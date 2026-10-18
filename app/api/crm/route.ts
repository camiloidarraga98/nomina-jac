import {crmWorkspace,crmWeekly,crmContactDetail,crmDirectory,saveCrmPlan,linkCrmPayroll,saveCrmContact,addCrmContactFiles} from '@/lib/crm-workspace';
import {waitUntil} from 'cloudflare:workers';
import {prepareCrmDeletion,deleteCrmShow} from '@/lib/crm-delete';
import {createCrmShow} from '@/lib/crm-create';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {agendaDate} from '@/lib/calendar-core';
import {crmFeed,crmShowDetail,syncCrmMonth,updateCrmShow,addCrmPayment,voidCrmPayment,paymentShowID,guardActive} from '@/lib/crm-store';
import {crmGuard} from '@/lib/crm-access';
import {CrmFailure,canCrm} from '@/lib/crm-core';
import {syncCrmSheet,createCrmSheet,disconnectCrmSheets} from '@/lib/crm-sheets';
import {startCrmSheetsOauth} from '@/lib/crm-sheets-oauth';
import {boundedNoticeJSON} from '@/lib/notice-files';
import {NoticeFailure} from '@/lib/notifications-core';
import {CalendarFailure} from '@/lib/calendar';
export const dynamic='force-dynamic';
const reply=(data:unknown,status=200,cookie?:string)=>Response.json(data,{status,headers:{...payrollHeaders,...(cookie?{'Set-Cookie':cookie}:{})}});
const failure=(e:unknown)=>reply({error:e instanceof CrmFailure||e instanceof NoticeFailure||e instanceof CalendarFailure?e.message:'No pudimos completar la operación. Tus datos se conservan; intenta de nuevo.'},e instanceof CrmFailure||e instanceof NoticeFailure||e instanceof CalendarFailure?e.status:502);
export async function GET(req:Request){const u=await payrollUser();if(!u||u.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);if(!canCrm(u))return reply({error:'El CRM está disponible solo para administradores.'},403);try{const guard=crmGuard(req,u),q=new URL(req.url).searchParams,id=q.get('id')??(q.get('payment')?await paymentShowID(u,q.get('payment')!):null),data=q.get('view')==='workspace'?await crmWorkspace(u,q.get('id')??'',guard):q.get('view')==='weekly'?await crmWeekly(u,q.get('week')??undefined,guard):q.get('view')==='contacts'?{contacts:await crmDirectory()}:q.get('view')==='contact'?await crmContactDetail(u,q.get('id')??'',guard):id?await crmShowDetail(u,id):await crmFeed(u,q.get('month')??agendaDate().slice(0,7));if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);return reply(data);}catch(e){return failure(e);}}
export async function POST(req:Request){const u=await payrollUser();if(!u||u.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);if(!canCrm(u))return reply({error:'El CRM está disponible solo para administradores.'},403);if(req.headers.get('origin')!==new URL(req.url).origin)return reply({error:'Origen no autorizado.'},403);
 try{const body=await boundedNoticeJSON(req) as {action?:string;record?:unknown;month?:string;revision?:number},guard=crmGuard(req,u);
  if(body.action==='savePlan'){await saveCrmPlan(u,body.record,guard);return reply({ok:true});}
  if(body.action==='linkPayroll'){await linkCrmPayroll(u,body.record,guard);return reply({ok:true});}
  if(body.action==='saveContact')return reply(await saveCrmContact(u,body.record,guard));
  if(body.action==='addContactFiles')return reply(await addCrmContactFiles(u,body.record,guard));
  if(body.action==='prepareDeleteShow')return reply(await prepareCrmDeletion(u,body.record,guard));
  if(body.action==='deleteShow')return reply(await deleteCrmShow(u,body.record,guard));
  if(body.action==='createShow'){const result=await createCrmShow(u,body.record,guard);waitUntil(syncCrmSheet(guard).catch(()=>({synced:0})));return reply(result);}
  if(body.action==='syncCalendar')return reply(await syncCrmMonth(u,body.month??agendaDate().slice(0,7),guard));
  if(body.action==='connectSheets'){const start=await startCrmSheetsOauth(u,req.headers.get('cookie')||'');return reply({url:start.url},200,start.cookie);}
  if(body.action==='createSheet')return reply({url:await createCrmSheet(guard)});
  if(body.action==='disconnectSheets'){if(!Number.isSafeInteger(body.revision))throw new CrmFailure('Actualiza la conexión.');await disconnectCrmSheets(body.revision!,guard);return reply({ok:true});}
  if(body.action==='syncSheets')return reply(await syncCrmSheet(guard));
  if(body.action==='updateShow')await updateCrmShow(u,body.record,guard);
  else if(body.action==='addPayment')await addCrmPayment(u,body.record,guard);
  else if(body.action==='voidPayment')await voidCrmPayment(u,body.record,guard);
  else throw new CrmFailure('Operación del CRM no disponible.');
  const syncing=syncCrmSheet(guard).catch(()=>({synced:0}));waitUntil(syncing);return reply({ok:true});
 }catch(e){return failure(e);}
}
