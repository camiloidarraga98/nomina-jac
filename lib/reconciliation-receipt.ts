import {z} from 'zod';
import {cents,CrmFailure} from './crm-core';

const plain=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
export function receiptDate(value:string):string|null {
 const v=plain(value).replace(/\bde\b/g,' ').replace(/[,]/g,' ').replace(/\s+/g,' ').trim();
 let year:number,month:number,day:number;
 let match=v.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
 if(match){[,year,month,day]=match.map(Number);}
 else if((match=v.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/))){[,day,month,year]=match.map(Number);}
 else {
  const months=[['ene','enero'],['feb','febrero'],['mar','marzo'],['abr','abril'],['may','mayo'],['jun','junio'],['jul','julio'],['ago','agosto'],['sep','sept','septiembre','setiembre'],['oct','octubre'],['nov','noviembre'],['dic','diciembre']];
  match=v.match(/^(\d{1,2})[\s/-]+([a-z]+)\.?[\s/-]+(\d{4})$/);
  if(!match)return null;
  day=Number(match[1]);month=months.findIndex(names=>names.includes(match![2]))+1;year=Number(match[3]);
 }
 if(year<2000||year>2100||month<1||month>12||day<1||day>31)return null;
 const iso=`${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
 return new Date(iso+'T12:00:00Z').toISOString().slice(0,10)===iso?iso:null;
}

/** Exact decimal parsing; grouped COP and international formats are accepted.
 * Account numbers, mixed text, negative values and ambiguous separators fail closed. */
export function receiptAmount(value:string):number|null {
 let v=value.trim().replace(/^(?:COP\s*\$?|\$\s*COP|\$)\s*/i,'').replace(/\s*(?:COP|pesos)\s*$/i,'').trim();
 if(/\s/.test(v)){
  if(!/^\d{1,3}(?:[\s\u00a0]\d{3})+(?:[.,]\d{1,2})?$/.test(v))return null;
  v=v.replace(/[\s\u00a0]/g,'');
 }
 if(!/^\d[\d.,]*$/.test(v))return null;
 let normalized='';
 if(/^\d+$/.test(v))normalized=v;
 else if(/^\d+[.,]\d{1,2}$/.test(v))normalized=v.replace(',','.');
 else if(/^\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?$/.test(v))normalized=v.replaceAll('.','').replace(',','.');
 else if(/^\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?$/.test(v))normalized=v.replaceAll(',','');
 else return null;
 const amount=Number(normalized);
 try{return amount>0?cents(amount)/100:null;}catch{return null;}
}

export const receiptReadingSchema=z.object({
 document:z.enum(['single_payment','multiple_payments','other','unreadable']),
 amountText:z.string().max(80).nullable(),
 dateText:z.string().max(80).nullable(),
 currency:z.enum(['COP','other','unknown']),
 transactionStatus:z.enum(['completed','pending','failed','unknown']),
 legible:z.boolean(),
}).strict();
export type ReceiptReading=ReturnType<typeof normalizeReceiptReading>;
export function normalizeReceiptReading(input:unknown){
 const parsed=receiptReadingSchema.safeParse(input);
 if(!parsed.success)throw new CrmFailure('No pudimos interpretar la lectura. Puedes completar el valor y la fecha manualmente.',422);
 const r=parsed.data;
 // Neither a date nor an amount is invented from the upload date, filename or bank balance.
 const amount=r.document==='single_payment'&&r.currency!=='other'&&r.amountText?receiptAmount(r.amountText):null;
 const date=r.document==='single_payment'&&r.dateText?receiptDate(r.dateText):null;
 const warnings:string[]=[];
 if(r.document==='multiple_payments')warnings.push('El archivo contiene varios pagos. Usa un comprobante por abono o elige el movimiento manualmente.');
 else if(r.document!=='single_payment')warnings.push('No se reconoce un único comprobante de pago. Revisa el archivo antes de relacionarlo.');
 if(r.currency!=='COP')warnings.push(r.currency==='other'?'El comprobante indica otra moneda. No se convierte a pesos automáticamente.':'Confirma que el valor esté expresado en pesos colombianos.');
 if(r.transactionStatus==='failed')warnings.push('El comprobante indica un pago rechazado o fallido. No confirma un abono recibido.');
 else if(r.transactionStatus!=='completed')warnings.push('No se pudo confirmar que la transferencia esté completada. Revisa su estado.');
 if(!r.legible)warnings.push('La lectura no es clara. Comprueba los datos con el original.');
 if(amount===null)warnings.push('Escribe o corrige el valor del pago.');
 if(!date)warnings.push('Escribe o corrige la fecha del pago.');
 const autoEligible=r.document==='single_payment'&&r.currency==='COP'&&r.transactionStatus==='completed'&&r.legible&&amount!==null&&date!==null;
 return {...r,amount,date,warnings,autoEligible};
}

export const receiptLookupSchema=z.object({
 amount:z.number().positive().max(1e12).refine(n=>{try{cents(n);return true;}catch{return false;}}).nullable(),
 date:z.string().refine(v=>/^\d{4}-\d{2}-\d{2}$/.test(v)&&receiptDate(v)===v).nullable(),
}).strict().refine(v=>v.amount!==null||v.date!==null);
export type ReceiptCandidate={id:string;version:number;date:string;amount:number;status:string;entrepreneur:string;showId:string};
export function matchReceiptPayments(payments:ReceiptCandidate[],criteria:{amount:number|null;date:string|null},autoEligible=false){
 const lookup=receiptLookupSchema.safeParse(criteria);
 if(!lookup.success)throw new CrmFailure('Indica un valor positivo con máximo dos decimales y/o una fecha válida.');
 const {amount,date}=lookup.data;
 const matches=payments.filter(p=>amount!==null?cents(p.amount)===cents(amount):p.date===date).map(p=>({...p,
  kind:amount!==null&&date&&p.date===date?'exact' as const:amount!==null?'amount' as const:'date' as const,
 })).sort((a,b)=>Number(b.kind==='exact')-Number(a.kind==='exact')||
  (date?Math.abs(Date.parse(a.date)-Date.parse(date))-Math.abs(Date.parse(b.date)-Date.parse(date)):0)||a.date.localeCompare(b.date)||a.id.localeCompare(b.id));
 const exact=matches.filter(p=>p.kind==='exact');
 // A date alone, amount alone, fuzzy match, already identified row or tie never auto-selects.
 const autoMatchId=autoEligible&&exact.length===1&&exact[0].status!=='identified'?exact[0].id:null;
 return {matches:matches.slice(0,100),total:matches.length,autoMatchId};
}
