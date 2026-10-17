import {z} from 'zod';

const text=(label:string,max:number)=>z.string().trim().min(1,`Completa ${label}.`).max(max,`${label}: máximo ${max} caracteres.`).refine(v=>!/[\u0000-\u001f\u007f]/.test(v),`${label}: no se admiten saltos de línea ni controles.`).transform(v=>v.normalize('NFC').replace(/\s+/g,' ')).refine(v=>/^[\u0020-\u007e\u00a0-\u00ff–—‘’“”€]+$/.test(v),`${label}: usa letras, números y signos habituales en español.`);
function validDate(v:string){if(!/^\d{4}-\d{2}-\d{2}$/.test(v))return false;const d=new Date(v+'T12:00:00Z');return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===v&&v>='1900-01-01'&&v<='2199-12-31';}
const date=z.string().refine(validDate,'Introduce una fecha válida.');
export const contractInput=z.object({
 company:text('la empresa contratante',100),nit:text('el NIT',25),representative:text('el representante legal',90),identity:text('la cédula',25),
 eventDate:date,venue:text('el sitio del evento',100),municipality:text('el municipio',60),department:text('el departamento',40),
 showTime:z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/,'Introduce la hora del show.'),
 price:z.number().int('Introduce el precio en pesos enteros.').positive('El precio debe ser mayor que cero.').max(1e12),
 deposited:z.number().int('Introduce el abono en pesos enteros.').min(0).max(1e12),halfDeadline:date,
}).strict().superRefine((v,ctx)=>{
 if(v.deposited>v.price/2)ctx.addIssue({code:'custom',path:['deposited'],message:'En esta plantilla el abono no puede superar el 50% del contrato.'});
 if(validDate(v.eventDate)&&validDate(v.halfDeadline)&&v.halfDeadline>contractFinalDate(v.eventDate))ctx.addIssue({code:'custom',path:['halfDeadline'],message:'El plazo para completar el 50% debe ser anterior o igual al pago final, cinco días antes del show.'});
});
export type ContractInput=z.infer<typeof contractInput>;
const small=['cero','uno','dos','tres','cuatro','cinco','seis','siete','ocho','nueve','diez','once','doce','trece','catorce','quince','dieciséis','diecisiete','dieciocho','diecinueve','veinte','veintiuno','veintidós','veintitrés','veinticuatro','veinticinco','veintiséis','veintisiete','veintiocho','veintinueve'];
const tens=['','','','treinta','cuarenta','cincuenta','sesenta','setenta','ochenta','noventa'];
const hundreds=['','ciento','doscientos','trescientos','cuatrocientos','quinientos','seiscientos','setecientos','ochocientos','novecientos'];
function apocope(v:string){return v.replace(/veintiuno$/,'veintiún').replace(/uno$/,'un');}
export function spanishInteger(n:number):string{
 if(!Number.isSafeInteger(n)||n<0||n>1e12)throw new Error('Valor fuera del rango del contrato.');
 if(n<30)return small[n];if(n<100)return tens[Math.floor(n/10)]+(n%10?' y '+small[n%10]:'');
 if(n===100)return 'cien';if(n<1000)return hundreds[Math.floor(n/100)]+(n%100?' '+spanishInteger(n%100):'');
 if(n<1e6){const k=Math.floor(n/1000);return (k===1?'mil':apocope(spanishInteger(k))+' mil')+(n%1000?' '+spanishInteger(n%1000):'');}
 if(n<1e12){const m=Math.floor(n/1e6);return (m===1?'un millón':apocope(spanishInteger(m))+' millones')+(n%1e6?' '+spanishInteger(n%1e6):'');}
 return 'un billón';
}
export function contractMoneyWords(value:number){
 const cents=Math.round(value*100);if(!Number.isSafeInteger(cents)||value<0||value>1e12)throw new Error('Valor fuera del rango del contrato.');
 const whole=Math.floor(cents/100),fraction=cents%100;
 const pesos=apocope(spanishInteger(whole))+(whole>0&&whole%1e6===0?' de pesos':whole===1?' peso':' pesos');
 return (pesos+(fraction?' con '+apocope(spanishInteger(fraction))+(fraction===1?' centavo':' centavos'):'')).toLocaleUpperCase('es-CO');
}
export const contractMoney=(v:number)=>v.toLocaleString('es-CO',{maximumFractionDigits:2});
export function contractFinalDate(date:string){const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()-5);return d.toISOString().slice(0,10);}
export function contractDate(date:string,weekday=true,year=true){return new Intl.DateTimeFormat('es-CO',{timeZone:'UTC',...(weekday?{weekday:'long'}:{}),day:'numeric',month:'long',...(year?{year:'numeric'}:{})}).format(new Date(date+'T12:00:00Z')).replace(',', '');}
export function contractTime(time:string){const [h,m]=time.split(':').map(Number);return `${h%12||12}:${String(m).padStart(2,'0')} ${h>=12?'pm':'am'}`;}
export function contractFilename(v:Pick<ContractInput,'eventDate'|'municipality'>){const [year,,day]=v.eventDate.split('-').map(Number),month=new Intl.DateTimeFormat('es-CO',{month:'long',timeZone:'UTC'}).format(new Date(v.eventDate+'T12:00:00Z'));const town=v.municipality.normalize('NFC').replace(/[^\p{L}\p{N} .-]/gu,'').trim();return `Contrato JAC - ${town} ${spanishInteger(day)} de ${month} de ${spanishInteger(year)}.pdf`;}
