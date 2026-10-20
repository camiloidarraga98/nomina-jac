import {z} from 'zod';
import {agendaDate,addAgendaDays,validAgendaDate} from './calendar-core';
import {calculate,round,type PayrollState,type Period} from './payroll';
import {cents,type CrmShowRow} from './crm-core';
export const budgetLabels={musicians:'Músicos',technical:'Técnica',drivers:'Conductores y kilómetros',tickets:'Tiquetes',hotels:'Hoteles',food:'Alimentación',other:'Otros gastos'};
export type Budget=Record<keyof typeof budgetLabels,number>;
const amount=z.number().min(0).max(1e12).refine(n=>{try{cents(n);return true;}catch{return false;}});
export const budgetSchema=z.object({musicians:amount,technical:amount,drivers:amount,tickets:amount,hotels:amount,food:amount,other:amount}).strict();
export const defaultTasks=()=>['Contrato firmado','Hotel','Transporte','Itinerario'].map((title,i)=>({id:['contract','hotel','transport','itinerary'][i],title,status:'pending' as 'pending'|'done'|'na',responsible:'',dueDate:'',note:''}));
export const taskSchema=z.object({id:z.string().min(1).max(64),title:z.string().trim().min(1).max(120),status:z.enum(['pending','done','na']),responsible:z.string().trim().max(100),dueDate:z.string().refine(s=>s===''||validAgendaDate(s)),note:z.string().trim().max(500)}).strict();
export type CrmTask=z.infer<typeof taskSchema>;
export const planInput=z.object({showId:z.string().uuid(),version:z.number().int().nonnegative(),budget:budgetSchema.nullable(),tasks:z.array(taskSchema).min(4).max(30).refine(tasks=>new Set(tasks.map(t=>t.id)).size===tasks.length&&defaultTasks().every(d=>tasks.some(t=>t.id===d.id)))}).strict();
export const contactInput=z.object({id:z.string().uuid(),version:z.number().int().nonnegative(),name:z.string().trim().min(1).max(200),company:z.string().trim().max(200),phone:z.string().trim().max(60),email:z.union([z.literal(''),z.string().email().max(254)]),city:z.string().trim().max(120),note:z.string().trim().max(2000)}).strict();
export function crmWeek(day=agendaDate()){if(!validAgendaDate(day))throw Error('Selecciona una semana válida.');const d=new Date(day+'T12:00:00Z'),offset=(d.getUTCDay()+6)%7,from=addAgendaDays(day,-offset);return {from,to:addAgendaDays(from,6),today:agendaDate()};}
export type PayrollLink={show_id:string;period_id:string;payroll_show_id:string};
export function crmProfitReader(state:PayrollState|null,links:PayrollLink[],options:{includeChoices?:boolean}={}){
 const cache=new Map<string,ReturnType<typeof calculate>>();
 return (show:CrmShowRow,budget:Budget|null)=>{
  const estimate=budget?round(Object.values(budget).reduce((n,v)=>n+v,0)):null,base={estimatedCost:estimate,estimatedProfit:estimate!==null&&show.sale_cents!==null?round(show.sale_cents/100-estimate):null,actual:null as null|{periodId:string;start:string;end:string;closed:boolean;sale:number;musicians:number;technical:number;drivers:number;expenses:number;cost:number;profit:number;variance:number|null;commissionBase:number;periodCommission:number|null;promotional:boolean;expensesByType:Record<string,number>},issue:'',choices:[] as {periodId:string;showId:string;label:string}[]};
  if(!state)return {...base,issue:'Aún no hay una nómina vinculada.'};
  const direct=state.periods.flatMap(p=>p.shows.filter(s=>s.crmShowId===show.id).map(s=>({p,s}))),manual=links.find(l=>l.show_id===show.id);
  const matches=direct.length?direct:state.periods.flatMap(p=>p.id===manual?.period_id?p.shows.filter(s=>s.id===manual.payroll_show_id).map(s=>({p,s})):[]);
  if(options.includeChoices!==false)base.choices=state.periods.flatMap(p=>p.shows.filter(s=>(!s.crmShowId||s.crmShowId===show.id)&&!links.some(l=>l.show_id!==show.id&&l.period_id===p.id&&l.payroll_show_id===s.id)).map(s=>({periodId:p.id,showId:s.id,label:s.date+' · '+s.name+' · '+(p.status==='cerrada'?'Cerrada':'Abierta')})));
  if(matches.length!==1)return {...base,issue:matches.length?'Hay varios shows de nómina vinculados. Revisa sus vínculos antes de analizar costos.':'Vincula el show de nómina para consultar sus costos registrados.'};
  const {p,s}=matches[0];if(p.status==='cerrada'&&!p.snapshot?.camiloCommission)return {...base,issue:'Este cierre histórico no contiene el desglose de costos. Se conserva sin recalcularlo.'};
  let result=cache.get(p.id);if(!result){result=calculate(state,p);cache.set(p.id,result);}const costs=result.camiloCommission?.shows.find(c=>c.id===s.id);
  if(!costs)return {...base,issue:'No se encontró el desglose guardado del show.'};
  if(result.camiloCommission?.issues.length)return {...base,issue:result.camiloCommission.issues.join(' ')};
  const expenseTypes:Record<string,number>={};for(const e of p.showExpenses??[])if(e.showId===s.id)expenseTypes[e.category]=round((expenseTypes[e.category]??0)+e.amount);
  return {...base,actual:{periodId:p.id,start:p.start,end:p.end,closed:p.status==='cerrada',sale:costs.sale,musicians:costs.musicians,technical:costs.technical,drivers:costs.drivers,expenses:costs.expenses,cost:costs.cost,profit:round(costs.sale-costs.cost),variance:estimate===null?null:round(costs.cost-estimate),commissionBase:round(costs.sale-costs.deductible),periodCommission:result.camiloCommission?.amount??null,promotional:costs.promotional,expensesByType:expenseTypes}};
 };
}
