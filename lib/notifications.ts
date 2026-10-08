import {contentHash,stageTravelFiles,discardTravelFiles,uploadedGate,uploadedBindings} from './travel-files';
import {env} from 'cloudflare:workers';
import {boardingToday,boardingFilenameDate,boardingFilenameDetails,boardingPassengerKey,validBoardingDate,BOARDING_CHANNELS} from './boarding-passes';
import {manualNoticeSchema,decodeNoticeFiles,fileMime} from './notice-files';
import {z} from 'zod';
import {database} from '@/db/raw';
import {decryptMail,encryptMail} from './payroll-mail-core';
import {mailKey} from './payroll-mail';
import {tokenHash} from './payroll-auth-crypto';
import type {AccessUser} from './payroll-permissions';
import {NoticeFailure,ITINERARY_CHANNEL,ITINERARY_TEAM,MAX_PDF_BYTES,createWebKeys,appleKey,applePushRequest,webPushRequest,noticePushContent,validateSubscription,type PushCredentials,type WebSubscription,type Notice} from './notifications-core';

const uuid=z.string().uuid();
const now=()=>new Date().toISOString();
type Config={credentials:string;version:number};
type Row={revision:number;updated_at:string;change_summary:string;sort_at:string;confirmed_revision:number;confirmed_at:string;id:string;kind:Notice['kind'];travel_date:string;title:string;body:string;filename:string;size:number;created_at:string;file_key:string;read_at:string};
export const noticeOwner=(u:AccessUser)=>!u.legacy&&!u.itinerariesOnly&&u.isOwner;
export async function noticeConfig(){return await database().prepare('SELECT credentials,version FROM jac_notice_settings WHERE id=?').bind('jac').first<Config>()??{credentials:'',version:0};}
export async function pushCredentials(c?:Config):Promise<PushCredentials>{const config=c??await noticeConfig();return config.credentials?decryptMail(config.credentials,mailKey()):{};}
async function settings(){const c=await noticeConfig(),keys=await pushCredentials(c);return {version:c.version,slackConnected:!!keys.slack,appleConfigured:!!keys.apns,webPublicKey:keys.web?.publicKey??'',channel:'#itinerarios-finales',webhook:'https://jhonalexcastano.com/api/notices/slack'};}
function view(row:Row):Notice{return {revision:row.revision,updatedAt:row.updated_at,changeSummary:row.change_summary,confirmed:row.confirmed_revision===row.revision,id:row.id,kind:row.kind,title:row.title,body:row.body,filename:row.filename,size:row.size,createdAt:row.created_at,read:!!row.read_at,...(row.kind==='boarding_pass'?{travelDate:row.travel_date}:{})};}
const accessSql="(n.kind='itinerary' OR EXISTS(SELECT 1 FROM jac_notice_recipients a WHERE a.notice_id=n.id AND a.user_id=?) OR (n.kind<>'boarding_pass' AND ?=1))";
async function noticeViews(rows:Row[]){
 if(!rows.length)return [];const attachments=(await database().prepare(`SELECT id,notice_id,filename,mime_type,size FROM jac_notice_attachments WHERE state='ready' AND notice_id IN (${rows.map(()=>'?').join(',')}) ORDER BY id`).bind(...rows.map(r=>r.id)).all<{id:string;notice_id:string;filename:string;mime_type:string;size:number}>()).results;
 return rows.map(row=>({...view(row),attachments:[...(row.file_key?[{id:row.id,filename:row.filename,mimeType:'application/pdf',size:row.size}]:[]),...attachments.filter(a=>a.notice_id===row.id).map(a=>({id:a.id,filename:a.filename,mimeType:a.mime_type,size:a.size}))]}));
}
export async function noticeFeed(u:AccessUser,cursor=''){
 if(cursor&&!/^\d{4}-\d{2}-\d{2}T[\d:.]+Z\|[a-f0-9-]{36}$/.test(cursor))throw new NoticeFailure('Actualiza el listado.');
 const [time,id]=cursor.split('|');
 const rows=await database().prepare(`SELECT n.*,CASE WHEN n.updated_at='' THEN n.created_at ELSE n.updated_at END AS sort_at,r.read_at,r.confirmed_revision,r.confirmed_at FROM jac_notices n LEFT JOIN jac_notice_recipients r ON r.notice_id=n.id AND r.user_id=? WHERE n.kind<>'boarding_pass' AND ${accessSql} ${cursor?"AND ((CASE WHEN n.updated_at='' THEN n.created_at ELSE n.updated_at END)<? OR ((CASE WHEN n.updated_at='' THEN n.created_at ELSE n.updated_at END)=? AND n.id<?))":''} ORDER BY sort_at DESC,n.id DESC LIMIT 41`).bind(u.id,u.id,noticeOwner(u)?1:0,...(cursor?[time,time,id]:[])).all<Row>();
 const all=rows.results,list=all.slice(0,40),last=list.at(-1);
 const users=noticeOwner(u)?(await database().prepare("SELECT id,name,(password_hash<>'') AS ready FROM payroll_users WHERE active=1 ORDER BY name").all<{id:string;name:string;ready:number}>()).results.map(person=>({...person,ready:person.ready===1})):[];
 const failures=noticeOwner(u)?(await database().prepare("SELECT id,error FROM jac_slack_files WHERE status='failed' ORDER BY created_at DESC LIMIT 20").all<{id:string;error:string}>()).results:[];
 const boardingUsers=noticeOwner(u)?(await database().prepare('SELECT id,name FROM payroll_users WHERE active=1 ORDER BY name').all<{id:string;name:string}>()).results:[];
 const boardingChannels=noticeOwner(u)?(await database().prepare('SELECT id,user_id AS userId,version,enabled FROM jac_boarding_channels').all()).results:[];
 return {boardingUsers,boardingChannels,notices:await noticeViews(list),nextCursor:all.length>40&&last?last.sort_at+'|'+last.id:'',settings:await settings(),users,failures};
}
export async function allowedNotice(u:AccessUser,id:string){if(!uuid.safeParse(id).success)throw new NoticeFailure('El aviso no existe.',404);const row=await database().prepare(`SELECT n.*,r.read_at,r.confirmed_revision,r.confirmed_at FROM jac_notices n LEFT JOIN jac_notice_recipients r ON r.notice_id=n.id AND r.user_id=? WHERE n.id=? AND ${accessSql}`).bind(u.id,id,u.id,noticeOwner(u)?1:0).first<Row>();if(!row)throw new NoticeFailure('El aviso no está disponible para esta cuenta.',404);return row;}
export async function noticeItem(u:AccessUser,id:string){
 const row=await allowedNotice(u,id),item=(await noticeViews([row]))[0];
 if(noticeOwner(u)&&row.kind!=='boarding_pass')item.receipts=(await database().prepare('SELECT u.id AS userId,u.name,r.confirmed_at AS confirmedAt,(r.confirmed_revision=?) AS confirmed FROM jac_notice_recipients r JOIN payroll_users u ON u.id=r.user_id WHERE r.notice_id=? AND u.active=1 ORDER BY u.name').bind(row.revision,id).all<{userId:string;name:string;confirmedAt:string;confirmed:number}>()).results.map(r=>({...r,confirmed:r.confirmed===1}));
 return item;
}
export async function markNoticeRead(u:AccessUser,id:string){await allowedNotice(u,id);await database().prepare('INSERT INTO jac_notice_recipients (id,notice_id,user_id,read_at,push_target) SELECT ?,?,?,?,0 WHERE EXISTS(SELECT 1 FROM jac_notices WHERE id=?) ON CONFLICT(id) DO UPDATE SET read_at=excluded.read_at').bind(id+'|'+u.id,id,u.id,now(),id).run();}
export async function saveManualNotice(u:AccessUser,body:unknown,authorize:()=>Promise<boolean>){
 const parsed=z.object({id:uuid,title:z.string().trim().min(1).max(120),body:z.string().trim().min(1).max(2000),recipients:z.array(uuid).min(1).max(100)}).strict().safeParse(body);
 if(!parsed.success)throw new NoticeFailure('Ingresa título, mensaje y al menos un destinatario.');const p=parsed.data,ids=[...new Set(p.recipients)].sort();
 const recipients=(await database().prepare(`SELECT id FROM payroll_users WHERE active=1 AND id IN (${ids.map(()=>'?').join(',')})`).bind(...ids).all<{id:string}>()).results;
 if(recipients.length!==ids.length)throw new NoticeFailure('Algún destinatario ya no está activo. Actualiza el listado.',409);
 if(await database().prepare('SELECT id FROM jac_deleted_alerts WHERE id=?').bind(p.id).first())throw new NoticeFailure('Esta alerta fue eliminada. Abre un formulario nuevo.',410);
 const existing=await database().prepare('SELECT kind,title,body,manual_hash FROM jac_notices WHERE id=?').bind(p.id).first<{kind:string;title:string;body:string;manual_hash:string}>();
 if(existing){if(!noticeOwner(u)||!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);const previous=(await database().prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=? AND push_target=1 ORDER BY user_id').bind(p.id).all<{user_id:string}>()).results.map(x=>x.user_id);if(existing.kind!=='alert'||existing.manual_hash||existing.title!==p.title||existing.body!==p.body||JSON.stringify(previous)!==JSON.stringify(ids))throw new NoticeFailure('Esta solicitud ya guardó otra alerta. Abre un formulario nuevo.',409);await queuePush(p.id);return p.id;}
 if(!noticeOwner(u)||!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);
 const stamp=now();const saved=await database().batch([database().prepare("INSERT INTO jac_notices (id,kind,title,body,created_at) SELECT ?,'alert',?,?,? WHERE NOT EXISTS(SELECT 1 FROM jac_deleted_alerts WHERE id=?)").bind(p.id,p.title,p.body,stamp,p.id),...ids.map(id=>database().prepare("INSERT INTO jac_notice_recipients (id,notice_id,user_id) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM jac_notices WHERE id=? AND kind='alert')").bind(p.id+'|'+id,p.id,id,p.id))]);if(saved[0].meta.changes!==1)throw new NoticeFailure('Esta alerta fue eliminada. Abre un formulario nuevo.',410);
 await queuePush(p.id);return p.id;
}
// Keep only the deleted UUID so delayed creation retries cannot restore content or pushes.
export async function deleteManualNotice(u:AccessUser,id:unknown,confirmation:unknown,authorize:()=>Promise<boolean>){
 if(!noticeOwner(u))throw new NoticeFailure('Solo un administrador puede eliminar alertas.',403);
 if(!uuid.safeParse(id).success||confirmation!==id)throw new NoticeFailure('Confirma la alerta que deseas eliminar.');
 const target=id as string,db=database();
 const item=await db.prepare('SELECT kind FROM jac_notices WHERE id=?').bind(target).first<{kind:string}>();
 if(item&&item.kind!=='alert')throw new NoticeFailure('Selecciona una alerta para eliminar.');
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);
 await db.batch([
  db.prepare("INSERT OR IGNORE INTO jac_deleted_alerts (id,deleted_at) SELECT id,? FROM jac_notices WHERE id=? AND kind='alert'").bind(now(),target),
  db.prepare("UPDATE jac_notice_attachments SET state='deleted',cleaned=0,cleanup_version=cleanup_version+1 WHERE notice_id=? AND EXISTS(SELECT 1 FROM jac_deleted_alerts WHERE id=?)").bind(target,target),
  db.prepare('DELETE FROM jac_push_deliveries WHERE notice_id=? AND EXISTS(SELECT 1 FROM jac_deleted_alerts WHERE id=?)').bind(target,target),
  db.prepare('DELETE FROM jac_notice_recipients WHERE notice_id=? AND EXISTS(SELECT 1 FROM jac_deleted_alerts WHERE id=?)').bind(target,target),
  db.prepare("DELETE FROM jac_notices WHERE id=? AND kind='alert' AND EXISTS(SELECT 1 FROM jac_deleted_alerts WHERE id=?)").bind(target,target),
 ]);
 if(!await db.prepare('SELECT id FROM jac_deleted_alerts WHERE id=?').bind(target).first())throw new NoticeFailure('La alerta no está disponible.',404);
 await purgeNoticeAttachments();
}
// D1 deletion is atomic. Failed R2 cleanup remains queued without restoring access.
export async function purgeDeletedItineraries(id?:string){
 const db=database(),rows=(await db.prepare('SELECT id,file_key,cleanup_version FROM jac_deleted_itineraries WHERE file_deleted=0'+(id?' AND id=?':'')+' LIMIT 20').bind(...(id?[id]:[])).all<{id:string;file_key:string;cleanup_version:number}>()).results;
 for(const row of rows){try{if(row.file_key)await env.BUCKET.delete(row.file_key);await db.prepare('UPDATE jac_deleted_itineraries SET file_deleted=1 WHERE id=? AND cleanup_version=?').bind(row.id,row.cleanup_version).run();}catch{/* Retry only the private PDF cleanup on the next refresh. */}}
}
async function deleteTravelNotice(u:AccessUser,id:unknown,confirmation:unknown,authorize:()=>Promise<boolean>,kind:"itinerary"|"boarding_pass"){
 if(!noticeOwner(u))throw new NoticeFailure('Solo un administrador puede eliminar itinerarios y sus pases.',403);
 if(!uuid.safeParse(id).success||confirmation!==id)throw new NoticeFailure('Confirma el documento que deseas eliminar.');
 const target=id as string,db=database(),item=await db.prepare('SELECT kind FROM jac_notices WHERE id=?').bind(target).first<{kind:string}>();
 if(item&&item.kind!==kind)throw new NoticeFailure(kind==='boarding_pass'?'Selecciona un pase de abordar para eliminar.':'Selecciona un itinerario para eliminar.');
 if(item&&kind==='boarding_pass')await allowedNotice(u,target);
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);
 await db.batch([
  db.prepare("INSERT OR IGNORE INTO jac_deleted_itineraries (id,source,file_key,deleted_at) SELECT id,source,file_key,? FROM jac_notices WHERE id=? AND kind=? AND (?='itinerary' OR EXISTS(SELECT 1 FROM jac_notice_recipients WHERE notice_id=? AND user_id=?))").bind(now(),target,kind,kind,target,u.id),
  db.prepare("UPDATE jac_notice_attachments SET state='deleted',cleaned=0,cleanup_version=cleanup_version+1 WHERE notice_id=? AND EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE id=?)").bind(target,target),
  db.prepare('DELETE FROM jac_push_deliveries WHERE notice_id=? AND EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE id=?)').bind(target,target),
  db.prepare('DELETE FROM jac_notice_recipients WHERE notice_id=? AND EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE id=?)').bind(target,target),
  db.prepare('DELETE FROM jac_itinerary_updates WHERE notice_id=? AND EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE id=?)').bind(target,target),
  db.prepare("DELETE FROM jac_notices WHERE id=? AND kind=? AND EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE id=?)").bind(target,kind,target),
  db.prepare("UPDATE jac_slack_files SET status='deleted',error='' WHERE 'slack:'||id=(SELECT source FROM jac_deleted_itineraries WHERE id=?)").bind(target),
 ]);
 if(!await db.prepare('SELECT id FROM jac_deleted_itineraries WHERE id=?').bind(target).first())throw new NoticeFailure('El itinerario no está disponible.',404);
 await purgeDeletedItineraries(target);await purgeNoticeAttachments();
}
export async function deleteItinerary(u:AccessUser,id:unknown,confirmation:unknown,authorize:()=>Promise<boolean>){return deleteTravelNotice(u,id,confirmation,authorize,'itinerary');}
export async function deleteBoardingPass(u:AccessUser,id:unknown,confirmation:unknown,authorize:()=>Promise<boolean>){return deleteTravelNotice(u,id,confirmation,authorize,'boarding_pass');}
export async function configureNotices(kind:string,input:Record<string,unknown>,authorize:()=>Promise<boolean>){
 const c=await noticeConfig();if(input.version!==c.version)throw new NoticeFailure('La configuración cambió. Actualiza antes de guardar.',409);const keys=await pushCredentials(c);
 if(kind==='web')keys.web??=await createWebKeys();
 else if(kind==='apple'){
  const p=z.object({teamId:z.string().regex(/^[A-Z0-9]{10}$/),keyId:z.string().regex(/^[A-Z0-9]{10}$/),privateKey:z.string().min(50).max(8000)}).safeParse(input);
  if(!p.success)throw new NoticeFailure('Revisa Team ID, Key ID y la clave .p8 de Apple.');await appleKey(p.data.privateKey);keys.apns=p.data;
 }else if(kind==='slack'){
  const p=z.object({token:z.string().regex(/^xoxb-[A-Za-z0-9-]{15,200}$/),signingSecret:z.string().regex(/^[a-f0-9]{32}$/)}).safeParse(input);
  if(!p.success)throw new NoticeFailure('Revisa Bot Token y Signing Secret de la app de Slack.');
  const auth=await slackGet('auth.test',p.data.token);if(auth.team_id!==ITINERARY_TEAM)throw new NoticeFailure('La app de Slack debe estar instalada en JAC Music.');
  const info=await slackGet('conversations.info',p.data.token,{channel:ITINERARY_CHANNEL}),channel=info.channel as {is_member?:boolean;is_archived?:boolean}|undefined;
  if(!channel?.is_member||channel.is_archived)throw new NoticeFailure('Invita el bot de integración a #itinerarios-finales antes de guardar.');keys.slack=p.data;
 }else throw new NoticeFailure('Configuración no válida.');
 const encrypted=await encryptMail(keys,mailKey());if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
 await database().prepare('INSERT OR IGNORE INTO jac_notice_settings (id) VALUES (?)').bind('jac').run();
 const result=await database().prepare('UPDATE jac_notice_settings SET credentials=?,version=version+1 WHERE id=? AND version=?').bind(encrypted,'jac',c.version).run();if(result.meta.changes!==1)throw new NoticeFailure('La configuración cambió. Actualiza antes de guardar.',409);
 return settings();
}
export async function registerDevice(u:AccessUser,body:Record<string,unknown>,sessionId:string,authorize:()=>Promise<boolean>){
 if(!uuid.safeParse(body.id).success||!sessionId)throw new NoticeFailure('El dispositivo no es válido.');let data:unknown;
 if(body.platform==='ios'){const p=z.object({token:z.string().regex(/^[a-f0-9]{64,200}$/),environment:z.enum(['sandbox','production'])}).safeParse(body);if(!p.success)throw new NoticeFailure('El registro del iPhone no es válido.');data=p.data;}
 else if(body.platform==='web'){const p=z.object({subscription:z.object({endpoint:z.string().max(4096),keys:z.object({p256dh:z.string().max(100),auth:z.string().max(30)})})}).safeParse(body);if(!p.success)throw new NoticeFailure('La suscripción del navegador no es válida.');data=validateSubscription(p.data.subscription);if(!(await pushCredentials()).web)throw new NoticeFailure('Camilo debe activar primero las notificaciones del navegador.',409);}
 else throw new NoticeFailure('Dispositivo no válido.');
 const cipher=await encryptMail(data,mailKey());if(!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);
 const result=await database().prepare("INSERT INTO jac_push_devices (id,user_id,user_version,platform,data,session_id,updated_at) SELECT ?,id,version,?,?,?,? FROM payroll_users WHERE id=? AND active=1 AND password_hash<>'' ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id,user_version=excluded.user_version,platform=excluded.platform,data=excluded.data,session_id=excluded.session_id,enabled=1,updated_at=excluded.updated_at").bind(body.id,body.platform,cipher,tokenHash(sessionId),now(),u.id).run();if(result.meta.changes!==1)throw new NoticeFailure('Tu acceso cambió. Inicia sesión de nuevo.',403);
}
export async function unregisterDevice(u:AccessUser,id:unknown){if(!uuid.safeParse(id).success)throw new NoticeFailure('Selecciona un dispositivo válido.');await database().prepare('UPDATE jac_push_devices SET enabled=0 WHERE id=? AND user_id=?').bind(id,u.id).run();}
export async function queuePush(id:string){await database().prepare("INSERT OR IGNORE INTO jac_push_deliveries (id,notice_id,device_id,updated_at,notice_revision) SELECT ?||'|'||d.id||CASE WHEN n.revision=1 THEN '' ELSE '|v'||n.revision END,?,d.id,?,n.revision FROM jac_push_devices d JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN jac_notice_recipients r ON r.user_id=u.id AND r.notice_id=? JOIN jac_notices n ON n.id=r.notice_id WHERE r.push_target=1 AND d.enabled=1 AND u.active=1 AND u.password_hash<>''").bind(id,id,now(),id).run();}
export async function dispatchPush(){
 const keys=await pushCredentials();
 const rows=(await database().prepare("SELECT p.id,p.notice_id,p.device_id,d.user_id,d.platform,d.data FROM jac_push_deliveries p JOIN jac_push_devices d ON d.id=p.device_id JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN jac_notice_recipients r ON r.notice_id=p.notice_id AND r.user_id=u.id WHERE p.status='pending' AND d.enabled=1 AND u.active=1 AND u.password_hash<>'' ORDER BY p.updated_at LIMIT 24").all<{id:string;notice_id:string;device_id:string;user_id:string;platform:string;data:string}>()).results;
 await Promise.all(rows.map(async row=>{
  const claimed=await database().prepare("UPDATE jac_push_deliveries SET status='sending',updated_at=? WHERE id=? AND status='pending'").bind(now(),row.id).run();if(claimed.meta.changes!==1)return;
  let state='uncertain';
  try{
   // A permission/account change after listing must prevent the provider call.
   const activeDelivery=()=>database().prepare("SELECT d.id,n.kind,n.title,n.body,n.revision,n.change_summary AS changeSummary FROM jac_push_devices d JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN jac_notice_recipients r ON r.user_id=u.id AND r.notice_id=? AND r.push_target=1 JOIN jac_notices n ON n.id=r.notice_id JOIN jac_push_deliveries p ON p.device_id=d.id AND p.notice_id=n.id WHERE p.notice_revision=n.revision AND p.id=? AND p.status='sending' AND d.id=? AND d.data=? AND d.user_id=? AND d.enabled=1 AND u.active=1 AND u.password_hash<>''").bind(row.notice_id,row.id,row.device_id,row.data,row.user_id).first<{id:string;kind:Notice['kind'];title:string;body:string;revision:number;changeSummary:string}>();
   const active=await activeDelivery();
   if(!active)state='disabled';else if(row.platform==='ios'?!keys.apns:!keys.web)state='unconfigured';
   else{
    const data=await decryptMail<Record<string,string>|WebSubscription>(row.data,mailKey());
    const content=noticePushContent(active);
    const request=row.platform==='ios'?await applePushRequest((data as Record<string,string>).token,(data as Record<string,string>).environment,keys.apns!,row.notice_id,content):await webPushRequest(data as WebSubscription,keys.web!,JSON.stringify({id:row.notice_id,...content}));
    // Encryption/signing can yield: revalidate deletion and access immediately before sending.
    if(!await activeDelivery()){await database().prepare("UPDATE jac_push_deliveries SET status='disabled',updated_at=? WHERE id=? AND status='sending'").bind(now(),row.id).run();return;}
    const response=await fetch(request.url,request.options);state=response.ok?'sent':response.status===404||response.status===410?'expired':'failed';
    if(state==='expired')await database().prepare('UPDATE jac_push_devices SET enabled=0 WHERE id=? AND data=?').bind(row.device_id,row.data).run();
   }
  }catch{/* Delivery might have reached the provider: do not silently resend. */}
  await database().prepare('UPDATE jac_push_deliveries SET status=?,updated_at=? WHERE id=?').bind(state,now(),row.id).run();
 }));
}
async function slackGet(method:string,token:string,params:Record<string,string>={}){const url=new URL('https://slack.com/api/'+method);url.search=new URLSearchParams(params).toString();const response=await fetch(url,{headers:{Authorization:'Bearer '+token},redirect:'manual',signal:AbortSignal.timeout(8000)});const result=await response.json().catch(()=>({})) as Record<string,unknown>;if(!response.ok||!result.ok)throw new NoticeFailure('Slack no permitió acceder al canal o archivo. Revisa la app y sus permisos.',502);return result;}
export async function queueSlackFiles(ids:string[],channel=ITINERARY_CHANNEL){
 const mapping=channel===ITINERARY_CHANNEL?null:await database().prepare('SELECT c.user_id,c.version FROM jac_boarding_channels c JOIN payroll_users u ON u.id=c.user_id WHERE c.id=? AND c.enabled=1 AND u.active=1').bind(channel).first<{user_id:string;version:number}>();
 if(channel!==ITINERARY_CHANNEL&&!mapping)return;
 for(const id of ids)await database().prepare('INSERT OR IGNORE INTO jac_slack_files (id,created_at,channel_id,recipient_id,mapping_version) SELECT ?,?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE source=?)').bind(id,now(),channel,mapping?.user_id??'',mapping?.version??0,'slack:'+id).run();
}
export async function boardingFeed(u:AccessUser,history=false,cursor=''){
 if(cursor&&!/^20\d{2}-\d{2}-\d{2}\|[a-f0-9-]{36}$/.test(cursor))throw new NoticeFailure('Actualiza el listado.');
 const [date,id]=cursor.split('|'),today=boardingToday(),direction=history?'DESC':'ASC',op=history?'<':'>';
 const rows=(await database().prepare(`SELECT n.*,r.read_at,r.confirmed_revision,r.confirmed_at FROM jac_notices n JOIN jac_notice_recipients r ON r.notice_id=n.id AND r.user_id=? WHERE n.kind='boarding_pass' AND n.travel_date${history?'<':'>='}? ${cursor?`AND (n.travel_date${op}? OR (n.travel_date=? AND n.id${op}?))`:''} ORDER BY n.travel_date ${direction},n.id ${direction} LIMIT 41`).bind(u.id,today,...(cursor?[date,date,id]:[])).all<Row>()).results;
 const list=rows.slice(0,40),last=list.at(-1);return {settings:await settings(),users:[],notices:await noticeViews(list),today,nextCursor:rows.length>40&&last?last.travel_date+'|'+last.id:''};
}
export async function configureBoardingChannels(input:unknown,authorize:()=>Promise<boolean>){
 const parsed=z.object({channels:z.array(z.object({id:z.string(),userId:uuid,version:z.number().int().min(0)}).strict()).length(3)}).strict().safeParse(input);
 if(!parsed.success)throw new NoticeFailure('Asigna una cuenta a cada canal.');const channels=parsed.data.channels;
 if(new Set(channels.map(c=>c.id)).size!==3||new Set(channels.map(c=>c.userId)).size!==3||channels.some(c=>!BOARDING_CHANNELS.some(known=>known.id===c.id)))throw new NoticeFailure('Revisa los tres canales y sus cuentas individuales.');
 const keys=await pushCredentials();if(!keys.slack)throw new NoticeFailure('Primero conecta la app de Slack existente.');
 for(const c of channels){const expected=BOARDING_CHANNELS.find(k=>k.id===c.id)!;if(!await database().prepare('SELECT id FROM payroll_users WHERE id=? AND email=? AND active=1').bind(c.userId,({'C0C7QKT2FJQ':'camilo@mac2you.co','C0C8FAPHTCG':'jhonalexcastano@gmail.com','C0C7K0QCMKQ':'alexzuluagaazp@gmail.com'} as Record<string,string>)[c.id]).first())throw new NoticeFailure('El canal debe corresponder a la cuenta indicada.');const result=await slackGet('conversations.info',keys.slack.token,{channel:c.id}),info=result.channel as {id?:string;is_member?:boolean;is_archived?:boolean};if(info?.id!==c.id||!info.is_member||info.is_archived)throw new NoticeFailure('Invita JAC Itinerarios a '+expected.name+' antes de guardar.');}
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
 // One CAS across all three bindings; a stale settings form cannot partially overwrite them.
 const clauses=channels.map(()=>'(id=? AND version=?)').join(' OR '),params=channels.flatMap(c=>[c.id,c.version]);
 const count=channels.filter(c=>c.version>0).length;
 const gate=`(SELECT count(*) FROM jac_boarding_channels WHERE ${clauses})=${count} AND (SELECT count(*) FROM jac_boarding_channels)=${count}`;
 const result=await database().prepare(`INSERT INTO jac_boarding_channels(id,user_id,created_at) SELECT column1,column2,column3 FROM (VALUES ${channels.map(()=>'(?,?,?)').join(',')}) WHERE ${gate} ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id,enabled=1,version=jac_boarding_channels.version+1,created_at=excluded.created_at`).bind(...channels.flatMap(c=>[c.id,c.userId,now()]),...params).run();
 if(result.meta.changes!==3)throw new NoticeFailure('La asignación cambió. Actualiza el listado.',409);
}

