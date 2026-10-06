import {z} from 'zod';
const amount=z.number().finite().min(0).max(1e12),id=z.string().min(1).max(80),str=z.string().max(180),date=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(s=>!Number.isNaN(Date.parse(s))&&new Date(s+'T12:00:00Z').toISOString().slice(0,10)===s,'Fecha inválida');
const employee=z.object({id,name:str.min(2),document:str,role:str,category:z.enum(['musicos','tecnica','conductores','administracion','comision']),active:z.boolean(),showRate:amount,kmRate:amount,fixedService:amount,withholding:z.number().min(0).max(1),ica:z.number().min(0).max(1),salary:amount,transport:amount,pension:z.boolean(),health:z.boolean(),cycle:z.enum(['quincenal','mensual']),monthlyHalf:z.union([z.literal(1),z.literal(2)]),nonSalary:amount,contributionBase:z.number().min(0).max(1),incomeTax:amount,solidarity:amount,deleted:z.boolean().optional(),email:z.union([z.literal(''),z.string().trim().email().max(254)]).optional()});
const movement=z.object({id,employeeId:id,concept:str.min(1),kind:z.enum(['servicio','reintegro','salarial','descuento']),quantity:z.number().finite().min(0.01).max(10000),amount,note:z.string().max(500)});
const route=z.union([z.object({id,kind:z.literal('extra'),date,name:str.min(1),km:z.number().finite().min(.01).max(50000),drivers:z.array(z.object({employeeId:id,rate:amount})).min(1).max(200)}),z.object({id,showId:id,date,name:str.min(1),km:z.number().finite().min(0).max(50000),drivers:z.array(z.object({employeeId:id,rate:amount})).min(1).max(200)}),z.object({id,employeeId:id,date,name:str.min(1),km:z.number().finite().min(0).max(50000),rate:amount})]);
const period=z.object({id,start:date,end:date,status:z.enum(['abierta','cerrada']),shows:z.array(z.object({id,date,name:str.min(1),sale:amount,participants:z.array(z.object({employeeId:id,amount})).max(200)})).max(200),movements:z.array(movement).max(2000),hours:z.array(z.object({employeeId:id,counts:z.array(z.number().finite().min(0).max(744)).length(7),days:z.number().finite().min(0).max(30),vacations:amount,note:z.string().max(500)})).max(200),routes:z.array(route).max(2000),excludedEmployees:z.array(id).max(200),snapshot:z.any().optional(),revisions:z.array(z.any()).max(50).optional(),calculationBase:z.object({employees:z.array(employee).max(200),settings:z.object({company:str.min(1),nit:str,hourDivisor:z.number().min(1).max(744),hourFactors:z.array(z.number().finite().min(0).max(5)).length(7)})}).optional(),ownerOnly:z.boolean().optional(),reopenedAt:z.string().optional(),reopenedBy:str.optional()});
export const stateSchema=z.object({employees:z.array(employee).max(200),concepts:z.array(z.object({id,name:str.min(1),amount,kind:z.enum(['servicio','reintegro','salarial','descuento'])})).max(200),settings:z.object({company:str.min(1),nit:str,hourDivisor:z.number().min(1).max(744),hourFactors:z.array(z.number().finite().min(0).max(5)).length(7)}),periods:z.array(period).max(240)}).superRefine((s,ctx)=>{
 const error=(message:string)=>ctx.addIssue({code:z.ZodIssueCode.custom,message});
 const unique=(xs:string[])=>new Set(xs).size===xs.length;
 if(!unique(s.employees.map(e=>e.id))||!unique(s.periods.map(p=>p.id))||!unique(s.concepts.map(c=>c.id)))error('Hay identificadores repetidos.');
 const employeeIds=new Set(s.employees.map(e=>e.id));
 const sorted=s.periods.slice().sort((a,b)=>a.start.localeCompare(b.start));
 for(let i=0;i<sorted.length;i++){
  const p=sorted[i];const periodEmployees=p.calculationBase?.employees||(Array.isArray(p.snapshot?.employees)?p.snapshot.employees:s.employees);if(p.calculationBase&&!unique(p.calculationBase.employees.map(e=>e.id)))error('Hay personas repetidas en las condiciones del corte.');const periodEmployeeIds=new Set([...employeeIds,...(p.calculationBase?.employees.map(e=>e.id)||[])]);if(p.start>p.end||p.start.slice(0,7)!==p.end.slice(0,7))error('El período debe quedar dentro de un mes.');
  if(i&&p.start<=sorted[i-1].end)error('Las quincenas no pueden superponerse.');
  if(!unique(p.shows.map(x=>x.id))||!unique(p.movements.map(x=>x.id))||!unique(p.routes.map(x=>x.id))||!unique(p.hours.map(x=>x.employeeId)))error('Hay registros repetidos en la quincena.');
  for(const sh of p.shows){if(sh.date<p.start||sh.date>p.end)error('La fecha del show está fuera de la quincena.');if(!unique(sh.participants.map(x=>x.employeeId)))error('Una persona no puede repetirse en el mismo show.');}
  const shared=p.routes.filter(r=>'showId' in r);
  if(!unique(shared.map(r=>r.showId)))error('Solo se registra un kilometraje por show.');
  for(const r of p.routes){
   if(r.date<p.start||r.date>p.end)error('La fecha de un recorrido está fuera de la quincena.');
   if('drivers' in r){
    if(!unique(r.drivers.map(d=>d.employeeId)))error('Un conductor no puede repetirse en un recorrido.');
    for(const d of r.drivers)if(!(periodEmployees as z.infer<typeof employee>[]).some(e=>e.id===d.employeeId&&e.category==='conductores'))error('El pago por kilómetros solo corresponde a conductores.');
   }
   if('showId' in r){
    const show=p.shows.find(sh=>sh.id===r.showId);
    if(!show)error('El kilometraje debe corresponder a un show de esta quincena.');
    else if(r.date!==show.date||r.name!==show.name)error('El recorrido debe conservar el nombre y la fecha del show.');
    if(show&&p.routes.some(old=>'employeeId' in old&&old.date===show.date&&(old.name.trim().toLocaleLowerCase('es')===show.name.trim().toLocaleLowerCase('es')||p.shows.filter(sh=>sh.date===show.date).length===1)))error('Consolida los recorridos anteriores de este show para evitar pagos duplicados.');
   }
  }
  for(const eid of [...p.shows.flatMap(sh=>sh.participants.map(x=>x.employeeId)),...p.movements.map(x=>x.employeeId),...p.routes.flatMap(x=>'drivers' in x?x.drivers.map(d=>d.employeeId):[x.employeeId]),...p.hours.map(x=>x.employeeId),...p.excludedEmployees])if(!periodEmployeeIds.has(eid))error('Hay una referencia a un empleado inexistente.');
  for(const sh of p.shows)for(const part of sh.participants)if((periodEmployees as z.infer<typeof employee>[]).find(e=>e.id===part.employeeId)?.category==='conductores')error('Los conductores se liquidan por recorridos, no por show.');
 }
});
