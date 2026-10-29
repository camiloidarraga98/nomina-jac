import {calculate,payrollGeneral,closeIssues,legacyRoutesForShow,normalizeRehearsalMovements,type PayrollState,type Period} from './payroll';
import {routeParticipantOptions,routePayees,defaultRouteParticipant} from './payroll-routes';

// Mobile clients display the same server calculations and historical snapshots as the web.
export function mobileOverview(data:PayrollState,version:number){
 return {
  version,company:data.settings.company,
  periods:data.periods.map(p=>({id:p.id,start:p.start,end:p.end,status:p.status,showCount:p.shows.length,ownerOnly:!!p.ownerOnly,closedAt:p.snapshot?.closedAt??null})),
  employees:data.employees,
 };
}

export function mobilePeriod(data:PayrollState,p:Period,version:number){
 p=normalizeRehearsalMovements(p);
 const employees=p.snapshot?.employees??p.calculationBase?.employees??data.employees;
 const drivers=routePayees(employees,p.excludedEmployees).filter(defaultRouteParticipant);
 const calculation=calculate(data,p);
 return {
  version,period:p,
  employees,
  calculation:{...calculation,general:payrollGeneral(calculation)},
  closeIssues:p.status==='cerrada'?[]:closeIssues(data,p),
  editing:{
   settings:p.snapshot?.settings??p.calculationBase?.settings??data.settings,
   concepts:data.concepts,
   drivers:drivers.map(e=>({employeeId:e.id,rate:e.kmRate})),
   routeParticipants:routeParticipantOptions(employees,p.excludedEmployees),
   showRoutes:p.shows.map(show=>{
    const existing=p.routes.find(r=>'showId' in r&&r.showId===show.id);if(existing)return existing;
    const previous=legacyRoutesForShow(p,show),ids=[...new Set(previous.map(r=>r.employeeId))];
    const distances=ids.map(id=>previous.filter(r=>r.employeeId===id).reduce((total,r)=>total+r.km,0));
    const selected=routePayees(employees,p.excludedEmployees).filter(e=>defaultRouteParticipant(e)||ids.includes(e.id));
    return {id:crypto.randomUUID(),showId:show.id,date:show.date,name:show.name,km:distances.length&&distances.every(km=>km===distances[0])?distances[0]:0,drivers:selected.map(e=>({employeeId:e.id,rate:previous.find(r=>r.employeeId===e.id)?.rate??e.kmRate})),legacyCount:previous.length};
   }),
  },
 };
}
