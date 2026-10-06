export type Category='musicos'|'tecnica'|'conductores'|'administracion'|'comision';
export const categoryNames:Record<Category,string>={musicos:'Músicos',tecnica:'Técnica',conductores:'Conductores',administracion:'Dependientes',comision:'Comisiones y otros'};
export const hourNames=['Recargo nocturno','Recargo dominical diurno','Recargo dominical nocturno','Extra diurna','Extra nocturna','Extra dominical diurna','Extra dominical nocturna'];
export type Employee={id:string;name:string;document:string;role:string;category:Category;active:boolean;showRate:number;kmRate:number;fixedService:number;withholding:number;ica:number;salary:number;transport:number;pension:boolean;health:boolean;cycle:'quincenal'|'mensual';monthlyHalf:1|2;nonSalary:number;contributionBase:number;incomeTax:number;solidarity:number;deleted?:boolean;email?:string};
export type Concept={id:string;name:string;amount:number;kind:'servicio'|'reintegro'|'salarial'|'descuento'};
export type Show={id:string;date:string;name:string;sale:number;participants:{employeeId:string;amount:number}[]};
export type Movement={id:string;employeeId:string;concept:string;kind:Concept['kind'];quantity:number;amount:number;note:string};
export type Hours={employeeId:string;counts:number[];days:number;vacations:number;note:string};
export type LegacyRoute={id:string;employeeId:string;date:string;name:string;km:number;rate:number};
export type ShowRoute={id:string;showId:string;date:string;name:string;km:number;drivers:{employeeId:string;rate:number}[]};
export type ExtraRoute={id:string;kind:'extra';date:string;name:string;km:number;drivers:{employeeId:string;rate:number}[]};
export type Route=LegacyRoute|ShowRoute|ExtraRoute;
export const routeDrivers=(r:Route)=>'drivers' in r?r.drivers:[{employeeId:r.employeeId,rate:r.rate}];
export function legacyRoutesForShow(p:Period,show:Show):LegacyRoute[]{return p.routes.filter((r):r is LegacyRoute=>'employeeId' in r&&r.date===show.date&&(r.name.trim().toLocaleLowerCase('es')===show.name.trim().toLocaleLowerCase('es')||p.shows.filter(s=>s.date===show.date).length===1));}
export function setShowRoute(p:Period,r:ShowRoute){const show=p.shows.find(s=>s.id===r.showId);if(!show)throw new Error('El show no existe.');const old=new Set(legacyRoutesForShow(p,show).map(x=>x.id));p.routes=p.routes.filter(x=>!old.has(x.id)&&!('showId' in x&&x.showId===r.showId));p.routes.push({...r,date:show.date,name:show.name});}
export function updateShow(p:Period,s:Show){const i=p.shows.findIndex(x=>x.id===s.id);if(i<0)p.shows.push(s);else p.shows[i]=s;p.routes=p.routes.map(r=>'showId' in r&&r.showId===s.id?{...r,date:s.date,name:s.name}:r);}
export function removeShow(p:Period,id:string){p.shows=p.shows.filter(s=>s.id!==id);p.routes=p.routes.filter(r=>!('showId' in r&&r.showId===id));}
export type Item={concept:string;quantity:number;rate:number;amount:number;kind:'ingreso'|'deduccion'|'reintegro';reference?:string};
export type PayrollRow={employeeId:string;name:string;document:string;role:string;category:Category;gross:number;reimbursements:number;deductions:number;net:number;items:Item[]};
export type Snapshot={rows:PayrollRow[];sale:number;total:number;gross:number;deductions:number;reimbursements:number;company:string;nit:string;start:string;end:string;closedAt:string;closedBy:string;settings:Settings;employees:Employee[]};
export type Period={id:string;start:string;end:string;status:'abierta'|'cerrada';shows:Show[];movements:Movement[];hours:Hours[];routes:Route[];excludedEmployees:string[];snapshot?:Snapshot;revisions?:Snapshot[];calculationBase?:{employees:Employee[];settings:Settings};ownerOnly?:boolean;reopenedAt?:string;reopenedBy?:string};
export type Settings={company:string;nit:string;hourDivisor:number;hourFactors:number[]};
export type PayrollState={employees:Employee[];concepts:Concept[];settings:Settings;periods:Period[]};
export const round=(n:number)=>Math.round((n+Number.EPSILON)*100)/100;
export const money=(n:number)=>'$ '+Math.round(n).toLocaleString('es-CO',{maximumFractionDigits:0}).replace(/[\u00a0\u202f]/g,' ');
const months=['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
export const shortMonth=(date:string)=>['ene.','feb.','mar.','abr.','may.','jun.','jul.','ago.','sept.','oct.','nov.','dic.'][Number(date.slice(5,7))-1];
export function closedDate(date:string){const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'America/Bogota',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(date));const v=(type:string)=>parts.find(p=>p.type===type)?.value;return `${v('day')}/${v('month')}/${v('year')} ${v('hour')}:${v('minute')}`;}
export function periodLabel(p:Pick<Period,'start'|'end'>){return `${Number(p.start.slice(-2))}–${Number(p.end.slice(-2))} ${months[Number(p.start.slice(5,7))-1]} de ${p.start.slice(0,4)}`;}
export function newPeriod(start:string,end:string):Period{return {id:crypto.randomUUID(),start,end,status:'abierta',shows:[],movements:[],hours:[],routes:[],excludedEmployees:[]};}
export function calculate(state:PayrollState,p:Period):Omit<Snapshot,'closedAt'|'closedBy'|'employees'>{
 if(p.status==='cerrada'&&p.snapshot)return p.snapshot;
 if(p.calculationBase)state={...state,...p.calculationBase};
 const rows:PayrollRow[]=[];
 for(const e of state.employees){
  if(!e.active||e.deleted||p.excludedEmployees.includes(e.id))continue;
  const moves=p.movements.filter(m=>m.employeeId===e.id);
  const service:Item[]=[];
  for(const s of p.shows){const part=s.participants.find(x=>x.employeeId===e.id);if(part&&part.amount>0)service.push({concept:s.name,quantity:1,rate:part.amount,amount:part.amount,kind:'ingreso',reference:s.date});}
  for(const r of p.routes){const driver=routeDrivers(r).find(d=>d.employeeId===e.id);if(driver)service.push({concept:'kind' in r?'Kilometraje extra · '+r.name:r.name,quantity:r.km,rate:driver.rate,amount:round(r.km*driver.rate),kind:'ingreso',reference:r.date});}
  if(e.fixedService>0)service.push({concept:'Honorario fijo quincenal',quantity:1,rate:e.fixedService,amount:e.fixedService,kind:'ingreso'});
  for(const m of moves.filter(m=>m.kind==='servicio'))service.push({concept:m.concept+(m.note?' · '+m.note:''),quantity:m.quantity,rate:m.amount,amount:round(m.quantity*m.amount),kind:'ingreso'});
  if(service.length||(!e.salary&&moves.length)){
   const gross=round(service.reduce((v,x)=>v+x.amount,0));
   if(e.ica>0&&gross>0)service.push({concept:`ReteICA (${e.ica*100}%)`,quantity:1,rate:round(gross*e.ica),amount:round(gross*e.ica),kind:'deduccion'});
   if(e.withholding>0&&gross>0)service.push({concept:`Retención (${e.withholding*100}%)`,quantity:1,rate:round(gross*e.withholding),amount:round(gross*e.withholding),kind:'deduccion'});
   for(const m of moves.filter(m=>m.kind==='reintegro'||m.kind==='descuento'))service.push({concept:m.concept+(m.note?' · '+m.note:''),quantity:m.quantity,rate:m.amount,amount:round(m.quantity*m.amount),kind:m.kind==='reintegro'?'reintegro':'deduccion'});
   rows.push(makeRow(e,e.category,service));
  }
  const half=Number(p.start.slice(-2))<=15?1:2;
  if(e.salary>0&&(e.cycle==='quincenal'||e.monthlyHalf===half)){
   const h=p.hours.find(h=>h.employeeId===e.id);const days=h?.days??(e.cycle==='mensual'?30:15);
   const items:Item[]=[{concept:`Salario (${days} días)`,quantity:days,rate:round(e.salary/30),amount:round(e.salary*days/30),kind:'ingreso'}];
   const hourRate=e.salary/state.settings.hourDivisor;
   (h?.counts??Array(7).fill(0)).forEach((n,i)=>{if(n>0)items.push({concept:hourNames[i],quantity:n,rate:round(hourRate*state.settings.hourFactors[i]),amount:round(hourRate*state.settings.hourFactors[i]*n),kind:'ingreso'});});
   if(h?.vacations)items.push({concept:'Vacaciones',quantity:1,rate:h.vacations,amount:h.vacations,kind:'ingreso'});
   for(const m of moves.filter(m=>m.kind==='salarial'))items.push({concept:m.concept+(m.note?' · '+m.note:''),quantity:m.quantity,rate:m.amount,amount:round(m.quantity*m.amount),kind:'ingreso'});
   const taxable=round(items.reduce((v,x)=>v+x.amount,0)*e.contributionBase);
   if(e.transport>0)items.push({concept:'Auxilio de transporte',quantity:days,rate:round(e.transport/30),amount:round(e.transport*days/30),kind:'reintegro'});
   if(e.nonSalary>0)items.push({concept:'Movilización no salarial',quantity:1,rate:e.nonSalary,amount:e.nonSalary,kind:'reintegro'});
   if(e.health)items.push({concept:'EPS (4%)',quantity:1,rate:round(taxable*0.04),amount:round(taxable*0.04),kind:'deduccion'});
   if(e.pension)items.push({concept:'AFP (4%)',quantity:1,rate:round(taxable*0.04),amount:round(taxable*0.04),kind:'deduccion'});
   if(e.incomeTax>0)items.push({concept:'Retención de nómina',quantity:1,rate:e.incomeTax,amount:e.incomeTax,kind:'deduccion'});
   if(e.solidarity>0)items.push({concept:'Fondo de solidaridad pensional',quantity:1,rate:e.solidarity,amount:e.solidarity,kind:'deduccion'});
   // Shared identity: reimbursements/discounts apply once when a person also receives service pay.
   if(!service.length)for(const m of moves.filter(m=>m.kind==='reintegro'||m.kind==='descuento'))items.push({concept:m.concept+(m.note?' · '+m.note:''),quantity:m.quantity,rate:m.amount,amount:round(m.quantity*m.amount),kind:m.kind==='reintegro'?'reintegro':'deduccion'});
   rows.push(makeRow(e,'administracion',items));
  }
 }
 return {rows,sale:round(p.shows.reduce((v,s)=>v+s.sale,0)),total:round(rows.reduce((v,r)=>v+r.net,0)),gross:round(rows.reduce((v,r)=>v+r.gross,0)),deductions:round(rows.reduce((v,r)=>v+r.deductions,0)),reimbursements:round(rows.reduce((v,r)=>v+r.reimbursements,0)),company:state.settings.company,nit:state.settings.nit,start:p.start,end:p.end,settings:structuredClone(state.settings)};
}
function makeRow(e:Employee,category:Category,items:Item[]):PayrollRow{const sum=(k:Item['kind'])=>round(items.filter(x=>x.kind===k).reduce((v,x)=>v+x.amount,0));const gross=sum('ingreso'),reimbursements=sum('reintegro'),deductions=sum('deduccion');return {employeeId:e.id,name:e.name,document:e.document,role:e.role,category,gross,reimbursements,deductions,net:round(gross+reimbursements-deductions),items};}
export function closeIssues(state:PayrollState,p:Period):string[]{
 if(p.calculationBase)state={...state,...p.calculationBase};
 const result=calculate(state,p),issues:string[]=[];for(const r of result.rows)if(r.net<0)issues.push(`${r.name}: el neto es negativo.`);if(!result.rows.length)issues.push('La quincena no tiene pagos para cerrar.');
 const valid=(id:string)=>state.employees.find(e=>e.id===id&&e.active&&!e.deleted)&&!p.excludedEmployees.includes(id);
 for(const sh of p.shows)for(const part of sh.participants)if(!valid(part.employeeId))issues.push(`El show ${sh.name} contiene una persona excluida o inactiva. Revisa sus participantes.`);
 for(const r of p.routes)for(const d of routeDrivers(r))if(!valid(d.employeeId))issues.push(`El recorrido ${r.name} contiene una persona excluida o inactiva.`);
 for(const m of p.movements){if(!valid(m.employeeId))issues.push(`La novedad ${m.concept} corresponde a una persona excluida o inactiva.`);if(m.kind==='salarial'&&!result.rows.some(r=>r.employeeId===m.employeeId&&r.category==='administracion'))issues.push(`La novedad salarial ${m.concept} no tiene un salario en este corte.`);if(!result.rows.some(r=>r.employeeId===m.employeeId))issues.push(`La novedad ${m.concept} no está incluida en un pago. Revisa la frecuencia de la persona.`);}
 for(const h of p.hours)if((h.counts.some(n=>n>0)||h.vacations>0)&&!result.rows.some(r=>r.employeeId===h.employeeId&&r.category==='administracion'))issues.push('Hay horas o vacaciones de una persona fuera de este corte.');
 return [...new Set(issues)];
}
