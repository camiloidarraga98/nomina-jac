import {database} from '@/db/raw';
import {env} from 'cloudflare:workers';
import {z} from 'zod';
import {readAgenda,agendaConnection,CalendarFailure} from './calendar';
import {agendaMonth,agendaDate} from './calendar-core';
import {decodeNoticeFiles} from './notice-files';
import {contentHash,stageTravelFiles,discardTravelFiles,uploadedGate,uploadedBindings} from './travel-files';
import {purgeNoticeAttachments} from './notifications';
import {CrmFailure,canCrm,cents,MAX_CENTS,showMunicipalities,calendarShowDate,publicCrmShow,crmShowInput,crmPaymentInput,crmVoidInput,type CrmShowRow,type CrmPaymentRow} from './crm-core';
import type {AccessUser} from './payroll-permissions';
import type {CrmGuard} from './crm-access';
const uuid=z.string().uuid();
const requireCrm=(u:AccessUser)=>{if(!canCrm(u))throw new CrmFailure('El CRM está disponible solo para administradores.',403);};
export async function guardActive(guard:CrmGuard){return !!await database().prepare('SELECT 1 WHERE '+guard.sql).bind(...guard.bindings).first();}
async function showRow(u:AccessUser,id:string){requireCrm(u);if(!uuid.safeParse(id).success)throw new CrmFailure('Show no disponible.',404);const r=await database().prepare('SELECT * FROM jac_crm_shows WHERE id=?').bind(id).first<CrmShowRow>();if(!r)throw new CrmFailure('Show no disponible.',404);return r;}
export async function crmFeed(u:AccessUser,month:string){requireCrm(u);agendaMonth(month);const start=month+'-01',d=new Date(start+'T12:00:00Z');d.setUTCMonth(d.getUTCMonth()+6);const end=d.toISOString().slice(0,10),today=agendaDate(),visibleStart=start>today?start:today,db=database();
 const result=await db.prepare('SELECT * FROM jac_crm_shows WHERE show_date>=? AND show_date<? ORDER BY show_date,title,id LIMIT 1001').bind(visibleStart,end).all<CrmShowRow>();if(result.results.length>1000)throw new CrmFailure('Selecciona un rango con menos shows.',413);
 const connection=await db.prepare('SELECT spreadsheet_url,spreadsheet_id,credentials,version,creation_state,error FROM jac_crm_sheets WHERE id=?').bind('jac').first<{spreadsheet_url:string;spreadsheet_id:string;credentials:string;version:number;creation_state:string;error:string}>();
 const calendar=await agendaConnection();
 const pending=await db.prepare('SELECT count(*) AS n FROM jac_crm_exports WHERE synced_version<version OR connection_version<>?').bind(connection?.version??0).first<{n:number}>();
 return {shows:result.results.map(publicCrmShow),month,today,until:end,calendar:{revision:calendar.revision,ready:calendar.connected&&calendar.writeAuthorized&&!!calendar.selected,name:calendar.selected?.name??''},sheets:{connected:!!connection?.credentials,url:connection?.spreadsheet_url||'',ready:!!connection?.spreadsheet_id,version:connection?.version??0,creationState:connection?.creation_state||'idle',error:connection?.error||'',pending:pending?.n??0}};
}
export async function crmShowDetail(u:AccessUser,id:string){const show=await showRow(u,id),db=database();const rows=(await db.prepare('SELECT p.*,u.name AS actor_name FROM jac_crm_payments p LEFT JOIN payroll_users u ON u.id=p.actor_id WHERE show_id=? ORDER BY payment_date DESC,created_at DESC LIMIT 1001').bind(id).all<CrmPaymentRow&{actor_name:string}>()).results;if(rows.length>1000)throw new CrmFailure('Este show excede el límite de abonos visibles.',413);
 const files=(await db.prepare("SELECT id,notice_id,filename,mime_type,size FROM jac_notice_attachments WHERE state='ready' AND notice_id IN (SELECT 'crm-payment:'||id FROM jac_crm_payments WHERE show_id=?)").bind(id).all<{id:string;notice_id:string;filename:string;mime_type:string;size:number}>()).results;
 return {show:publicCrmShow(show),payments:rows.map(p=>({id:p.id,amount:p.amount_cents/100,paymentDate:p.payment_date,note:p.note,status:p.status,version:p.version,createdAt:p.created_at,actor:p.actor_name||'Administrador',voidReason:p.void_reason,voidedAt:p.voided_at,files:files.filter(f=>f.notice_id==='crm-payment:'+p.id).map(f=>({id:f.id,filename:f.filename,mimeType:f.mime_type,size:f.size}))}))};
}
export async function crmSourceID(calendar:string,event:string){const h=await contentHash([calendar,event]);return h.slice(0,8)+'-'+h.slice(8,12)+'-4'+h.slice(13,16)+'-a'+h.slice(17,20)+'-'+h.slice(20,32);}
export async function syncCrmMonth(u:AccessUser,month:string,guard:CrmGuard){requireCrm(u);const grid=agendaMonth(month),agenda=await readAgenda(month),selected=agenda.connection.selected;if(!agenda.connection.connected||!selected)throw new CrmFailure('Conecta y selecciona Agenda antes de detectar shows.',409);
 guard={sql:guard.sql+" AND EXISTS(SELECT 1 FROM payroll_calendar WHERE id='jac' AND version=? AND calendar_id=? AND credentials<>'')",bindings:[...guard.bindings,agenda.connection.revision,selected.id]};
 const db=database(),existing=(await db.prepare('SELECT * FROM jac_crm_shows WHERE calendar_id=?').bind(selected.id).all<CrmShowRow>()).results,byEvent=new Map(existing.map(s=>[s.event_id,s])),stamp=new Date().toISOString(),writes:D1PreparedStatement[]=[];let detected=0;
 for(const event of agenda.events){const towns=showMunicipalities(event.title),old=byEvent.get(event.id);if(!towns.length&&!old)continue;const id=old?.id??await crmSourceID(selected.id,event.id),municipality=towns.join(' / ')||old!.municipality;detected++;
 writes.push(db.prepare(`INSERT INTO jac_crm_shows(id,calendar_id,event_id,title,municipality,show_date,created_at,updated_at) SELECT ?,?,?,?,?,?,?,? WHERE ${guard.sql} ON CONFLICT(id) DO UPDATE SET title=excluded.title,municipality=excluded.municipality,show_date=excluded.show_date,source_state='present',version=jac_crm_shows.version+1,updated_at=excluded.updated_at WHERE jac_crm_shows.title<>excluded.title OR jac_crm_shows.municipality<>excluded.municipality OR jac_crm_shows.show_date<>excluded.show_date OR jac_crm_shows.source_state<>'present'`).bind(id,selected.id,event.id,event.title,municipality,calendarShowDate(event),stamp,stamp,...guard.bindings));
 }
 const seen=new Set(agenda.events.map(e=>e.id));for(const old of existing)if(old.source_state==='present'&&old.show_date>=grid.days[0]&&old.show_date<=grid.days.at(-1)!&&!seen.has(old.event_id))writes.push(db.prepare(`UPDATE jac_crm_shows SET source_state='missing',version=version+1,updated_at=? WHERE id=? AND ${guard.sql}`).bind(stamp,old.id,...guard.bindings));
 const current=await agendaConnection();if(current.revision!==agenda.connection.revision||current.selected?.id!==selected.id)throw new CrmFailure('El calendario cambió. Vuelve a detectar shows.',409);if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
 writes.push(db.prepare(`UPDATE jac_crm_exports SET version=version+1,error='' WHERE payment_id IN (SELECT cp.id FROM jac_crm_payments cp JOIN jac_crm_shows s ON s.id=cp.show_id WHERE s.updated_at=?) AND ${guard.sql}`).bind(stamp,...guard.bindings));
 for(let i=0;i<writes.length;i+=80)await db.batch(writes.slice(i,i+80));return {detected};
}
export async function updateCrmShow(u:AccessUser,input:unknown,guard:CrmGuard){requireCrm(u);const parsed=crmShowInput.safeParse(input);if(!parsed.success)throw new CrmFailure('Revisa el precio y los datos del show.');const p=parsed.data,old=await showRow(u,p.id),db=database(),nonce=crypto.randomUUID(),sale=cents(p.sale),stamp=new Date().toISOString();
 const result=await db.batch([
  db.prepare(`UPDATE jac_crm_shows SET sale_cents=?,entrepreneur=?,note=?,status=?,promotional=?,version=version+1,write_nonce=?,updated_at=? WHERE id=? AND version=? AND ${guard.sql}`).bind(sale,p.entrepreneur,p.note,p.status,Number(p.promotional),nonce,stamp,p.id,p.version,...guard.bindings),
  db.prepare("INSERT INTO jac_crm_audit(id,show_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)").bind(crypto.randomUUID(),p.id,u.id,'show-updated',JSON.stringify({previousSale:old.sale_cents,newSale:sale,status:p.status,promotional:p.promotional}),stamp,p.id,nonce),
  db.prepare("UPDATE jac_crm_exports SET version=version+1,error='' WHERE payment_id IN (SELECT id FROM jac_crm_payments WHERE show_id=?) AND EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)").bind(p.id,p.id,nonce)
 ]);if(result[0].meta.changes!==1)throw new CrmFailure('El show o tu sesión cambió. Actualiza antes de guardar.',409);
}
export async function addCrmPayment(u:AccessUser,input:unknown,guard:CrmGuard){requireCrm(u);const parsed=crmPaymentInput.safeParse(input);if(!parsed.success)throw new CrmFailure('Revisa valor, fecha y comprobantes del abono.');const p=parsed.data,files=decodeNoticeFiles(p.files),hash=await contentHash({showId:p.showId,amount:cents(p.amount),date:p.paymentDate,proof:p.files.map(f=>f.data).sort()}),db=database(),prior=await db.prepare('SELECT hash,actor_id,note FROM jac_crm_payments WHERE id=?').bind(p.id).first<{hash:string;actor_id:string;note:string}>();
 if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);if(prior){if(prior.hash!==hash||prior.actor_id!==u.id||prior.note!==p.note)throw new CrmFailure('Ese intento ya guardó otro abono. Abre un formulario nuevo.',409);return {id:p.id};}
 const duplicate=await db.prepare("SELECT id FROM jac_crm_payments WHERE show_id=? AND hash=? AND status='recorded' LIMIT 1").bind(p.showId,hash).first();if(duplicate)throw new CrmFailure('Ya existe un abono con ese valor, fecha y comprobante. Revisa el historial antes de registrarlo otra vez.',409);
 const show=await showRow(u,p.showId);if(show.sale_cents===null||show.status!=='active')throw new CrmFailure('Guarda el precio de un show activo antes de registrar abonos.');
 const uploads=await stageTravelFiles(files),token=crypto.randomUUID(),amount=cents(p.amount),stamp=new Date().toISOString();let committed=false;
 try{if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
 const savedGate='EXISTS(SELECT 1 FROM jac_crm_payments WHERE id=? AND upload_token=?)';
 const result=await db.batch([
  db.prepare(`UPDATE jac_crm_shows SET paid_cents=paid_cents+?,version=version+1,write_nonce=?,updated_at=? WHERE id=? AND sale_cents IS NOT NULL AND status='active' AND paid_cents+?<=? AND NOT EXISTS(SELECT 1 FROM jac_crm_payments WHERE id=? OR (show_id=? AND hash=? AND status='recorded')) AND ${guard.sql}${uploadedGate(uploads)}`).bind(amount,token,stamp,p.showId,amount,MAX_CENTS,p.id,p.showId,hash,...guard.bindings,...uploadedBindings(uploads)),
  db.prepare("INSERT INTO jac_crm_payments(id,show_id,amount_cents,payment_date,note,hash,actor_id,upload_token,created_at) SELECT ?,?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)").bind(p.id,p.showId,amount,p.paymentDate,p.note,hash,u.id,token,stamp,p.showId,token),
  ...uploads.map(f=>db.prepare(`UPDATE jac_notice_attachments SET state='ready',notice_id=? WHERE id=? AND state='staged' AND ${savedGate}`).bind('crm-payment:'+p.id,f.id,p.id,token)),
  db.prepare(`INSERT INTO jac_crm_exports(payment_id) SELECT ? WHERE ${savedGate}`).bind(p.id,p.id,token),
  db.prepare(`INSERT INTO jac_crm_audit(id,show_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE ${savedGate}`).bind(crypto.randomUUID(),p.showId,u.id,'payment-added',JSON.stringify({id:p.id,amountCents:amount}),stamp,p.id,token)
 ]);committed=result[0].meta.changes===1;const row=await db.prepare('SELECT hash,actor_id,note FROM jac_crm_payments WHERE id=?').bind(p.id).first<{hash:string;actor_id:string;note:string}>();if(!row||row.hash!==hash||row.actor_id!==u.id||row.note!==p.note)throw new CrmFailure('No se confirmó el abono. Conserva el formulario y reintenta el mismo registro.',409);return {id:p.id};
 }finally{if(!committed){await discardTravelFiles(uploads);await purgeNoticeAttachments();}}
}
export async function voidCrmPayment(u:AccessUser,input:unknown,guard:CrmGuard){requireCrm(u);const parsed=crmVoidInput.safeParse(input);if(!parsed.success)throw new CrmFailure('Indica el motivo de la anulación.');const p=parsed.data,db=database(),row=await db.prepare('SELECT * FROM jac_crm_payments WHERE id=?').bind(p.id).first<CrmPaymentRow>();if(!row)throw new CrmFailure('Abono no disponible.',404);if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
 if(row.status==='voided'){if(row.void_reason===p.reason)return;throw new CrmFailure('El abono ya está anulado.',409);}const stamp=new Date().toISOString(),token=crypto.randomUUID();
 const result=await db.batch([
  db.prepare(`UPDATE jac_crm_shows SET paid_cents=paid_cents-?,version=version+1,write_nonce=?,updated_at=? WHERE id=? AND paid_cents>=? AND EXISTS(SELECT 1 FROM jac_crm_payments WHERE id=? AND version=? AND status='recorded') AND ${guard.sql}`).bind(row.amount_cents,token,stamp,row.show_id,row.amount_cents,p.id,p.version,...guard.bindings),
  db.prepare("UPDATE jac_crm_payments SET status='voided',version=version+1,voided_at=?,voided_by=?,void_reason=? WHERE id=? AND version=? AND status='recorded' AND EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)").bind(stamp,u.id,p.reason,p.id,p.version,row.show_id,token),
  db.prepare("UPDATE jac_crm_exports SET version=version+1,error='' WHERE payment_id=? AND EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)").bind(p.id,row.show_id,token),
  db.prepare("INSERT INTO jac_crm_audit(id,show_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)").bind(crypto.randomUUID(),row.show_id,u.id,'payment-voided',JSON.stringify({id:p.id,reason:p.reason}),stamp,row.show_id,token)
 ]);if(result[0].meta.changes!==1)throw new CrmFailure('El abono o tu sesión cambió. Actualiza el show.',409);
}
export async function crmReceipt(u:AccessUser,payment:string,file:string,guard:CrmGuard){requireCrm(u);if(!uuid.safeParse(payment).success||!uuid.safeParse(file).success)throw new CrmFailure('Comprobante no disponible.',404);
 const get=()=>database().prepare(`SELECT a.file_key,a.filename,a.mime_type FROM jac_notice_attachments a JOIN jac_crm_payments p ON a.notice_id='crm-payment:'||p.id WHERE p.id=? AND a.id=? AND a.state='ready' AND ${guard.sql}`).bind(payment,file,...guard.bindings).first<{file_key:string;filename:string;mime_type:string}>();
 const r=await get();if(!r)throw new CrmFailure('Comprobante no disponible.',404);const object=await env.BUCKET.get(r.file_key);if(!object||!await get())throw new CrmFailure('Comprobante no disponible.',404);return {object,filename:r.filename,mimeType:r.mime_type};
}
export async function paymentShowID(u:AccessUser,id:string){requireCrm(u);if(!uuid.safeParse(id).success)throw new CrmFailure('Abono no disponible.',404);const p=await database().prepare('SELECT show_id FROM jac_crm_payments WHERE id=?').bind(id).first<{show_id:string}>();if(!p)throw new CrmFailure('Abono no disponible.',404);return p.show_id;}