export async function importSlackFiles(){
 await purgeDeletedItineraries();
 const keys=await pushCredentials();if(!keys.slack){await dispatchPush();return;}
 const slack=keys.slack;
 const rows=(await database().prepare("SELECT id,channel_id,recipient_id,mapping_version,created_at FROM jac_slack_files WHERE status='pending' OR (status='processing' AND started_at<?) ORDER BY created_at LIMIT 5").bind(new Date(Date.now()-60000).toISOString()).all<{id:string;channel_id:string;recipient_id:string;mapping_version:number;created_at:string}>()).results;
 await Promise.all(rows.map(async ({id,channel_id,recipient_id,mapping_version,created_at})=>{
  const claimed=await database().prepare("UPDATE jac_slack_files SET status='processing',started_at=? WHERE id=? AND (status='pending' OR (status='processing' AND started_at<?))").bind(now(),id,new Date(Date.now()-60000).toISOString()).run();if(claimed.meta.changes!==1)return;
  try{
   if(await database().prepare('SELECT id FROM jac_deleted_itineraries WHERE source=?').bind('slack:'+id).first()){await database().prepare("UPDATE jac_slack_files SET status='deleted',error='' WHERE id=?").bind(id).run();return;}
   if(channel_id!==ITINERARY_CHANNEL){await importBoardingSlackFile({id,channel_id,recipient_id,mapping_version,created_at},slack.token);return;}
   const exists=await database().prepare('SELECT id FROM jac_notices WHERE source=?').bind('slack:'+id).first<{id:string}>();
   if(exists){await queuePush(exists.id);await database().prepare("UPDATE jac_slack_files SET status='ready',error='' WHERE id=? AND status<>'deleted'").bind(id).run();return;}
   const info=await slackGet('files.info',slack.token,{file:id}),f=info.file as {id:string;mimetype:string;size:number;name:string;url_private_download:string;channels?:string[];shares?:{public?:Record<string,unknown>}};
   if(!f||f.id!==id||f.mimetype!=='application/pdf'||!((f.channels??[]).includes(ITINERARY_CHANNEL)||f.shares?.public?.[ITINERARY_CHANNEL]))throw new NoticeFailure('Solo se importan PDF compartidos en #itinerarios-finales.');
   if(f.size>MAX_PDF_BYTES)throw new NoticeFailure('El PDF supera el límite de 10 MB.');
   const url=new URL(f.url_private_download);if(url.protocol!=='https:'||url.hostname!=='files.slack.com'||url.port||url.username||url.password)throw new NoticeFailure('Slack devolvió una dirección de archivo no admitida.');
   const response=await fetch(url,{headers:{Authorization:'Bearer '+slack.token},redirect:'manual',signal:AbortSignal.timeout(8000)});
   if(!response.ok||!response.body)throw new NoticeFailure('Slack no permitió descargar el PDF.',502);
   const reader=response.body.getReader(),parts:Uint8Array[]=[];let size=0;for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>MAX_PDF_BYTES){await reader.cancel();throw new NoticeFailure('El PDF supera el límite de 10 MB.');}parts.push(next.value);}
   const pdf=new Uint8Array(size);let offset=0;for(const p of parts){pdf.set(p,offset);offset+=p.length;}if(new TextDecoder().decode(pdf.slice(0,5))!=='%PDF-')throw new NoticeFailure('El archivo recibido no es un PDF válido.');
   const fileKey='itineraries/'+id+'.pdf',filename=(f.name??'Itinerario.pdf').replace(/[\x00-\x1f/\\]/g,'_').slice(0,160),nid=crypto.randomUUID(),stamp=now();
   await env.BUCKET.put(fileKey,pdf,{onlyIf:{etagDoesNotMatch:'*'},httpMetadata:{contentType:'application/pdf'}});
   try{await database().batch([database().prepare("INSERT OR IGNORE INTO jac_notices (id,kind,title,file_key,filename,size,source,created_at) SELECT ?,'itinerary',?,?,?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE source=?)").bind(nid,filename.replace(/\.pdf$/i,''),fileKey,filename,size,'slack:'+id,stamp,'slack:'+id),database().prepare("INSERT OR IGNORE INTO jac_notice_recipients (id,notice_id,user_id) SELECT n.id||'|'||u.id,n.id,u.id FROM jac_notices n CROSS JOIN payroll_users u WHERE n.source=? AND u.active=1 AND u.password_hash<>''").bind('slack:'+id),database().prepare("UPDATE jac_slack_files SET status=CASE WHEN EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE source=?) THEN 'deleted' ELSE 'ready' END,error='' WHERE id=?").bind('slack:'+id,id)]);
   const saved=await database().prepare('SELECT id FROM jac_notices WHERE source=?').bind('slack:'+id).first<{id:string}>();if(saved)await queuePush(saved.id);
   }finally{
   // An old import lease can finish uploading after deletion; remove that late copy too.
   const deleted=await database().prepare('UPDATE jac_deleted_itineraries SET file_deleted=0,cleanup_version=cleanup_version+1 WHERE source=?').bind('slack:'+id).run();if(deleted.meta.changes)await purgeDeletedItineraries();
   }
  }catch(e){await database().prepare("UPDATE jac_slack_files SET status='failed',error=? WHERE id=? AND status<>'deleted'").bind(e instanceof NoticeFailure?e.message:'No se pudo importar el PDF. Revisa la conexión y reintenta.',id).run();}
 }));
 await dispatchPush();
}
export async function retryImports(){await database().prepare("UPDATE jac_slack_files SET status='pending',error='' WHERE status='failed'").run();}
export async function itineraryPdf(u:AccessUser,id:string){const item=await allowedNotice(u,id);if(item.kind!=='itinerary'||!item.file_key)throw new NoticeFailure('Este aviso no tiene un PDF.',404);const object=await env.BUCKET.get(item.file_key);if(!object)throw new NoticeFailure('El PDF todavía no está disponible.',404);if((await allowedNotice(u,id)).file_key!==item.file_key)throw new NoticeFailure('El itinerario cambió. Abre la versión actual.',409);return {item,object};}

