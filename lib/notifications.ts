import {env} from 'cloudflare:workers';
import {z} from 'zod';
import {database} from '@/db/raw';
import {decryptMail,encryptMail} from './payroll-mail-core';
import {mailKey} from './payroll-mail';
import {tokenHash} from './payroll-auth-crypto';
import type {AccessUser} from './payroll-permissions';
import {NoticeFailure,ITINERARY_CHANNEL,ITINERARY_TEAM,MAX_PDF_BYTES,createWebKeys,appleKey,applePushRequest,webPushRequest,validateSubscription,type PushCredentials,type WebSubscription,type Notice} from './notifications-core';

const uuid=z.string().uuid();
const now=()=>new Date().toISOString();
type Config={credentials:string;version:number};
type Row={id:string;kind:'itinerary'|'alert';title:string;body:string;filename:string;size:number;created_at:string;file_key:string;read_at:string};
export const noticeOwner=(u:AccessUser)=>!u.legacy&&u.isOwner&&u.email==='camilo@mac2you.co';
export async function noticeConfig(){return await database().prepare('SELECT credentials,version FROM jac_notice_settings WHERE id=?').bind('jac').first<Config>()??{credentials:'',version:0};}
export async function pushCredentials(c?:Config):Promise<PushCredentials>{const config=c??await noticeConfig();return config.credentials?decryptMail(config.credentials,mailKey()):{};}
async function settings(){const c=await noticeConfig(),keys=await pushCredentials(c);return {version:c.version,slackConnected:!!keys.slack,appleConfigured:!!keys.apns,webPublicKey:keys.web?.publicKey??'',channel:'#itinerarios-finales',webhook:'https://jhonalexcastano.com/api/notices/slack'};}
function view(row:Row):Notice{return {id:row.id,kind:row.kind,title:row.title,body:row.body,filename:row.filename,size:row.size,createdAt:row.created_at,read:!!row.read_at};}
const accessSql="(n.kind='itinerary' OR EXISTS(SELECT 1 FROM jac_notice_recipients a WHERE a.notice_id=n.id AND a.user_id=?) OR ?=1)";
export async function noticeFeed(u:AccessUser,cursor=''){
 if(cursor&&!/^\d{4}-\d{2}-\d{2}T[\d:.]+Z\|[a-f0-9-]{36}$/.test(cursor))throw new NoticeFailure('Actualiza el listado.');
 const [time,id]=cursor.split('|');
 const rows=await database().prepare(`SELECT n.*,r.read_at FROM jac_notices n LEFT JOIN jac_notice_recipients r ON r.notice_id=n.id AND r.user_id=? WHERE ${accessSql} ${cursor?'AND (n.created_at<? OR (n.created_at=? AND n.id<?))':''} ORDER BY n.created_at DESC,n.id DESC LIMIT 41`).bind(u.id,u.id,noticeOwner(u)?1:0,...(cursor?[time,time,id]:[])).all<Row>();
 const all=rows.results,list=all.slice(0,40),last=list.at(-1);
 const users=noticeOwner(u)?(await database().prepare("SELECT id,name FROM payroll_users WHERE active=1 AND password_hash<>'' ORDER BY name").all<{id:string;name:string}>()).results:[];
 const failures=noticeOwner(u)?(await database().prepare("SELECT id,error FROM jac_slack_files WHERE status='failed' ORDER BY created_at DESC LIMIT 20").all<{id:string;error:string}>()).results:[];
 return {notices:list.map(view),nextCursor:all.length>40&&last?last.created_at+'|'+last.id:'',settings:await settings(),users,failures};
}
export async function allowedNotice(u:AccessUser,id:string){if(!uuid.safeParse(id).success)throw new NoticeFailure('El aviso no existe.',404);const row=await database().prepare(`SELECT n.* FROM jac_notices n WHERE n.id=? AND ${accessSql}`).bind(id,u.id,noticeOwner(u)?1:0).first<Row>();if(!row)throw new NoticeFailure('El aviso no está disponible para esta cuenta.',404);return row;}
export async function noticeItem(u:AccessUser,id:string){return view(await allowedNotice(u,id));}
export async function markNoticeRead(u:AccessUser,id:string){await allowedNotice(u,id);await database().prepare('INSERT INTO jac_notice_recipients (id,notice_id,user_id,read_at,push_target) VALUES (?,?,?,?,0) ON CONFLICT(id) DO UPDATE SET read_at=excluded.read_at').bind(id+'|'+u.id,id,u.id,now()).run();}
export async function saveManualNotice(u:AccessUser,body:unknown,authorize:()=>Promise<boolean>){
 const parsed=z.object({id:uuid,title:z.string().trim().min(1).max(120),body:z.string().trim().min(1).max(2000),recipients:z.array(uuid).min(1).max(100)}).strict().safeParse(body);
 if(!parsed.success)throw new NoticeFailure('Ingresa título, mensaje y al menos un destinatario.');const p=parsed.data,ids=[...new Set(p.recipients)].sort();
 const recipients=(await database().prepare(`SELECT id FROM payroll_users WHERE active=1 AND password_hash<>'' AND id IN (${ids.map(()=>'?').join(',')})`).bind(...ids).all<{id:string}>()).results;
 if(recipients.length!==ids.length)throw new NoticeFailure('Algún destinatario ya no está activo. Actualiza el listado.',409);
 const existing=await database().prepare('SELECT title,body FROM jac_notices WHERE id=?').bind(p.id).first<{title:string;body:string}>();
 if(existing){if(!noticeOwner(u)||!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);const previous=(await database().prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=? AND push_target=1 ORDER BY user_id').bind(p.id).all<{user_id:string}>()).results.map(x=>x.user_id);if(existing.title!==p.title||existing.body!==p.body||JSON.stringify(previous)!==JSON.stringify(ids))throw new NoticeFailure('Esta solicitud ya guardó otra alerta. Abre un formulario nuevo.',409);await queuePush(p.id);return p.id;}
 if(!noticeOwner(u)||!await authorize())throw new NoticeFailure('Tu sesión cambió. Inicia sesión de nuevo.',403);
 const stamp=now();await database().batch([database().prepare("INSERT INTO jac_notices (id,kind,title,body,created_at) VALUES (?,'alert',?,?,?)").bind(p.id,p.title,p.body,stamp),...ids.map(id=>database().prepare('INSERT INTO jac_notice_recipients (id,notice_id,user_id) VALUES (?,?,?)').bind(p.id+'|'+id,p.id,id))]);
 await queuePush(p.id);return p.id;
}
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
async function queuePush(id:string){await database().prepare("INSERT OR IGNORE INTO jac_push_deliveries (id,notice_id,device_id,updated_at) SELECT ?||'|'||d.id,?,d.id,? FROM jac_push_devices d JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN jac_notice_recipients r ON r.user_id=u.id AND r.notice_id=? WHERE r.push_target=1 AND d.enabled=1 AND u.active=1 AND u.password_hash<>''").bind(id,id,now(),id).run();}
export async function dispatchPush(){
 const keys=await pushCredentials();
 const rows=(await database().prepare("SELECT p.id,p.notice_id,p.device_id,d.user_id,d.platform,d.data FROM jac_push_deliveries p JOIN jac_push_devices d ON d.id=p.device_id JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN jac_notice_recipients r ON r.notice_id=p.notice_id AND r.user_id=u.id WHERE p.status='pending' AND d.enabled=1 AND u.active=1 AND u.password_hash<>'' ORDER BY p.updated_at LIMIT 24").all<{id:string;notice_id:string;device_id:string;user_id:string;platform:string;data:string}>()).results;
 await Promise.all(rows.map(async row=>{
  const claimed=await database().prepare("UPDATE jac_push_deliveries SET status='sending',updated_at=? WHERE id=? AND status='pending'").bind(now(),row.id).run();if(claimed.meta.changes!==1)return;
  let state='uncertain';
  try{
   // A permission/account change after listing must prevent the provider call.
   const active=await database().prepare("SELECT d.id FROM jac_push_devices d JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN jac_notice_recipients r ON r.user_id=u.id AND r.notice_id=? AND r.push_target=1 WHERE d.id=? AND d.data=? AND d.user_id=? AND d.enabled=1 AND u.active=1 AND u.password_hash<>''").bind(row.notice_id,row.device_id,row.data,row.user_id).first();
   if(!active)state='disabled';else if(row.platform==='ios'?!keys.apns:!keys.web)state='unconfigured';
   else{
    const data=await decryptMail<Record<string,string>|WebSubscription>(row.data,mailKey());
    const request=row.platform==='ios'?await applePushRequest((data as Record<string,string>).token,(data as Record<string,string>).environment,keys.apns!,row.notice_id):await webPushRequest(data as WebSubscription,keys.web!,JSON.stringify({id:row.notice_id,title:'JAC',body:'Tienes un aviso nuevo. Abre JAC para consultarlo.'}));
    const response=await fetch(request.url,request.options);state=response.ok?'sent':response.status===404||response.status===410?'expired':'failed';
    if(state==='expired')await database().prepare('UPDATE jac_push_devices SET enabled=0 WHERE id=? AND data=?').bind(row.device_id,row.data).run();
   }
  }catch{/* Delivery might have reached the provider: do not silently resend. */}
  await database().prepare('UPDATE jac_push_deliveries SET status=?,updated_at=? WHERE id=?').bind(state,now(),row.id).run();
 }));
}
async function slackGet(method:string,token:string,params:Record<string,string>={}){const url=new URL('https://slack.com/api/'+method);url.search=new URLSearchParams(params).toString();const response=await fetch(url,{headers:{Authorization:'Bearer '+token},redirect:'manual',signal:AbortSignal.timeout(8000)});const result=await response.json().catch(()=>({})) as Record<string,unknown>;if(!response.ok||!result.ok)throw new NoticeFailure('Slack no permitió acceder al canal o archivo. Revisa la app y sus permisos.',502);return result;}
export async function queueSlackFiles(ids:string[]){for(const id of ids)await database().prepare('INSERT OR IGNORE INTO jac_slack_files (id,created_at) VALUES (?,?)').bind(id,now()).run();}
export async function importSlackFiles(){
 const keys=await pushCredentials();if(!keys.slack){await dispatchPush();return;}
 const slack=keys.slack;
 const rows=(await database().prepare("SELECT id FROM jac_slack_files WHERE status='pending' OR (status='processing' AND started_at<?) ORDER BY created_at LIMIT 5").bind(new Date(Date.now()-60000).toISOString()).all<{id:string}>()).results;
 await Promise.all(rows.map(async ({id})=>{
  const claimed=await database().prepare("UPDATE jac_slack_files SET status='processing',started_at=? WHERE id=? AND (status='pending' OR (status='processing' AND started_at<?))").bind(now(),id,new Date(Date.now()-60000).toISOString()).run();if(claimed.meta.changes!==1)return;
  try{
   const exists=await database().prepare('SELECT id FROM jac_notices WHERE source=?').bind('slack:'+id).first<{id:string}>();
   if(exists){await queuePush(exists.id);await database().prepare("UPDATE jac_slack_files SET status='ready',error='' WHERE id=?").bind(id).run();return;}
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
   await database().batch([database().prepare("INSERT OR IGNORE INTO jac_notices (id,kind,title,file_key,filename,size,source,created_at) VALUES (?,'itinerary',?,?,?,?,?,?)").bind(nid,filename.replace(/\.pdf$/i,''),fileKey,filename,size,'slack:'+id,stamp),database().prepare("INSERT OR IGNORE INTO jac_notice_recipients (id,notice_id,user_id) SELECT n.id||'|'||u.id,n.id,u.id FROM jac_notices n CROSS JOIN payroll_users u WHERE n.source=? AND u.active=1 AND u.password_hash<>''").bind('slack:'+id),database().prepare("UPDATE jac_slack_files SET status='ready',error='' WHERE id=?").bind(id)]);
   const saved=await database().prepare('SELECT id FROM jac_notices WHERE source=?').bind('slack:'+id).first<{id:string}>();if(saved)await queuePush(saved.id);
  }catch(e){await database().prepare("UPDATE jac_slack_files SET status='failed',error=? WHERE id=?").bind(e instanceof NoticeFailure?e.message:'No se pudo importar el PDF. Revisa la conexión y reintenta.',id).run();}
 }));
 await dispatchPush();
}
export async function retryImports(){await database().prepare("UPDATE jac_slack_files SET status='pending',error='' WHERE status='failed'").run();}
export async function itineraryPdf(u:AccessUser,id:string){const item=await allowedNotice(u,id);if(item.kind!=='itinerary'||!item.file_key)throw new NoticeFailure('Este aviso no tiene un PDF.',404);const object=await env.BUCKET.get(item.file_key);if(!object)throw new NoticeFailure('El PDF todavía no está disponible.',404);return {item,object};}
