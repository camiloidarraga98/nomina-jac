import {env} from 'cloudflare:workers';
import {createHmac,randomBytes} from 'node:crypto';
import {database} from '@/db/raw';
import {generateBirthdayPhoto,normalizeBirthdayUpload} from './fans-birthday-image';

type FanEnv={OPENAI_API_KEY?:string;JAC_FANS_ENABLED?:string;JAC_FANS_TURNSTILE_SITE_KEY?:string;JAC_FANS_TURNSTILE_SECRET?:string;PAYROLL_AUTH_KEY?:string;BUCKET:R2Bucket};
type Job={id:string;owner_hash:string;ip_hash:string;payload_hash:string;status:string;source_key:string;source_mime:string;result_key:string;claim:string;started_at:string;message:string;created_at:string;expires_at:string;updated_at:string};
const settings=()=>env as unknown as FanEnv;
const HOUR=3600_000,DAY=24*HOUR;
export const BIRTHDAY_LIMITS={photoBytes:8*1024*1024,retentionHours:24,metadataDays:7,dailyGlobal:25,dailyIP:3,dailyBrowser:2,waiting:10} as const;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COOKIE=/^[A-Za-z0-9_-]{43}$/;
const terminal=new Set(['ready','failed','uncertain','cancelled']);
const privateHeaders={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Cross-Origin-Resource-Policy':'same-origin','X-Robots-Tag':'noindex, nofollow, noarchive'};
class BirthdayFailure extends Error {constructor(message:string,readonly status=400){super(message);}}
const now=()=>new Date().toISOString();
const enabled=()=>{const e=settings();return e.JAC_FANS_ENABLED==='1'&&!!e.OPENAI_API_KEY&&!!e.JAC_FANS_TURNSTILE_SITE_KEY&&!!e.JAC_FANS_TURNSTILE_SECRET&&!!e.PAYROLL_AUTH_KEY&&e.PAYROLL_AUTH_KEY.length>=32;};
const digest=(purpose:string,value:string)=>createHmac('sha256',settings().PAYROLL_AUTH_KEY??'').update('jac-birthday-v1:'+purpose+'\0'+value).digest('hex');
const reply=(value:unknown,status=200,extra:Record<string,string>={})=>Response.json(value,{status,headers:{...privateHeaders,...extra}});
const row=(id:string)=>database().prepare('SELECT * FROM jac_fan_birthday_jobs WHERE id=?').bind(id).first<Job>();

function browser(req:Request,create=false){
 const local=/^(localhost|127\.0\.0\.1)$/.test(new URL(req.url).hostname),name=local?'jac_fan':'__Host-jac_fan';
 const entries=(req.headers.get('cookie')??'').split(';').map(x=>x.trim()).filter(x=>x.startsWith(name+'='));
 const old=entries.length===1?entries[0].slice(name.length+1):'',valid=COOKIE.test(old),token=valid?old:create?randomBytes(32).toString('base64url'):'';
 return {owner:token?digest('browser',token):'',cookie:token?`${name}=${token}; Path=/; HttpOnly; ${local?'':'Secure; '}SameSite=Strict; Max-Age=86400`:''};
}
function writeOrigin(req:Request){
 if(req.headers.get('origin')!==new URL(req.url).origin||req.headers.get('sec-fetch-site')==='cross-site')throw new BirthdayFailure('Abre esta experiencia desde su página original.',403);
}
function requireID(id:string|null){if(!id||!UUID.test(id))throw new BirthdayFailure('Esta foto no está disponible.',404);return id;}
async function ownJob(id:string,owner:string){
 if(!owner)throw new BirthdayFailure('Vuelve a abrir la experiencia en este navegador.',403);
 const job=await row(id);if(!job||job.owner_hash!==owner)throw new BirthdayFailure('Esta foto no está disponible en este navegador.',404);
 if(job.expires_at<=now())throw new BirthdayFailure('Esta foto ya venció. Las fotos se conservan durante 24 horas.',410);
 return job;
}
function publicJob(job:Job){return {id:job.id,status:job.status==='uploading'?'queued':job.status,message:job.message,expiresAt:job.expires_at};}
async function boundedForm(req:Request){
 const type=req.headers.get('content-type')??'';
 if(!/^multipart\/form-data;\s*boundary=/i.test(type))throw new BirthdayFailure('Selecciona una foto para continuar.');
 const limit=BIRTHDAY_LIMITS.photoBytes+64*1024;
 if(Number(req.headers.get('content-length')??0)>limit)throw new BirthdayFailure('La foto debe pesar como máximo 8 MB.',413);
 if(!req.body)throw new BirthdayFailure('No recibimos la foto.');
 const reader=req.body.getReader(),parts:Uint8Array[]=[];let length=0;
 for(;;){const next=await reader.read();if(next.done)break;length+=next.value.length;if(length>limit){await reader.cancel();throw new BirthdayFailure('La foto debe pesar como máximo 8 MB.',413);}parts.push(next.value);}
 const bytes=new Uint8Array(length);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
 try{return await new Request(req.url,{method:'POST',headers:{'Content-Type':type},body:bytes}).formData();}catch{throw new BirthdayFailure('No pudimos leer la foto. Selecciónala de nuevo.');}
}
function imageMime(bytes:Uint8Array){
 if(bytes.length>8&&[137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v))return 'image/png';
 if(bytes.length>3&&bytes[0]===255&&bytes[1]===216&&bytes[2]===255)return 'image/jpeg';
 if(bytes.length>12&&new TextDecoder().decode(bytes.subarray(0,4))==='RIFF'&&new TextDecoder().decode(bytes.subarray(8,12))==='WEBP')return 'image/webp';
 throw new BirthdayFailure('Usa una foto válida en JPG, PNG o WebP.',415);
}
async function verifyHuman(req:Request,token:FormDataEntryValue|null){
 if(typeof token!=='string'||token.length<1||token.length>2048)throw new BirthdayFailure('Completa la verificación y vuelve a intentarlo.',403);
 let response:Response;
 try{response=await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify',{method:'POST',redirect:'manual',signal:AbortSignal.timeout(12_000),body:new URLSearchParams({secret:settings().JAC_FANS_TURNSTILE_SECRET!,response:token})});}catch{throw new BirthdayFailure('No pudimos completar la verificación. Inténtalo de nuevo.',503);}
 if(!response.ok)throw new BirthdayFailure('La verificación no está disponible. Inténtalo de nuevo.',503);
 let data:{success?:boolean;hostname?:string;action?:string};try{data=await response.json();}catch{throw new BirthdayFailure('La verificación no está disponible. Inténtalo de nuevo.',503);}
 if(data.success!==true||data.hostname!==new URL(req.url).hostname||data.action!=='birthday-photo')throw new BirthdayFailure('La verificación venció. Complétala otra vez.',403);
}
async function removeAsset(key:string){if(key)await settings().BUCKET.delete(key);}
async function purgeAssets(job:Job,includeResult=true){
 const keys=[['source_key',job.source_key],...(includeResult?[['result_key',job.result_key]]:[])] as [string,string][];
  for(const [column,key] of keys){if(!key)continue;try{await removeAsset(key);await database().prepare(`UPDATE jac_fan_birthday_jobs SET ${column}='' WHERE id=? AND ${column}=? AND claim='' AND status IN ('ready','failed','uncertain','cancelled')`).bind(job.id,key).run();}catch{/* Keep the key so the next maintenance pass can finish private cleanup. */}}
}

async function createJob(req:Request,owner:string){
 if(!owner)throw new BirthdayFailure('Abre primero la experiencia en este navegador.',403);
 if(!enabled())throw new BirthdayFailure('Estamos preparando la experiencia. Vuelve pronto.',503);
 const form=await boundedForm(req),id=requireID(typeof form.get('id')==='string'?String(form.get('id')):null),photo=form.get('photo');
 if(form.getAll('id').length!==1||form.getAll('photo').length!==1||!(photo instanceof File)||photo.size===0)throw new BirthdayFailure('Selecciona una foto para continuar.');
 if(photo.size>BIRTHDAY_LIMITS.photoBytes)throw new BirthdayFailure('La foto debe pesar como máximo 8 MB.',413);
 if(form.get('consent')!=='true'||form.get('adult')!=='true')throw new BirthdayFailure('Confirma que eres mayor de edad y que tienes permiso para usar la foto.');
 const raw=new Uint8Array(await photo.arrayBuffer()),mime=imageMime(raw),hash=createHmac('sha256',settings().PAYROLL_AUTH_KEY!).update('jac-birthday-v1:photo\0').update(raw).update(mime).digest('hex'),prior=await row(id);
 if(prior){if(prior.owner_hash!==owner)throw new BirthdayFailure('Este intento no está disponible.',404);if(prior.payload_hash!==hash)throw new BirthdayFailure('Este intento corresponde a otra foto. Inicia una creación nueva.',409);return publicJob(await ownJob(id,owner));}
 const address=req.headers.get('cf-connecting-ip');if(!address||address.length>100)throw new BirthdayFailure('No pudimos verificar la conexión. Inténtalo desde la página original.',403);
 const ip=digest('ip',address),stamp=now(),day=new Date(Date.now()-5*HOUR).toISOString().slice(0,10)+'T05:00:00.000Z',expires=new Date(Date.now()+DAY).toISOString(),key='fans-birthday/source/'+id,uploadClaim=randomBytes(24).toString('hex');
 // Reject exhausted budgets before verification and image transformations.
 // The INSERT below still performs the authoritative atomic reservation.
 const budget=await database().prepare(`SELECT
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE created_at>=?) AS total,
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE ip_hash=? AND created_at>=?) AS network,
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE owner_hash=? AND created_at>=?) AS browser,
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE status IN ('uploading','queued','processing') AND expires_at>?) AS waiting`).bind(day,ip,day,owner,day,stamp).first<{total:number;network:number;browser:number;waiting:number}>();
 if(!budget||budget.total>=BIRTHDAY_LIMITS.dailyGlobal||budget.network>=BIRTHDAY_LIMITS.dailyIP||budget.browser>=BIRTHDAY_LIMITS.dailyBrowser||budget.waiting>=BIRTHDAY_LIMITS.waiting)throw new BirthdayFailure('Por hoy alcanzamos el límite de creaciones o hay varias fotos en espera. Inténtalo más tarde.',429);
 await verifyHuman(req,form.get('turnstileToken'));
 let normalized:{bytes:Uint8Array;mimeType:string};
 try{normalized=await normalizeBirthdayUpload(raw,mime);}catch(e){if(e&&typeof e==='object'&&'status' in e&&e.status===503)throw new BirthdayFailure('No pudimos preparar tu foto en este momento. Inténtalo más tarde.',503);throw new BirthdayFailure('No pudimos preparar esa foto. Prueba con una foto válida en JPG, PNG o WebP.',415);}
 if(!normalized.bytes.length||normalized.bytes.length>3*1024*1024||!['image/jpeg','image/png','image/webp'].includes(normalized.mimeType))throw new BirthdayFailure('No pudimos preparar esa foto. Prueba con otra.',415);
 const reserved=await database().prepare(`INSERT INTO jac_fan_birthday_jobs(id,owner_hash,ip_hash,payload_hash,status,source_key,source_mime,claim,started_at,created_at,expires_at,updated_at)
 SELECT ?,?,?,?,'uploading',?,?,?,?,?,?,? WHERE
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE created_at>=?)<? AND
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE ip_hash=? AND created_at>=?)<? AND
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE owner_hash=? AND created_at>=?)<? AND
 (SELECT count(*) FROM jac_fan_birthday_jobs WHERE status IN ('uploading','queued','processing') AND expires_at>?)<?
 ON CONFLICT(id) DO NOTHING`).bind(id,owner,ip,hash,key,normalized.mimeType,uploadClaim,stamp,stamp,expires,stamp,day,BIRTHDAY_LIMITS.dailyGlobal,ip,day,BIRTHDAY_LIMITS.dailyIP,owner,day,BIRTHDAY_LIMITS.dailyBrowser,stamp,BIRTHDAY_LIMITS.waiting).run();
 if(reserved.meta.changes!==1){const existing=await row(id);if(existing&&existing.owner_hash===owner&&existing.payload_hash===hash)return publicJob(await ownJob(id,owner));throw new BirthdayFailure('Por hoy alcanzamos el límite de creaciones o hay varias fotos en espera. Inténtalo más tarde.',429);}
 try{
  await settings().BUCKET.put(key,normalized.bytes,{httpMetadata:{contentType:normalized.mimeType}});
  const saved=await database().prepare("UPDATE jac_fan_birthday_jobs SET status='queued',claim='',updated_at=? WHERE id=? AND owner_hash=? AND status='uploading' AND claim=? AND expires_at>?").bind(now(),id,owner,uploadClaim,now()).run();
  if(saved.meta.changes!==1){await removeAsset(key);throw new BirthdayFailure('Se canceló este intento antes de terminar la subida.',409);}
 }catch(e){
  await database().prepare("UPDATE jac_fan_birthday_jobs SET status='failed',message=?,updated_at=? WHERE id=? AND status='uploading'").bind('No pudimos guardar la foto. Puedes iniciar una creación nueva.',now(),id).run();
  if(e instanceof BirthdayFailure)throw e;throw new BirthdayFailure('No pudimos guardar la foto. Inténtalo de nuevo.',502);
 }finally{
  // A cancelled PUT may still finish and even lose its acknowledgement. Keep
  // both deterministic object keys until that write has settled, then purge.
  await database().prepare("UPDATE jac_fan_birthday_jobs SET claim='' WHERE id=? AND claim=?").bind(id,uploadClaim).run();
  const latest=await row(id).catch(()=>null);if(latest&&terminal.has(latest.status))await purgeAssets(latest);
 }
 return publicJob((await row(id))!);
}

export async function handleBirthdayApi(req:Request):Promise<Response>{
 try{
  const url=new URL(req.url),identity=browser(req,req.method==='GET'&&!url.searchParams.has('id'));
  if(req.method==='GET'&&!url.searchParams.has('id')){
   const active=await database().prepare("SELECT id FROM jac_fan_birthday_jobs WHERE owner_hash=? AND expires_at>? AND status<>'cancelled' ORDER BY created_at DESC,id DESC LIMIT 1").bind(identity.owner,now()).first<{id:string}>();
   return reply({enabled:enabled(),turnstileSiteKey:enabled()?settings().JAC_FANS_TURNSTILE_SITE_KEY!:'',retentionHours:BIRTHDAY_LIMITS.retentionHours,activeJobId:active?.id??''},200,identity.cookie?{'Set-Cookie':identity.cookie}:{});
  }
  if(req.method==='POST'){writeOrigin(req);return reply({job:await createJob(req,identity.owner)},202,identity.cookie?{'Set-Cookie':identity.cookie}:{});}
  if(req.method!=='GET'&&req.method!=='DELETE')return reply({error:'Método no disponible.'},405,{Allow:'GET, POST, DELETE'});
  if(req.method==='DELETE')writeOrigin(req);
  const id=requireID(url.searchParams.get('id')),job=await ownJob(id,identity.owner);
  if(req.method==='DELETE'){
   // Keep an in-flight lease until its processor exits: cancellation prevents
   // publication, but cannot instantly stop a provider already generating.
   await database().prepare("UPDATE jac_fan_birthday_jobs SET status='cancelled',message=?,updated_at=? WHERE id=? AND owner_hash=?").bind('Eliminaste esta foto.',now(),id,identity.owner).run();
   await purgeAssets({...job,status:'cancelled'});return reply({job:publicJob((await row(id))!)});
  }
  if(!url.searchParams.has('image'))return reply({job:publicJob(job)});
  if(job.status!=='ready'||!job.result_key)throw new BirthdayFailure('Tu foto todavía no está lista para descargar.',409);
  const image=await settings().BUCKET.get(job.result_key);if(!image)throw new BirthdayFailure('Esta foto ya no está disponible.',410);
  const live=await ownJob(id,identity.owner);if(live.status!=='ready'||live.result_key!==job.result_key){await image.body.cancel().catch(()=>{});throw new BirthdayFailure('Esta foto ya no está disponible.',410);}
  return new Response(image.body,{headers:{...privateHeaders,'Content-Type':'image/png','Content-Disposition':`${url.searchParams.has('download')?'attachment':'inline'}; filename="Mi-cumpleanos-con-el-Rey.png"`}});
 }catch(e){return reply({error:e instanceof BirthdayFailure?e.message:'No pudimos completar la operación. Inténtalo de nuevo.'},e instanceof BirthdayFailure?e.status:502);}
}

async function cleanupBirthdayJobs(){
 const stamp=now(),stale=new Date(Date.now()-10*60_000).toISOString(),old=new Date(Date.now()-BIRTHDAY_LIMITS.metadataDays*DAY).toISOString(),db=database();
 await db.prepare("UPDATE jac_fan_birthday_jobs SET status='uncertain',claim='',message=?,updated_at=? WHERE status='processing' AND started_at<?").bind('La generación no pudo confirmarse. No la repetiremos automáticamente.',stamp,stale).run();
 await db.prepare("UPDATE jac_fan_birthday_jobs SET claim='' WHERE claim<>'' AND started_at<?").bind(stale).run();
 await db.prepare("UPDATE jac_fan_birthday_jobs SET status='failed',claim='',message=?,updated_at=? WHERE status='uploading' AND created_at<?").bind('La subida no se completó. Puedes iniciar una creación nueva.',stamp,stale).run();
 await db.prepare("UPDATE jac_fan_birthday_jobs SET status='cancelled',claim='',message=?,updated_at=? WHERE expires_at<=? AND status IN ('uploading','queued','processing')").bind('Esta foto ya venció.',stamp,stamp).run();
 const jobs=(await db.prepare("SELECT * FROM jac_fan_birthday_jobs WHERE (source_key<>'' OR result_key<>'') AND (expires_at<=? OR status IN ('failed','uncertain','cancelled') OR (status='ready' AND source_key<>'')) ORDER BY expires_at,id LIMIT 20").bind(stamp).all<Job>()).results;
 for(const job of jobs)await purgeAssets(job,job.status!=='ready'||job.expires_at<=stamp);
 await db.prepare("DELETE FROM jac_fan_birthday_jobs WHERE created_at<? AND source_key='' AND result_key='' AND status IN ('ready','failed','uncertain','cancelled')").bind(old).run();
}

// Called by the minute cron, whose lifetime permits long image generations.
// There is never an automatic retry of a call that may already have been billed.
export async function processBirthdayJobs():Promise<void>{
 await cleanupBirthdayJobs();if(!enabled())return;
 const db=database(),stamp=now(),job=await db.prepare("SELECT * FROM jac_fan_birthday_jobs WHERE status='queued' AND expires_at>? ORDER BY created_at,id LIMIT 1").bind(stamp).first<Job>();if(!job)return;
 const claim=randomBytes(24).toString('hex'),resultKey='fans-birthday/result/'+job.id+'.png';
 const claimed=await db.prepare("UPDATE jac_fan_birthday_jobs SET status='processing',claim=?,started_at=?,result_key=?,updated_at=? WHERE id=? AND status='queued' AND expires_at>? AND NOT EXISTS(SELECT 1 FROM jac_fan_birthday_jobs WHERE claim<>'' AND started_at>?)").bind(claim,stamp,resultKey,stamp,job.id,stamp,new Date(Date.now()-10*60_000).toISOString()).run();if(claimed.meta.changes!==1)return;
 const stillOwned=async()=>{const live=await row(job.id);return live?.status==='processing'&&live.claim===claim&&live.expires_at>now();};
 try{
  const source=await settings().BUCKET.get(job.source_key);if(!source)throw Object.assign(new Error('Source missing'),{paidAttempt:false});
  const bytes=new Uint8Array(await source.arrayBuffer());if(!bytes.length||bytes.length>3*1024*1024)throw Object.assign(new Error('Invalid private source'),{paidAttempt:false});
  if(!await stillOwned())return;
  const output=await generateBirthdayPhoto(bytes,job.source_mime);
  if(!await stillOwned())return;
  if(!output.length||output.length>16*1024*1024)throw new Error('Invalid generated output');
  await settings().BUCKET.put(resultKey,output,{httpMetadata:{contentType:'image/png'}});
  const saved=await db.prepare("UPDATE jac_fan_birthday_jobs SET status='ready',claim='',message='',updated_at=? WHERE id=? AND status='processing' AND claim=? AND expires_at>?").bind(now(),job.id,claim,now()).run();
  if(saved.meta.changes!==1)await removeAsset(resultKey);
 }catch(e){
  // A lost acknowledgement after the final CAS must not destroy a ready image.
  const latest=await row(job.id).catch(()=>null);
  if(latest?.status!=='ready')await db.prepare("UPDATE jac_fan_birthday_jobs SET status=?,claim='',message=?,updated_at=? WHERE id=? AND status='processing' AND claim=?").bind(e&&typeof e==='object'&&'paidAttempt' in e&&e.paidAttempt===false?'failed':'uncertain','No pudimos confirmar tu foto. Este intento no se repetirá automáticamente.',now(),job.id,claim).run();
 }finally{
  await db.prepare("UPDATE jac_fan_birthday_jobs SET claim='' WHERE id=? AND claim=?").bind(job.id,claim).run();
  const latest=await row(job.id).catch(()=>null);if(latest&&terminal.has(latest.status))await purgeAssets(latest,latest.status!=='ready');
 }
}
