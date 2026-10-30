import {payrollPdf} from './payroll-pdf';
export {payrollPdf} from './payroll-pdf';
import {zipSync} from 'fflate';
import {documentWorkbook,type DocumentExcelCell as Cell,type DocumentExcelSheet as Sheet} from './document-xlsx';
import {documentDate} from './document-brand';
import {calculate,closeIssues,normalizeRehearsalMovements,periodLabel,categoryNames,routeDrivers,payrollGeneral,showHonorarium,type Period,type Snapshot,type PayrollState} from './payroll';
export type PayrollReview={calculation:Omit<Snapshot,'closedAt'|'closedBy'>;generatedAt:string;version:number;issues:string[]};
/** An ephemeral review of saved inputs, never a closure or a mail batch. */
export function payrollReview(state:PayrollState,period:Period,version:number,generatedAt=new Date().toISOString()){
 if(period.status!=='abierta')throw new Error('La preliquidación requiere una quincena abierta.');
 const p=normalizeRehearsalMovements(period),calculation=calculate(state,p);
 const review:PayrollReview={calculation:{...calculation,employees:structuredClone(p.calculationBase?.employees??state.employees)},generatedAt,version,issues:[...new Set([...closeIssues(state,p),...(calculation.camiloCommission?.issues??[])])]};
 return {period:p,review};
}
export function payrollXlsx(p:Period,review?:PayrollReview){const s=review?.calculation??p.snapshot!;
 const rows:Cell[][]=[[s.company+(review?' - PRELIQUIDACIÓN · PARA REVISIÓN':' - Resumen de nómina')],[p.start+' al '+p.end],[review?'Quincena abierta · Generada: '+review.generatedAt+' · Versión '+review.version:'Cierre: '+p.snapshot!.closedAt+' | '+p.snapshot!.closedBy],['Persona','Documento','Cargo','Grupo','Devengado','Adiciones y reintegros','Descuentos','Neto a pagar']];
 s.rows.forEach((r,i)=>rows.push([r.name,r.document,r.role,categoryNames[r.category],r.gross,r.reimbursements,r.deductions,{formula:`E${i+5}+F${i+5}-G${i+5}`,value:r.net}]));
 const last=rows.length,general=payrollGeneral(s),sum=(column:string,value:number)=>({formula:last<5?'0':`SUM(${column}5:${column}${last})`,value});
 rows.push(['Camilo Idarraga','','','Comisión del 5%',general.camilo??'Pendiente de revisión',0,0,general.camilo??'Pendiente de revisión']);
 const commissionRow=rows.length;
 rows.push(['TOTAL EQUIPO','','','',sum('E',s.gross),sum('F',s.reimbursements),sum('G',s.deductions),sum('H',s.total)]);
 const teamRow=rows.length;
 rows.push(['TOTAL GENERAL','','','',general.gross===null?'Pendiente de revisión':{formula:`E${teamRow}+E${commissionRow}`,value:general.gross},s.reimbursements,s.deductions,general.total===null?'Pendiente de revisión':{formula:`H${teamRow}+H${commissionRow}`,value:general.total}]);
 const detail:Cell[][]=[['Persona','Documento','Grupo','Concepto','Referencia','Cantidad','Valor unitario','Ingreso','Reintegro','Deducción']];
 for(const r of s.rows)for(const x of r.items)detail.push([r.name,r.document,categoryNames[r.category],x.concept,x.reference||'',x.quantity,x.rate,x.kind==='ingreso'?x.amount:0,x.kind==='reintegro'?x.amount:0,x.kind==='deduccion'?x.amount:0]);
 const shows:Cell[][]=[['Fecha','Show','Venta','Persona','Tarifa completa','Porcentaje','Honorario liquidado']];for(const sh of p.shows){if(!sh.participants.length)shows.push([sh.date,sh.name,sh.sale,'',0,'',0]);sh.participants.forEach((part,i)=>shows.push([sh.date,sh.name,i===0?sh.sale:0,s.employees.find(e=>e.id===part.employeeId)?.name||part.employeeId,part.amount,sh.promotional&&sh.halfPay?'50%':'100%',{formula:sh.promotional&&sh.halfPay?`ROUND(E${shows.length+1}*0.5,2)`:`E${shows.length+1}*1`,value:showHonorarium(sh,part.amount)}]));}
 const movements:Cell[][]=[['Persona','Concepto','Tratamiento','Cantidad','Valor unitario','Total','Observación']];for(const m of p.movements)movements.push([s.employees.find(e=>e.id===m.employeeId)?.name||m.employeeId,m.concept,m.kind,m.quantity,m.amount,{formula:`D${movements.length+1}*E${movements.length+1}`,value:m.quantity*m.amount},m.note]);
 const hours:Cell[][]=[['Persona','Días','Vacaciones','Recargo nocturno','Dominical diurno','Dominical nocturno','Extra diurna','Extra nocturna','Extra dominical diurna','Extra dominical nocturna','Observación']];for(const h of p.hours)hours.push([s.employees.find(e=>e.id===h.employeeId)?.name||h.employeeId,h.days,h.vacations,...h.counts,h.note]);
 const routes:Cell[][]=[['Fecha','Conductor','Show / recorrido','Kilómetros','Tarifa por km','Valor bruto']];for(const r of p.routes)for(const d of routeDrivers(r))routes.push([r.date,s.employees.find(e=>e.id===d.employeeId)?.name||d.employeeId,'kind' in r?'Kilometraje extra · '+r.name:r.name,r.km,d.rate,{formula:`D${routes.length+1}*E${routes.length+1}`,value:r.km*d.rate}]);
 const params:Cell[][]=[['Parámetro','Valor'],['Empresa',s.company],['NIT',s.nit],['Divisor mensual de horas',s.settings.hourDivisor],...s.settings.hourFactors.map((v,i)=>[['Recargo nocturno','Dominical diurno','Dominical nocturno','Extra diurna','Extra nocturna','Extra dominical diurna','Extra dominical nocturna'][i],v] as Cell[]),[],['Persona','Documento','Tarifa show','Tarifa km','Fijo quincenal','Salario mensual','Auxilio mensual','Retención servicios','ReteICA','AFP','Frecuencia','Corte mensual','Movilización','Base aportes','Retención nómina','FSP']];s.employees.forEach(e=>params.push([e.name,e.document,e.showRate,e.kmRate,e.fixedService,e.salary,e.transport,e.withholding,e.ica,e.pension?'Sí':'No',e.cycle,e.monthlyHalf,e.nonSalary,e.contributionBase,e.incomeTax,e.solidarity]));
 const sheets:Sheet[]=[{name:'Resumen',rows,widths:[38,18,26,19,20,23,20,20],header:4,moneyCols:[4,5,6,7],rowStyles:{[teamRow]:'team',[rows.length]:'total'}},{name:'Detalle',rows:detail,widths:[48,18,22,52,18,15,20,20,20,20],header:1,moneyCols:[6,7,8,9]},{name:'Shows',rows:shows,widths:[15,35,20,48,20,15,23],header:1,moneyCols:[2,4,6]},{name:'Novedades',rows:movements,widths:[48,35,20,15,20,20,55],header:1,moneyCols:[4,5]},{name:'Horas',rows:hours,widths:[48,12,20,20,20,20,20,20,24,24,55],header:1,moneyCols:[2]},{name:'Recorridos',rows:routes,widths:[15,48,35,15,20,20],header:1,moneyCols:[4,5]},{name:'Parámetros',rows:params,widths:[35,18,16,16,16,16,16,15,12,12,15,14,16,15,16,12],header:1,moneyCols:[],sectionHeaders:[13],filter:false}];
 if(review)sheets.push({name:'Revisión',rows:[['Comprobación','Detalle'],['Estado','PRELIQUIDACIÓN · PARA REVISIÓN'],['Quincena','Abierta; valores sujetos a cambios.'],['Versión',review.version],['Generada',documentDate(review.generatedAt)+' · Hora Colombia'],['Pendientes',review.issues.length],...review.issues.map((issue,i)=>['Pendiente '+(i+1),issue])],widths:[38,90],header:1,moneyCols:[],filter:false});
 return documentWorkbook(sheets,{title:review?'Preliquidación de nómina':'Resumen de nómina',company:s.company,nit:s.nit,review:!!review,
  context:periodLabel(p)+' · '+(review?'PRELIQUIDACIÓN · PARA REVISIÓN · '+documentDate(review.generatedAt)+' · Versión '+review.version:'Cierre: '+documentDate(p.snapshot!.closedAt)+' · '+p.snapshot!.closedBy)+' · Hora Colombia'});
}

export async function payrollSlipZip(p:Period){const files:Record<string,Uint8Array>={};for(const eid of [...new Set(p.snapshot!.rows.map(r=>r.employeeId))]){const r=p.snapshot!.rows.find(r=>r.employeeId===eid)!;const name=r.name.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-zA-Z0-9_-]/g,'_');files[`${name}_${eid}.pdf`]=await payrollPdf(p,eid);}return zipSync(files,{level:6});}
