import {database} from '@/db/raw';
import {setShowRoute,type PayrollState,type Show} from './payroll';
import type {CrmShowRow} from './crm-core';
// Only new periods receive source shows. Existing open periods and closed
// snapshots never change when a CRM price, deposit or Calendar event changes.
export async function importCrmPeriods(current:PayrollState,next:PayrollState){
 for(const p of next.periods){if(current.periods.some(old=>old.id===p.id))continue;
  const shows=(await database().prepare("SELECT * FROM jac_crm_shows WHERE status='active' AND source_state='present' AND sale_cents IS NOT NULL AND show_date>=? AND show_date<=? ORDER BY show_date,title,id").bind(p.start,p.end).all<CrmShowRow>()).results;
  for(const source of shows){
   if(p.shows.some(s=>s.crmShowId===source.id))continue;
   const show:Show={id:crypto.randomUUID(),name:source.title.slice(0,180),date:source.show_date,sale:source.sale_cents!/100,promotional:source.promotional===1,crmShowId:source.id,crmVersion:source.version,participants:next.employees.filter(e=>e.active&&!e.deleted&&['musicos','tecnica'].includes(e.category)).map(e=>({employeeId:e.id,amount:e.showRate}))};
   p.shows.push(show);const drivers=next.employees.filter(e=>e.active&&!e.deleted&&e.category==='conductores');if(drivers.length)setShowRoute(p,{id:crypto.randomUUID(),showId:show.id,name:show.name,date:show.date,km:0,drivers:drivers.map(e=>({employeeId:e.id,rate:e.kmRate}))});
  }
 }
 return next;
}
export function crmLinkIssue(current:PayrollState,next:PayrollState){
 for(const p of next.periods)for(const show of p.shows){const old=current.periods.find(x=>x.id===p.id)?.shows.find(x=>x.id===show.id);
  if(old?.crmShowId&&(show.crmShowId!==old.crmShowId||show.crmVersion!==old.crmVersion))return 'Actualiza el formulario para conservar el vínculo del show con el CRM.';
  if(!old?.crmShowId&&show.crmShowId)return 'Los vínculos del CRM se incorporan al crear la quincena.';
 }
 return null;
}
export function crmPayrollGuard(current:PayrollState,next:PayrollState){
 const sources=next.periods.filter(p=>!current.periods.some(old=>old.id===p.id)).flatMap(p=>p.shows.filter(s=>s.crmShowId).map(s=>[s.crmShowId,s.crmVersion,Math.round(s.sale*100),s.date]));
 return sources.length?{sql:"NOT EXISTS(SELECT 1 FROM json_each(?) expected WHERE NOT EXISTS(SELECT 1 FROM jac_crm_shows c WHERE c.id=json_extract(expected.value,'$[0]') AND c.version=json_extract(expected.value,'$[1]') AND c.sale_cents=json_extract(expected.value,'$[2]') AND c.show_date=json_extract(expected.value,'$[3]') AND c.status='active' AND c.source_state='present'))",bindings:[JSON.stringify(sources)]}:undefined;
}