// Staged uploads are tracked before R2 writes. Cleanup leases cannot discard a late upload.
export async function purgeNoticeAttachments(){
 const db=database();await db.prepare("UPDATE jac_notice_attachments SET state='deleted',cleaned=0,cleanup_version=cleanup_version+1 WHERE state='staged' AND expires_at<?").bind(now()).run();
 const rows=(await db.prepare("SELECT id,file_key,cleanup_version FROM jac_notice_attachments WHERE state='deleted' AND cleaned=0 LIMIT 30").all<{id:string;file_key:string;cleanup_version:number}>()).results;
 for(const row of rows){try{await env.BUCKET.delete(row.file_key);await db.prepare("UPDATE jac_notice_attachments SET cleaned=1,filename='',notice_id='' WHERE id=? AND state='deleted' AND cleanup_version=?").bind(row.id,row.cleanup_version).run();}catch{/* Access stays revoked; refresh retries private-file cleanup. */}}
}
export async function publishManualNotice(u:AccessUser,input:unknown,authorize:()=>Promise<boolean>){
 if(!noticeOwner(u))throw new NoticeFailure('Solo un administrador puede crear alertas e itinerarios.',403);
 const parsed=manualNoticeSchema.safeParse(input);if(!parsed.success)throw new NoticeFailure('Revisa título, mensaje, destinatarios y adjuntos.');const p=parsed.data;
 if(p.kind==='alert'&&(!p.body||!p.recipients.length))throw new NoticeFailure('Ingresa un mensaje y elige al menos un destinatario.');
 const files=decodeNoticeFiles(p.files),db=database();let travelDate='';
 if(p.kind==='boarding_pass'){
  if(p.recipients.length!==1||!files.length)throw new NoticeFailure('Elige una sola persona y adjunta al menos un pase.');
  const person=await db.prepare('SELECT email FROM payroll_users WHERE id=? AND active=1').bind(p.recipients[0]).first<{email:string}>();
  for(const file of files){const info=boardingFilenameDetails(file.filename);if(info){const identity=boardingPassengerKey(info.passenger),email=identity?boardingIdentityEmails[identity]:null;if(!email||email!==person?.email)throw new NoticeFailure('El pasajero del archivo no corresponde a la persona elegida. Revisa el nombre y el destinatario.');}}
  const dates=files.map(f=>boardingFilenameDate(f.filename));
  travelDate=p.travelDate??dates[0]??'';
  if(!validBoardingDate(travelDate)||dates.some(d=>d&&d!==travelDate))throw new NoticeFailure('Revisa la fecha. Publica por separado los pases de días diferentes. Usa nombres como Camilo 10 de octubre 2026.pdf.');
 }else if(p.travelDate)throw new NoticeFailure('La fecha de viaje solo corresponde a pases de abordar.');
 const digest=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes as BufferSource)),b=>b.toString(16).padStart(2,'0')).join('');
 const hash=await digest(new TextEncoder().encode(JSON.stringify({kind:p.kind,title:p.title,body:p.body,...(p.kind==='boarding_pass'?{travelDate}:{}),recipients:p.kind!=='itinerary'?[...new Set(p.recipients)].sort():[],files:await Promise.all(files.map(async f=>({filename:f.filename,mimeType:f.mimeType,hash:await digest(f.bytes)})))})));
 const isDeleted=async()=>!!await db.prepare('SELECT id FROM jac_deleted_alerts WHERE id=? UNION ALL SELECT id FROM jac_deleted_itineraries WHERE id=?').bind(p.id,p.id).first();
 const existing=async()=>db.prepare('SELECT manual_hash FROM jac_notices WHERE id=?').bind(p.id).first<{manual_hash:string}>();
 if(await isDeleted())throw new NoticeFailure('Este aviso fue eliminado. Abre un formulario nuevo.',410);
 const previous=await existing();if(previous){if(!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);if(previous.manual_hash!==hash)throw new NoticeFailure('Esta solicitud ya guardó otro contenido. Abre un formulario nuevo.',409);await queuePush(p.id);return p.id;}
 const ids=p.kind==='itinerary'?(await db.prepare("SELECT id FROM payroll_users WHERE active=1 AND password_hash<>'' ORDER BY id").all<{id:string}>()).results.map(x=>x.id):[...new Set(p.recipients)].sort();
 const active=(await db.prepare(`SELECT id FROM payroll_users WHERE active=1 ${p.kind==='itinerary'?"AND password_hash<>''":''} AND id IN (${ids.map(()=>'?').join(',')||"''"})`).bind(...ids).all()).results;if(active.length!==ids.length)throw new NoticeFailure('Algún destinatario cambió. Actualiza el listado.',409);
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);
 const uploadToken=crypto.randomUUID();const uploads=files.map(f=>({...f,id:crypto.randomUUID(),key:'notice-attachments/'+crypto.randomUUID()}));let committed=false;
 try{
  for(const file of uploads){await db.prepare("INSERT INTO jac_notice_attachments(id,file_key,filename,mime_type,size,expires_at) VALUES (?,?,?,?,?,?)").bind(file.id,file.key,file.filename,file.mimeType,file.size,new Date(Date.now()+3600000).toISOString()).run();await env.BUCKET.put(file.key,file.bytes,{httpMetadata:{contentType:file.mimeType}});}
  if(!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);
  const validUploads=uploads.length?` AND (SELECT count(*) FROM jac_notice_attachments WHERE id IN (${uploads.map(()=>'?').join(',')}) AND state='staged')=${uploads.length}`:'';
  const result=await db.batch([
   db.prepare(`INSERT OR IGNORE INTO jac_notices(id,kind,title,body,source,manual_hash,upload_token,created_at,travel_date) SELECT ?,?,?,?,?,?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM jac_deleted_alerts WHERE id=?) AND NOT EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE id=?)${validUploads} AND (SELECT count(*) FROM payroll_users WHERE active=1 AND id IN (${ids.map(()=>'?').join(',')||"''"}))=${ids.length}`).bind(p.id,p.kind,p.title,p.body,'manual:'+p.id,hash,uploadToken,now(),travelDate,p.id,p.id,...uploads.map(f=>f.id),...ids),
   ...uploads.map(file=>db.prepare("UPDATE jac_notice_attachments SET notice_id=?,state='ready' WHERE id=? AND state='staged' AND EXISTS(SELECT 1 FROM jac_notices WHERE id=? AND upload_token=?)").bind(p.id,file.id,p.id,uploadToken)),
   ...ids.map(id=>db.prepare("INSERT OR IGNORE INTO jac_notice_recipients(id,notice_id,user_id) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM jac_notices WHERE id=? AND upload_token=?)").bind(p.id+'|'+id,p.id,id,p.id,uploadToken))
  ]);
  committed=result[0].meta.changes===1;
  if(await isDeleted())throw new NoticeFailure('Este aviso fue eliminado. Abre un formulario nuevo.',410);
  const saved=await existing();if(!saved)throw new NoticeFailure('No se pudieron guardar los archivos. Intenta de nuevo.',409);if(saved.manual_hash!==hash)throw new NoticeFailure('Esta solicitud ya guardó otro contenido. Abre un formulario nuevo.',409);
  await queuePush(p.id);return p.id;
 }finally{if(!committed){for(const file of uploads)await db.prepare("UPDATE jac_notice_attachments SET state='deleted',cleaned=0,cleanup_version=cleanup_version+1 WHERE id=? AND state<>'ready'").bind(file.id).run();await purgeNoticeAttachments();}}
}
export async function noticeAttachment(u:AccessUser,id:string,file:string){
 const item=await allowedNotice(u,id);if(file===id&&item.file_key){const object=await env.BUCKET.get(item.file_key);if(!object)throw new NoticeFailure('El archivo no está disponible.',404);if((await allowedNotice(u,id)).file_key!==item.file_key)throw new NoticeFailure('El itinerario cambió. Abre la versión actual.',409);return {filename:item.filename,mimeType:'application/pdf',object};}
 if(!uuid.safeParse(file).success)throw new NoticeFailure('El archivo no está disponible.',404);
 const get=()=>database().prepare("SELECT file_key,filename,mime_type FROM jac_notice_attachments WHERE id=? AND notice_id=? AND state='ready'").bind(file,id).first<{file_key:string;filename:string;mime_type:string}>();
 const row=await get();if(!row)throw new NoticeFailure('El archivo no está disponible.',404);const object=await env.BUCKET.get(row.file_key);if(!object)throw new NoticeFailure('El archivo no está disponible.',404);await allowedNotice(u,id);if(!await get())throw new NoticeFailure('El archivo fue eliminado.',404);return {filename:row.filename,mimeType:row.mime_type,object};
}

