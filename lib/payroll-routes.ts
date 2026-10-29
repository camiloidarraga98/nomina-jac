import type {Employee} from './payroll';

// Stable payroll identities, independent of login accounts or display names.
export const andresRouteEmployeeId='emp-18';
const marianoEmployeeId='emp-19';
export const canReceiveRoutePay=(e:Pick<Employee,'id'|'category'>)=>e.category==='conductores'||e.id===andresRouteEmployeeId;
export const defaultRouteParticipant=(e:Pick<Employee,'id'|'category'>)=>e.category==='conductores'&&e.id!==andresRouteEmployeeId;
export function onlyRouteParticipant(drivers:{employeeId:string;rate:number}[],person:Pick<Employee,'id'|'kmRate'>){
 return [{employeeId:person.id,rate:drivers.find(d=>d.employeeId===person.id)?.rate??person.kmRate}];
}
export function routePayees(employees:Employee[],excluded:string[]=[]):Employee[]{
 const mariano=employees.find(e=>e.id===marianoEmployeeId);
 return employees.filter(e=>e.active&&!e.deleted&&!excluded.includes(e.id)&&canReceiveRoutePay(e)).map(e=>e.id===andresRouteEmployeeId?{...e,kmRate:mariano?.kmRate??1250}:e);
}
export function routeParticipantOptions(employees:Employee[],excluded:string[]=[]){
 return routePayees(employees,excluded).map(e=>({employeeId:e.id,name:e.name,rate:e.kmRate,selectedByDefault:defaultRouteParticipant(e),...(e.id===andresRouteEmployeeId?{selectAloneLabel:'Solo Andrés Rey'}:{})}));
}
