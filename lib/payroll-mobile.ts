import {calculate,closeIssues,legacyRoutesForShow,type PayrollState,type Period} from './payroll';

// Mobile clients display the same server calculations and historical snapshots as the web.
export function mobileOverview(data:PayrollState,version:number){
 return {
  version,company:data.settings.company,
  periods:data.periods.map(p=>({id:p.id,start:p.start,end:p.end,status:p.status,showCount:p.shows.length,ownerOnly:!!p.ownerOnly,closedAt:p.snapshot?.closedAt??null})),
  employees:data.employees,
 };
}

export function mobilePeriod(data:PayrollState,p:Period,version:number){
 const employees=p.snapshot?.employees??p.calculationBase?.employees??data.employees;
 const drivers=employees.filter(e=>e.active&&!e.deleted&&e.category==='conductores'&&!p.excludedEmployees.includes(e.id));
 return {
  version,period:p,
  employees,
  calculation:calculate(data,p),
  closeIssues:p.status==='cerrada'?[]:closeIssues(data,p),
  editing:{
   settings:p.snapshot?.settings??p.calculationBase?.settings??data.settings,
   concepts:data.concepts,
   drivers:drivers.map(e=>({employeeId:e.id,rate:e.kmRate})),
   showRoutes:p.shows.map(show=>{
    const existing=p.routes.find(r=>'showId' in r&&r.showId===show.id);if(existing)return existing;
    const previous=legacyRoutesForShow(p,show),ids=[...new Set(previous.map(r=>r.employeeId))];
    const distances=ids.map(id=>previous.filter(r=>r.employeeId===id).reduce((total,r)=>total+r.km,0));
    return {id:crypto.randomUUID(),showId:show.id,date:show.date,name:show.name,km:distances.length&&distances.every(km=>km===distances[0])?distances[0]:0,drivers:drivers.map(e=>({employeeId:e.id,rate:previous.find(r=>r.employeeId===e.id)?.rate??e.kmRate})),legacyCount:previous.length};
   }),
  },
 };
}