const boardingIdentityEmails:Record<string,string>={camilo:'camilo@mac2you.co','jhon-alex':'jhonalexcastano@gmail.com','alex-zuluaga':'alexzuluagaazp@gmail.com'};
async function importBoardingSlackFile(row:{id:string;channel_id:string;recipient_id:string;mapping_version:number;created_at:string},token:string){
 const db=database(),{id,channel_id,recipient_id,mapping_version}=row;
 const gate="EXISTS(SELECT 1 FROM jac_boarding_channels c JOIN payroll_users u ON u.id=c.user_id WHERE c.id=? AND c.user_id=? AND c.version=? AND c.enabled=1 AND u.active=1)";
 const bindings=[channel_id,recipient_id,mapping_version];
 if(!await db.prepare('SELECT 1 WHERE '+gate).bind(...bindings).first())throw new NoticeFailure('La asignación del canal cambió. No se importó el pase.');
 const existing=await db.prepare('SELECT id FROM jac_notices WHERE source=? AND kind=\'boarding_pass\'').bind('slack:'+id).first<{id:string}>();
 if(existing){await queuePush(existing.id);await db.prepare("UPDATE jac_slack_files SET status='ready',error='' WHERE id=? AND status<>'deleted'").bind(id).run();return;}
 const info=await slackGet('files.info',token,{file:id}),file=info.file as {id:string;name:string;mimetype:string;size:number;url_private_download:string;channels?:string[];shares?:{public?:Record<string,unknown>}};
 if(!file||file.id!==id||!['application/pdf','image/png','image/jpeg'].includes(file.mimetype)||!((file.channels??[]).includes(channel_id)||file.shares?.public?.[channel_id]))throw new NoticeFailure('El pase debe ser un PDF, JPG o PNG compartido en su canal asignado.');
 const travelDate=boardingFilenameDate(file.name,new Date(row.created_at));if(!travelDate)throw new NoticeFailure('El pase no tiene una fecha válida en el nombre. Usa Nombre 10 de octubre 2026.pdf y vuelve a subirlo.');
 const metadata=boardingFilenameDetails(file.name);if(metadata){const identity=boardingPassengerKey(metadata.passenger),person=await db.prepare('SELECT email FROM payroll_users WHERE id=? AND active=1').bind(recipient_id).first<{email:string}>();if(!identity||boardingIdentityEmails[identity]!==person?.email)throw new NoticeFailure('El pasajero del archivo no corresponde al canal. Corrige el nombre o súbelo al canal de su destinatario.');}
 if(file.size>MAX_PDF_BYTES)throw new NoticeFailure('El pase supera los 10 MB.');
 const url=new URL(file.url_private_download);if(url.protocol!=='https:'||url.hostname!=='files.slack.com'||url.port||url.username||url.password)throw new NoticeFailure('Dirección de archivo no admitida.');
 const response=await fetch(url,{headers:{Authorization:'Bearer '+token},redirect:'manual',signal:AbortSignal.timeout(8000)});if(!response.ok||!response.body)throw new NoticeFailure('Slack no permitió descargar el pase.');
 const reader=response.body.getReader(),parts:Uint8Array[]=[];let size=0;for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>MAX_PDF_BYTES){await reader.cancel();throw new NoticeFailure('El pase supera los 10 MB.');}parts.push(next.value);}
 const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}if(fileMime(bytes)!==file.mimetype)throw new NoticeFailure('El contenido del pase no corresponde a su formato.');
 const filename=file.name.replace(/[\x00-\x1f/\\]/g,'_').slice(0,160),nid=crypto.randomUUID(),attachment=crypto.randomUUID(),key='notice-attachments/'+crypto.randomUUID(),stamp=now();let committed=false;
 try{
  await db.prepare('INSERT INTO jac_notice_attachments(id,file_key,filename,mime_type,size,expires_at) VALUES (?,?,?,?,?,?)').bind(attachment,key,filename,file.mimetype,size,new Date(Date.now()+3600000).toISOString()).run();await env.BUCKET.put(key,bytes,{httpMetadata:{contentType:file.mimetype}});
  const result=await db.batch([
   db.prepare(`INSERT OR IGNORE INTO jac_notices(id,kind,title,source,created_at,travel_date) SELECT ?,'boarding_pass',?,?,?,? WHERE ${gate} AND EXISTS(SELECT 1 FROM jac_notice_attachments WHERE id=? AND state='staged') AND NOT EXISTS(SELECT 1 FROM jac_deleted_itineraries WHERE source=?)`).bind(nid,'Pase de abordar · '+travelDate,'slack:'+id,stamp,travelDate,...bindings,attachment,'slack:'+id),
   db.prepare("UPDATE jac_notice_attachments SET notice_id=?,state='ready' WHERE id=? AND state='staged' AND EXISTS(SELECT 1 FROM jac_notices WHERE id=?)").bind(nid,attachment,nid),
   db.prepare('INSERT OR IGNORE INTO jac_notice_recipients(id,notice_id,user_id) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM jac_notices WHERE id=?)').bind(nid+'|'+recipient_id,nid,recipient_id,nid)
  ]);committed=result[0].meta.changes===1;
  const saved=await db.prepare("SELECT id FROM jac_notices WHERE source=? AND kind='boarding_pass'").bind('slack:'+id).first<{id:string}>();if(!saved)throw new NoticeFailure('La cuenta o asignación cambió. No se importó el pase.');
  await queuePush(saved.id);await db.prepare("UPDATE jac_slack_files SET status='ready',error='' WHERE id=? AND status<>'deleted'").bind(id).run();
 }finally{if(!committed){await db.prepare("UPDATE jac_notice_attachments SET state='deleted',cleaned=0,cleanup_version=cleanup_version+1 WHERE id=? AND state<>'ready'").bind(attachment).run();await purgeNoticeAttachments();}}
}

