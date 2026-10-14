import {newPeriod,updateShow,removeShow,setShowRoute,movementPaymentKind,type PayrollState,type Period,type Employee,type Concept,type Show,type Movement,type Hours,type Route,type ShowRoute,type Settings,type ShowExpense} from './payroll';

export type MobileEdit={kind:string;periodId?:string;record?:Record<string,unknown>;id?:string};
export class MobileEditError extends Error{}

// These are UI commands. Validation, permissions, history, CAS and side effects
// remain in the shared payroll save/action endpoint.
export function applyMobileEdit(current:PayrollState,edit:MobileEdit,remove=false):PayrollState{
 const next=structuredClone(current),record=edit.record;
 const period=()=>{const p=next.periods.find(p=>p.id===edit.periodId);if(!p)throw new MobileEditError('La quincena no existe. Actualiza el listado.');return p;};
 const upsert=<T>(items:T[],value:T,key:(item:T)=>unknown)=>{const i=items.findIndex(x=>key(x)===key(value));if(i<0)items.push(value);else items[i]=value;};
 if(remove){
  const p=period();if(typeof edit.id!=='string')throw new MobileEditError('Selecciona el registro que deseas eliminar.');
  if(edit.kind==='show')removeShow(p,edit.id);
  else if(edit.kind==='showExpense')p.showExpenses=(p.showExpenses||[]).filter(x=>x.id!==edit.id);
  else if(edit.kind==='movement')p.movements=p.movements.filter(x=>x.id!==edit.id);
  else if(edit.kind==='route')p.routes=p.routes.filter(x=>x.id!==edit.id);
  else throw new MobileEditError('Esta eliminación no está disponible.');
  return next;
 }
 if(!record||Array.isArray(record)||typeof record!=='object')throw new MobileEditError('Revisa los datos del formulario.');
 switch(edit.kind){
  case 'period':{
   if(typeof record.id!=='string'||typeof record.start!=='string'||typeof record.end!=='string'||next.periods.some(p=>p.id===record.id))throw new MobileEditError('Revisa las fechas de la nueva quincena.');
   next.periods.push({...newPeriod(record.start,record.end),id:record.id});break;
  }
  case 'employee':upsert(next.employees,record as Employee,x=>x.id);break;
  case 'concept':upsert(next.concepts,record as Concept,x=>x.id);break;
  case 'settings':next.settings=record as Settings;break;
  case 'show':updateShow(period(),record as Show);break;
  case 'showExpense':{const p=period();p.showExpenses??=[];upsert(p.showExpenses,record as ShowExpense,x=>x.id);break;}
  case 'movement':{const movement=record as Movement;upsert(period().movements,{...movement,kind:movementPaymentKind(movement)},x=>x.id);break;}
  case 'hours':upsert(period().hours,record as Hours,x=>x.employeeId);break;
  case 'route':{
   const p=period();if('showId' in record)setShowRoute(p,record as ShowRoute);else upsert(p.routes,record as Route,x=>x.id);break;
  }
  case 'periodEmployee':{
   const p=period(),employees=p.calculationBase?.employees;if(!p.ownerOnly||!employees)throw new MobileEditError('Reabre el cierre antes de corregir sus condiciones.');
   const i=employees.findIndex(x=>x.id===record.id);if(i<0)throw new MobileEditError('La persona no existe en las condiciones de este corte.');employees[i]=record as Employee;break;
  }
  case 'periodSettings':{
   const p=period();if(!p.ownerOnly||!p.calculationBase)throw new MobileEditError('Reabre el cierre antes de corregir sus parámetros.');p.calculationBase.settings=record as Settings;break;
  }
  default:throw new MobileEditError('Formulario no disponible.');
 }
 return next;
}
