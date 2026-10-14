import {z} from 'zod';
import {database} from '@/db/raw';
import {agendaConnection,inspectAgendaEvents,deleteAgendaEvent,CalendarFailure} from './calendar';
import {canCrm,CrmFailure,calendarShowDate,type CrmShowRow} from './crm-core';
import {guardActive} from './crm-store';
import type {CrmGuard} from './crm-access';
import type {AccessUser} from './payroll-permissions';
const selection=z.object({id:z.string().uuid(),version:z.number().int().positive()}).strict();
const deletion=z.object({id:z.string().uuid(),showId:z.string().uuid(),version:z.number().int().positive(),revision:z.number().int().nonnegative(),etag:z.string().min(1).max(1024).refine(s=>!/[\r\n]/.test(s))}).strict();
type Deletion=z.infer<typeof deletion>;
async function context(u:AccessUser,id:string,actor:CrmGuard){
 if(!canCrm(u)||!await guardActive(actor))throw new CrmFailure('Tu sesión o permiso cambió.',403);
 const show=await database().prepare('SELECT * FROM jac_crm_shows WHERE id=?').bind(id).first<CrmShowRow&{write_nonce:string}>();
 if(!show)throw new CrmFailure('Show no disponible.',404);
 const c=await agendaConnection();if(!c.connected||!c.writeAuthorized||c.selected?.id!==show.calendar_id)throw new CrmFailure('Conecta el calendario original del show con permiso de edición.',409);
 const guard={sql:actor.sql+" AND EXISTS(SELECT 1 FROM payroll_calendar WHERE id='jac' AND version=? AND calendar_id=? AND credentials<>'')",bindings:[...actor.bindings,c.revision,show.calendar_id]};
 return {show,guard,revision:c.revision};
}
export async function prepareCrmDeletion(u:AccessUser,input:unknown,actor:CrmGuard):Promise<{record:Deletion;event?:{title:string;date:string}}>{
 const p=selection.safeParse(input);if(!p.success)throw new CrmFailure('Actualiza el show antes de eliminarlo.');
 const {show,guard,revision}=await context(u,p.data.id,actor);
 if(show.source_state==='deleted')throw new CrmFailure('Este evento ya se eliminó. Actualiza el listado.',409);
 if(show.version!==p.data.version)throw new CrmFailure('El show cambió. Actualiza antes de eliminar.',409);
 if(show.source_state==='deleting'){
  const prior=await database().prepare("SELECT data FROM jac_crm_audit WHERE id=? AND show_id=? AND action='show-delete-requested'").bind(show.write_nonce,show.id).first<{data:string}>();
  if(!prior)throw new CrmFailure('No se confirmó la eliminación pendiente. Actualiza el show.',409);
  const record=deletion.parse(JSON.parse(prior.data));
  if(record.revision!==revision){
   const reset=await database().prepare(`UPDATE jac_crm_shows SET source_state='present',version=version+1,write_nonce='' WHERE id=? AND source_state='deleting' AND write_nonce=? AND ${guard.sql}`).bind(show.id,show.write_nonce,...guard.bindings).run();
   if(reset.meta.changes!==1)throw new CrmFailure('El show cambió. Actualiza antes de continuar.',409);
   return prepareCrmDeletion(u,{id:show.id,version:show.version+1},actor);
  }
  if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
  return {record};
 }
 const event=(await inspectAgendaEvents(show.calendar_id,revision,[show.event_id])).get(show.event_id);
 if(event&&!event.editable)throw new CrmFailure('Elimina este tipo de evento desde Google Calendar.',409);
 if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
 return {record:{id:crypto.randomUUID(),showId:show.id,version:show.version,revision,etag:event?.etag??'"already-removed"'} satisfies Deletion,...(event?{event:{title:event.title,date:calendarShowDate(event)}}:{})};
}
export async function deleteCrmShow(u:AccessUser,input:unknown,actor:CrmGuard){
 const parsed=deletion.safeParse(input);if(!parsed.success)throw new CrmFailure('Actualiza el show y confirma de nuevo su eliminación.');
 const p=parsed.data,{show,guard,revision}=await context(u,p.showId,actor),db=database();
 if(show.source_state==='deleted')return {ok:true};
 if(revision!==p.revision)throw new CrmFailure('El calendario cambió. Actualiza y confirma de nuevo.',409);
 const stamp=new Date().toISOString();
 if(show.source_state!=='deleting'){
  const changed=await db.batch([
   db.prepare(`UPDATE jac_crm_shows SET source_state='deleting',version=version+1,write_nonce=?,updated_at=? WHERE id=? AND version=? AND source_state NOT IN ('deleted','deleting') AND NOT EXISTS(SELECT 1 FROM jac_crm_audit WHERE id=?) AND ${guard.sql}`).bind(p.id,stamp,show.id,p.version,p.id,...guard.bindings),
   db.prepare("INSERT INTO jac_crm_audit(id,show_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)").bind(p.id,show.id,u.id,'show-delete-requested',JSON.stringify(p),stamp,show.id,p.id)
  ]);if(changed[0].meta.changes!==1)throw new CrmFailure('El show cambió. Actualiza y confirma de nuevo.',409);
 }
 const intent=await db.prepare("SELECT data FROM jac_crm_audit WHERE id=? AND show_id=? AND action='show-delete-requested'").bind(p.id,show.id).first<{data:string}>();
 if(!intent||JSON.stringify(deletion.parse(JSON.parse(intent.data)))!==JSON.stringify(p))throw new CrmFailure('Ya hay otra eliminación pendiente. Actualiza el show.',409);
 const pending={sql:guard.sql+" AND EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND source_state='deleting' AND write_nonce=?)",bindings:[...guard.bindings,show.id,p.id]};
 try{await deleteAgendaEvent(show.calendar_id,p.revision,show.event_id,p.etag,()=>guardActive(pending));}
 catch(e){
  // Definite rejection has not deleted Google data. Release the claim so a
  // fresh confirmation can use the changed event. Network failures keep the
  // durable intent: retrying it cannot delete a newer ETag or recreate a show.
  if(e instanceof CalendarFailure&&[400,403,409].includes(e.status))await db.prepare(`UPDATE jac_crm_shows SET source_state='present',version=version+1,write_nonce='',updated_at=? WHERE id=? AND source_state='deleting' AND write_nonce=? AND ${guard.sql}`).bind(new Date().toISOString(),show.id,p.id,...guard.bindings).run();
  throw e;
 }
 const done=await db.batch([
  db.prepare(`UPDATE jac_crm_shows SET source_state='deleted',version=version+1,updated_at=? WHERE id=? AND source_state='deleting' AND write_nonce=? AND ${guard.sql}`).bind(new Date().toISOString(),show.id,p.id,...guard.bindings),
  db.prepare(`INSERT INTO jac_crm_audit(id,show_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND source_state='deleted' AND write_nonce=?) AND ${guard.sql}`).bind(crypto.randomUUID(),show.id,u.id,'show-deleted',JSON.stringify({request:p.id}),new Date().toISOString(),show.id,p.id,...guard.bindings)
 ]);
 if(done[0].meta.changes!==1)throw new CrmFailure('Calendar ya recibió la eliminación. Inicia sesión y reintenta para confirmar el resultado en CRM.',409);
 return {ok:true};
}
