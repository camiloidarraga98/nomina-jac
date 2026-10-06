import {calculate,closeIssues,type PayrollState,type Period} from './payroll';

// Mobile clients display the same server calculations and historical snapshots as the web.
export function mobileOverview(data:PayrollState,version:number){
 return {
  version,company:data.settings.company,
  periods:data.periods.map(p=>({id:p.id,start:p.start,end:p.end,status:p.status,showCount:p.shows.length,ownerOnly:!!p.ownerOnly,closedAt:p.snapshot?.closedAt??null})),
  employees:data.employees,
 };
}

export function mobilePeriod(data:PayrollState,p:Period,version:number){
 return {
  version,period:p,
  employees:p.snapshot?.employees??p.calculationBase?.employees??data.employees,
  calculation:calculate(data,p),
  closeIssues:p.status==='cerrada'?[]:closeIssues(data,p),
 };
}
