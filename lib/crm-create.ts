import {z} from 'zod';
import {database} from '@/db/raw';
import {calendarConfig,agendaConnection,validateAgendaDraft,saveAgendaEvent,CalendarFailure} from './calendar';
import {canEditAgenda} from './calendar-permissions';
import {agendaDate,addAgendaDays,type AgendaEvent} from './calendar-core';
import {canCrm,CrmFailure,crmShowInput,crmPaymentInput,cents,calendarShowDate,showMunicipalities} from './crm-core';
import {guardActive,crmSourceID,crmShowDetail,addCrmPayment} from './crm-store';
import {decodeNoticeFiles} from './notice-files';
import {NoticeFailure} from './notifications-core';
import {contentHash} from './travel-files';
import type {AccessUser} from './payroll-permissions';
import type {CrmGuard} from './crm-access';
const inputSchema=crmShowInput.omit({id:true,version:true,status:true}).extend({id:z.string().uuid().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/),revision:z.number().int().nonnegative(),event:z.unknown(),firstPayment:crmPaymentInput.omit({id:true,showId:true}).optional()}).strict();
type Creation={id:string;actor_id:string;calendar_id:string;event_hash:string;payload_hash:string;show_id:string;status:string};
export async function createCrmShow(user:AccessUser,input:unknown,actor:CrmGuard){
 if(!canCrm(user)||!canEditAgenda(user))throw new CrmFailure('Solo administradores pueden crear shows desde el CRM.',403);
 const parsed=inputSchema.safeParse(input);if(!parsed.success)throw new CrmFailure('Revisa los datos del evento, la venta y el primer abono.');
 const p=parsed.data,draft=validateAgendaDraft(p.event);if(draft.allDay?draft.end!==addAgendaDays(draft.start,1):agendaDate(new Date(draft.start))!==agendaDate(new Date(draft.end)))throw new CrmFailure('El show debe realizarse en un único día. Revisa la fecha y las horas.');if(p.firstPayment)decodeNoticeFiles(p.firstPayment.files);
 const eventHash=await contentHash(draft),payloadHash=await contentHash({event:draft,sale:p.sale,entrepreneur:p.entrepreneur,note:p.note,promotional:p.promotional,firstPayment:p.firstPayment??null}),db=database();
 if(!await guardActive(actor))throw new CrmFailure('Tu sesión cambió.',403);
 let creation=await db.prepare('SELECT * FROM jac_crm_creations WHERE id=?').bind(p.id).first<Creation>();
 const c=await calendarConfig();
 if(!creation&&c?.calendar_id)creation=await db.prepare('SELECT * FROM jac_crm_creations WHERE calendar_id=? AND event_hash=?').bind(c.calendar_id,eventHash).first<Creation>();
 const check=()=>{if(creation&&(creation.actor_id!==user.id||creation.payload_hash!==payloadHash))throw new CrmFailure('Este evento ya tiene una solicitud con otros datos. Revisa su cuenta en CRM antes de crear otro.',409);};check();
 if(creation){const current=await db.prepare('SELECT source_state FROM jac_crm_shows WHERE id=?').bind(creation.show_id).first<{source_state:string}>();if(current&&['deleted','deleting'].includes(current.source_state))throw new CrmFailure('Este evento fue eliminado o tiene una eliminación pendiente. No se puede recrear con el mismo intento.',409);}
 if(creation?.status==='completed')return creationResult(user,creation,actor);
 const connection=await agendaConnection();if(!c||!connection.connected||!connection.writeAuthorized||!c.calendar_id)throw new CrmFailure('Conecta Agenda con permiso para crear eventos antes de guardar.',409);
 if(creation?creation.calendar_id!==c.calendar_id:p.revision!==c.version)throw new CrmFailure('El calendario cambió. Actualiza el formulario antes de guardar.',409);
 const guard={sql:actor.sql+" AND EXISTS(SELECT 1 FROM payroll_calendar WHERE id='jac' AND version=? AND calendar_id=? AND credentials<>'')",bindings:[...actor.bindings,c.version,c.calendar_id]};
 if(!creation){
  const day=draft.allDay?draft.start:agendaDate(new Date(draft.start));if(day<agendaDate())throw new CrmFailure('Elige una fecha de hoy en adelante para el nuevo show.');
  const stamp=new Date().toISOString(),showId=await crmSourceID(c.calendar_id,'jac'+p.id.replaceAll('-',''));
  await db.prepare(`INSERT OR IGNORE INTO jac_crm_creations(id,actor_id,calendar_id,event_hash,payload_hash,show_id,created_at,updated_at) SELECT ?,?,?,?,?,?,?,? WHERE ${guard.sql}`).bind(p.id,user.id,c.calendar_id,eventHash,payloadHash,showId,stamp,stamp,...guard.bindings).run();
  creation=await db.prepare('SELECT * FROM jac_crm_creations WHERE calendar_id=? AND event_hash=?').bind(c.calendar_id,eventHash).first<Creation>();
  if(!creation)throw new CrmFailure('Tu sesión o el calendario cambió. Actualiza antes de guardar.',409);check();
 }
 try{
  if(creation.status==='pending'){
   // Only the public event draft reaches Google. Sale/receipts never enter the
   // Calendar payload, including its private extended properties.
   const result=await saveAgendaEvent('createEvent',{requestId:creation.id,revision:c.version,event:draft},()=>guardActive(guard));
   if(result.event.id!=='jac'+creation.id.replaceAll('-',''))throw new CrmFailure('Google no confirmó el identificador esperado.',502);
   await initializeAccount(creation,result.event,p,user,guard);
  }
  if(p.firstPayment)await addCrmPayment(user,{...p.firstPayment,id:await crmSourceID('crm-first-payment',creation.id),showId:creation.show_id},guard);
  const completed=await db.prepare(`UPDATE jac_crm_creations SET status='completed',updated_at=? WHERE id=? AND status IN ('account_ready','completed') AND ${guard.sql}`).bind(new Date().toISOString(),creation.id,...guard.bindings).run();
  if(completed.meta.changes!==1)throw new CrmFailure('Tu sesión o el calendario cambió.',409);
  if(!await guardActive(actor))throw new CrmFailure('Tu sesión cambió.',403);
  return creationResult(user,creation,actor);
 }catch(e){
  if(!await guardActive(actor))throw new CrmFailure('Tu sesión cambió. Inicia sesión para revisar el resultado.',403);
  const row=await db.prepare('SELECT status FROM jac_crm_creations WHERE id=?').bind(creation.id).first<{status:string}>();
  throw new CrmFailure((row?.status==='account_ready'?'El show ya está creado en Calendar y CRM; el primer abono todavía no se confirmó. ':'No se confirmó la creación completa. ')+(e instanceof CrmFailure||e instanceof CalendarFailure||e instanceof NoticeFailure?e.message+' ':'No pudimos completar el guardado. ')+'Reintenta este mismo formulario; conservamos el identificador del evento y del abono.',502);
 }
}
async function initializeAccount(creation:Creation,event:AgendaEvent,p:z.infer<typeof inputSchema>,user:AccessUser,guard:CrmGuard){
 const db=database(),stamp=new Date().toISOString(),nonce=crypto.randomUUID(),pending="EXISTS(SELECT 1 FROM jac_crm_creations WHERE id=? AND status='pending')",saved="EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)";
 await db.batch([
  db.prepare(`INSERT OR IGNORE INTO jac_crm_shows(id,calendar_id,event_id,title,municipality,show_date,created_at,updated_at) SELECT ?,?,?,?,?,?,?,? WHERE ${pending} AND ${guard.sql}`).bind(creation.show_id,creation.calendar_id,event.id,event.title,showMunicipalities(event.title).join(' / ')||event.title,calendarShowDate(event),stamp,stamp,creation.id,...guard.bindings),
  db.prepare(`UPDATE jac_crm_shows SET sale_cents=?,entrepreneur=?,note=?,promotional=?,status='active',source_state='present',version=version+1,write_nonce=?,updated_at=? WHERE id=? AND sale_cents IS NULL AND source_state NOT IN ('deleted','deleting') AND ${pending} AND ${guard.sql}`).bind(cents(p.sale),p.entrepreneur,p.note,Number(p.promotional),nonce,stamp,creation.show_id,creation.id,...guard.bindings),
  db.prepare(`INSERT INTO jac_crm_audit(id,show_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE ${saved}`).bind(crypto.randomUUID(),creation.show_id,user.id,'show-created',JSON.stringify({saleCents:cents(p.sale),promotional:p.promotional,creationId:creation.id}),stamp,creation.show_id,nonce),
  db.prepare(`UPDATE jac_crm_creations SET status='account_ready',updated_at=? WHERE id=? AND status='pending' AND ${saved}`).bind(stamp,creation.id,creation.show_id,nonce)
 ]);
 const row=await db.prepare('SELECT status FROM jac_crm_creations WHERE id=?').bind(creation.id).first<{status:string}>();
 if(!row||!['account_ready','completed'].includes(row.status))throw new CrmFailure('El show o la sesión cambió antes de guardar su cuenta. Revisa CRM.',409);
}

async function creationResult(user:AccessUser,creation:Creation,guard:CrmGuard){const detail=await crmShowDetail(user,creation.show_id);if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);if(['deleted','deleting'].includes(detail.show.sourceState))throw new CrmFailure('Este evento fue eliminado o tiene una eliminación pendiente. No se puede recrear con el mismo intento.',409);return {show:detail.show};}