export async function confirmNotice(u:AccessUser,id:unknown,revision:unknown,authorize:()=>Promise<boolean>){
 if(typeof id!=='string'||!Number.isSafeInteger(revision))throw new NoticeFailure('Actualiza el aviso antes de confirmar.');
 const item=await allowedNotice(u,id);if(item.kind==='boarding_pass')throw new NoticeFailure('La confirmación corresponde a alertas e itinerarios.');
 if(item.revision!==revision)throw new NoticeFailure('El aviso cambió. Lee la versión actual antes de confirmar.',409);
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
 const result=await database().prepare(`INSERT INTO jac_notice_recipients(id,notice_id,user_id,confirmed_revision,confirmed_at,push_target) SELECT ?,?,?,?,?,0 WHERE EXISTS(SELECT 1 FROM jac_notices n WHERE n.id=? AND n.revision=? AND ${accessSql}) ON CONFLICT(id) DO UPDATE SET confirmed_revision=excluded.confirmed_revision,confirmed_at=CASE WHEN jac_notice_recipients.confirmed_revision=excluded.confirmed_revision THEN jac_notice_recipients.confirmed_at ELSE excluded.confirmed_at END`).bind(id+'|'+u.id,id,u.id,revision,now(),id,revision,u.id,noticeOwner(u)?1:0).run();
 if(result.meta.changes!==1)throw new NoticeFailure('El aviso cambió o fue eliminado. Actualiza el listado.',409);
 return noticeItem(u,id);
}
const itineraryUpdateSchema=z.object({id:uuid,requestId:uuid,revision:z.number().int().positive(),title:z.string().trim().min(1).max(120),body:z.string().trim().max(2000),summary:z.string().trim().min(3).max(500),files:manualNoticeSchema.shape.files.min(1)}).strict();
export async function updateItinerary(u:AccessUser,input:unknown,authorize:()=>Promise<boolean>){
 if(!noticeOwner(u))throw new NoticeFailure('Solo un administrador puede actualizar itinerarios.',403);
 const parsed=itineraryUpdateSchema.safeParse(input);if(!parsed.success)throw new NoticeFailure('Indica qué cambió y adjunta la versión completa del itinerario.');const p=parsed.data,db=database(),files=decodeNoticeFiles(p.files),hash=await contentHash(p);
 const item=await allowedNotice(u,p.id);if(item.kind!=='itinerary')throw new NoticeFailure('Selecciona un itinerario.');
 const prior=await db.prepare('SELECT hash FROM jac_itinerary_updates WHERE id=?').bind(p.requestId).first<{hash:string}>();
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
 if(prior){if(prior.hash!==hash)throw new NoticeFailure('Este reintento tiene otro contenido.',409);await queuePush(p.id);return p.id;}
 if(item.revision!==p.revision)throw new NoticeFailure('El itinerario cambió. Actualízalo antes de editar.',409);
 const uploads=await stageTravelFiles(files);let committed=false;
 try{
  if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
  const token=crypto.randomUUID(),stamp=now(),gate='EXISTS(SELECT 1 FROM jac_notices WHERE id=? AND upload_token=?)';
  const result=await db.batch([
   db.prepare(`UPDATE jac_notices SET title=?,body=?,change_summary=?,updated_at=?,revision=revision+1,upload_token=?,file_key='',filename='',size=0 WHERE id=? AND kind='itinerary' AND revision=? AND NOT EXISTS(SELECT 1 FROM jac_itinerary_updates WHERE id=?)${uploadedGate(uploads)}`).bind(p.title,p.body,p.summary,stamp,token,p.id,p.revision,p.requestId,...uploadedBindings(uploads)),
   db.prepare(`UPDATE jac_notice_attachments SET state='deleted',cleaned=0,cleanup_version=cleanup_version+1 WHERE notice_id=? AND state='ready' AND ${gate}`).bind(p.id,p.id,token),
   ...uploads.map(f=>db.prepare(`UPDATE jac_notice_attachments SET state='ready',notice_id=? WHERE id=? AND state='staged' AND ${gate}`).bind(p.id,f.id,p.id,token)),
   db.prepare(`UPDATE jac_notice_recipients SET read_at='' WHERE notice_id=? AND ${gate}`).bind(p.id,p.id,token),
   db.prepare(`UPDATE jac_push_deliveries SET status='disabled' WHERE notice_id=? AND status IN ('pending','sending') AND ${gate}`).bind(p.id,p.id,token),
   db.prepare(`INSERT INTO jac_itinerary_updates(id,notice_id,revision,hash,summary,actor_id,created_at) SELECT ?,?,?,?,?,?,? WHERE ${gate}`).bind(p.requestId,p.id,p.revision+1,hash,p.summary,u.id,stamp,p.id,token),
   // Move the legacy Slack PDF into the existing durable cleanup queue.
   ...(item.file_key?[db.prepare(`INSERT INTO jac_notice_attachments(id,notice_id,file_key,filename,mime_type,size,state,expires_at) SELECT ?,?,?,?,'application/pdf',?,'deleted',? WHERE ${gate}`).bind(crypto.randomUUID(),p.id,item.file_key,item.filename,item.size,stamp,p.id,token)]:[])
  ]);committed=result[0].meta.changes===1;
  if(!committed){const saved=await db.prepare('SELECT hash FROM jac_itinerary_updates WHERE id=?').bind(p.requestId).first<{hash:string}>();if(saved?.hash!==hash)throw new NoticeFailure('El itinerario cambió. Actualiza el listado.',409);}
  await queuePush(p.id);return p.id;
 }finally{if(!committed)await discardTravelFiles(uploads);await purgeNoticeAttachments();}
}
