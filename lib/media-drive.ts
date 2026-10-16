import {database} from '@/db/raw';
import {mailKey} from './payroll-mail';
import {encryptMail,decryptMail} from './payroll-mail-core';
import {calendarGooglePost,CalendarFailure} from './calendar';
import {sessionToken,tokenHash} from './payroll-auth-crypto';
import {canReadMedia,canUploadMedia,canConnectMedia,MediaFailure,MEDIA_ROOT_ID,MEDIA_FOLDER_MIME,MEDIA_SCOPE,MEDIA_CHUNK_SIZE,MEDIA_DIRECT_CHUNK_SIZE,MEDIA_THUMBNAIL_MAX_BYTES,validMediaID,validMediaRequestID,mediaFolderName,mediaUploadInput,mediaKind,mediaSignature,mediaRange,mediaItemOrder,mediaThumbnailURL,type MediaItem} from './media-core';
import {sectionSql,type AccessUser} from './payroll-permissions';

export type MediaConnection={id:string;credentials:string;email:string;version:number};
export type MediaSecret={clientId:string;clientSecret:string;refreshToken:string;scopes:string[]};
export type MediaGuard={sql:string;bindings:(string|number)[];actorID:string};
type Context={guard:MediaGuard;config:MediaConnection;access:string};
type DriveFile={id:string;name:string;mimeType:string;parents?:string[];trashed?:boolean;size?:string;createdTime?:string;modifiedTime?:string;thumbnailLink?:string;capabilities?:{canAddChildren?:boolean;canDownload?:boolean};appProperties?:Record<string,string>;shortcutDetails?:unknown};
type Operation={id:string;actor_id:string;parent_id:string;payload_hash:string;kind:string;drive_id:string;name:string;mime_type:string;size:number;offset:number;status:string;session_payload:string;connection_version:number;claim:string;claim_at:string;expires_at:string};
const fields='id,name,mimeType,parents,trashed,size,createdTime,modifiedTime,thumbnailLink,capabilities(canAddChildren,canDownload),shortcutDetails,appProperties';
const safeID=(id:unknown)=>{if(!validMediaID(id))throw new MediaFailure('El archivo o carpeta no es válido.');return id;};
export function mediaStoredGuard(sessionID:string,actorID:string,mode:'read'|'upload'|'connect'='read'):MediaGuard {
 const role=mode==='upload'?`(${sectionSql('mu','media')} AND ${sectionSql('mu','mediaUpload')})`:mode==='connect'?"mu.media_only=0 AND mu.itineraries_only=0 AND mu.owner=1 AND mu.email='camilo@mac2you.co'":sectionSql('mu','media');
 return {actorID,sql:`EXISTS(SELECT 1 FROM payroll_sessions ms JOIN payroll_users mu ON mu.id=ms.user_id AND mu.version=ms.user_version WHERE ms.id=? AND mu.id=? AND (ms.persistent=1 OR ms.expires_at>?) AND mu.active=1 AND mu.password_hash<>'' AND ${role})`,bindings:[sessionID,actorID,new Date().toISOString()]};
}
export function mediaGuard(req:Request,user:AccessUser,mode:'read'|'upload'|'connect'='read') {if(!(mode==='upload'?canUploadMedia(user):mode==='connect'?canConnectMedia(user):canReadMedia(user)))throw new MediaFailure('Tu cuenta no tiene permiso para esta operación de Fotografía.',403);const secure=!/^(localhost|127\.0\.0\.1)$/.test(new URL(req.url).hostname),token=sessionToken(req.headers.get('cookie')||'',secure);if(!/^[A-Za-z0-9_-]{43}$/.test(token))throw new MediaFailure('Inicia sesión de nuevo.',401);return mediaStoredGuard(tokenHash(token),user.id,mode);}
export async function mediaGuardActive(g:MediaGuard){return !!await database().prepare('SELECT 1 WHERE '+g.sql).bind(...g.bindings).first();}
export async function mediaConfig(){return database().prepare('SELECT id,credentials,email,version FROM jac_media_connection WHERE id=?').bind('jac').first<MediaConnection>();}
export async function ensureMediaConfig(){await database().prepare('INSERT OR IGNORE INTO jac_media_connection(id,updated_at) VALUES (?,?)').bind('jac',new Date().toISOString()).run();return (await mediaConfig())!;}
export async function storeMediaConnection(secret:MediaSecret,version:number,g:MediaGuard){const r=await database().prepare(`UPDATE jac_media_connection SET credentials=?,email=?,version=version+1,updated_at=? WHERE id='jac' AND version=? AND ${g.sql}`).bind(await encryptMail(secret,mailKey()),'jacmusicestudios@gmail.com',new Date().toISOString(),version,...g.bindings).run();if(r.meta.changes!==1)throw new MediaFailure('La sesión o la conexión cambió. Vuelve a conectar Drive.',409);}
async function live(c:Context){const r2=await database().prepare("SELECT enabled FROM jac_media_r2_connection WHERE id='jac'").first<{enabled:number}>();const row=await mediaConfig();if(r2?.enabled===1||!row||row.version!==c.config.version||row.credentials!==c.config.credentials||!await mediaGuardActive(c.guard))throw new MediaFailure('La sesión, los permisos o la conexión cambiaron. Actualiza Fotografía.',403);}
let accessCache:{credentials:string;version:number;access:string;until:number}|undefined;
export async function mediaContext(g:MediaGuard):Promise<Context>{if((await database().prepare("SELECT enabled FROM jac_media_r2_connection WHERE id='jac'").first<{enabled:number}>())?.enabled===1)throw new MediaFailure('Fotografía utiliza exclusivamente el archivo nuevo de R2.',410);if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión o tus permisos cambiaron.',403);const config=await mediaConfig();if(!config?.credentials||config.email!=='jacmusicestudios@gmail.com')throw new MediaFailure('Camilo debe conectar la carpeta de Google Drive desde Fotografía.',409);if(accessCache?.credentials===config.credentials&&accessCache.version===config.version&&accessCache.until>Date.now()){const c={guard:g,config,access:accessCache.access};await live(c);return c;}const secret=await decryptMail<MediaSecret>(config.credentials,mailKey());if(!secret.scopes.includes(MEDIA_SCOPE))throw new MediaFailure('Vuelve a autorizar el acceso a la carpeta de fotografías.',409);let result:Record<string,unknown>;try{result=await calendarGooglePost({client_id:secret.clientId,client_secret:secret.clientSecret,refresh_token:secret.refreshToken,grant_type:'refresh_token'});}catch(e){if(e instanceof CalendarFailure&&['invalid_grant','access_denied'].includes(e.googleError||''))throw new MediaFailure('Google retiró la autorización de Fotografía. Camilo debe volver a conectar Drive.',403);throw new MediaFailure('No pudimos renovar el acceso a Drive. Camilo puede volver a conectarlo.',502);}if(typeof result.access_token!=='string')throw new MediaFailure('Google no confirmó el acceso a Drive.',502);const c={guard:g,config,access:result.access_token};await live(c);const lifetime=typeof result.expires_in==='number'?Math.min(3600,result.expires_in):0;if(lifetime>120)accessCache={credentials:config.credentials,version:config.version,access:c.access,until:Date.now()+(lifetime-60)*1000};return c;}
function googleURL(url:string){const u=new URL(url);if(u.origin!=='https://www.googleapis.com'||u.username||u.password||u.hash||!/^\/(?:upload\/)?drive\/v3\//.test(u.pathname))throw new MediaFailure('Google devolvió una dirección de archivo inesperada.',502);return u.toString();}
async function request(c:Context,url:string,options:RequestInit={},resume=false){await live(c);let r:Response;const controller=new AbortController(),deadline=setTimeout(()=>controller.abort(),60000);try{r=await fetch(googleURL(url),{...options,headers:{...Object.fromEntries(new Headers(options.headers)),Authorization:'Bearer '+c.access},redirect:'manual',signal:controller.signal});}catch(e){if(e instanceof MediaFailure)throw e;throw new MediaFailure('La conexión con Drive se interrumpió. Puedes reintentar sin duplicar el archivo.',502);}finally{clearTimeout(deadline);}try{await live(c);}catch(e){await r.body?.cancel().catch(()=>{});throw e;}if(r.status>=300&&r.status<400&&!(resume&&r.status===308))throw new MediaFailure('Google devolvió una redirección inesperada.',502);if(r.status===401)accessCache=undefined;return r;}
async function checked(r:Response){if(r.ok||r.status===308)return;if(r.status===416){await r.body?.cancel().catch(()=>{});throw new MediaFailure('El rango solicitado no está disponible.',416);}const body=await r.json().catch(()=>({})) as {error?:{errors?:{reason?:string}[]}};const reasons=Array.isArray(body?.error?.errors)?body.error.errors.map(e=>e?.reason):[];if(reasons.some(v=>['rateLimitExceeded','userRateLimitExceeded','dailyLimitExceeded','storageQuotaExceeded'].includes(v||'')))throw new MediaFailure('Google alcanzó un límite temporal o de almacenamiento. Conserva el archivo y vuelve a intentar.',503);throw new MediaFailure(r.status===404||r.status===410?'El archivo o la carpeta ya no está disponible.':r.status===403?'Google no permite acceder a esta carpeta o archivo. Revisa el acceso de la cuenta de JAC.':r.status===429?'Google limitó temporalmente las consultas. Intenta de nuevo en un momento.':r.status===401?'Camilo debe volver a conectar Google Drive.':'Google no confirmó la operación. Conserva el archivo y vuelve a intentar.',r.status===404||r.status===410?404:r.status===401||r.status===403?403:502);}
async function json<T>(c:Context,url:string,options:RequestInit={}):Promise<T>{const r=await request(c,url,options);await checked(r);const data=await r.json() as T;await live(c);return data;}
async function metadata(c:Context,id:string){const f=await json<DriveFile>(c,'https://www.googleapis.com/drive/v3/files/'+safeID(id)+'?'+new URLSearchParams({fields,supportsAllDrives:'true'}));if(f.id!==id||f.trashed||f.shortcutDetails||!mediaKind(f.mimeType)||typeof f.name!=='string')throw new MediaFailure('El archivo o carpeta no está disponible en Fotografía.',404);return f;}
// Some shared files omit parents in files.get, although files.list returns them.
// A server-observed location only tells us which folder to query again. It is
// never permission: the fresh listing and full ancestry must both confirm it.
async function rememberLocations(c:Context,folder:string,items:MediaItem[]){
 if(!items.length)return;
 await live(c);
 await database().prepare(`INSERT INTO jac_media_locations(file_id,parent_id,connection_version)
 SELECT json_extract(mi.value,'$.id'),?,? FROM json_each(?) mi WHERE ${c.guard.sql}
 AND EXISTS(SELECT 1 FROM jac_media_connection WHERE id='jac' AND version=? AND credentials=?)
 ON CONFLICT(file_id) DO UPDATE SET parent_id=excluded.parent_id,connection_version=excluded.connection_version
 WHERE excluded.connection_version>=jac_media_locations.connection_version
 AND (excluded.parent_id<>jac_media_locations.parent_id OR excluded.connection_version<>jac_media_locations.connection_version)`)
 .bind(folder,c.config.version,JSON.stringify(items.map(i=>({id:i.id}))),...c.guard.bindings,c.config.version,c.config.credentials).run();
 await live(c);
}
async function listedParent(c:Context,file:DriveFile):Promise<string[]|undefined>{
 const hint=await database().prepare('SELECT parent_id FROM jac_media_locations WHERE file_id=? AND connection_version=?').bind(file.id,c.config.version).first<{parent_id:string}>();
 await live(c);if(!hint||!validMediaID(hint.parent_id))return undefined;
 const literal=file.name.replace(/\\/g,'\\\\').replace(/'/g,"\\'");
 let pageToken:string|undefined;
 for(let page=0;page<10;page++){
  const data=await json<{files?:DriveFile[];nextPageToken?:string}>(c,'https://www.googleapis.com/drive/v3/files?'+new URLSearchParams({q:"'"+hint.parent_id+"' in parents and name = '"+literal+"' and trashed=false",fields:'nextPageToken,files(id,name,mimeType,parents,trashed,shortcutDetails)',pageSize:'100',supportsAllDrives:'true',includeItemsFromAllDrives:'true',...(pageToken?{pageToken}:{})}));
  const match=data.files?.find(candidate=>candidate.id===file.id);
  if(match)return match.name===file.name&&match.mimeType===file.mimeType&&!match.trashed&&!match.shortcutDetails&&Array.isArray(match.parents)&&match.parents.length===1&&match.parents[0]===hint.parent_id?match.parents:undefined;
  if(!data.nextPageToken)return undefined;
  if(typeof data.nextPageToken!=='string'||data.nextPageToken.length>4096)throw new MediaFailure('Google no confirmó la ubicación del archivo.',502);
  pageToken=data.nextPageToken;
 }
 return undefined;
}
// Check the current parent chain on every read/write, including files moved in Drive.
// Never trust a client-supplied parent, shortcut or a previously cached membership.
async function ancestry(c:Context,id:string){
 const chain:DriveFile[]=[],seen=new Set<string>();let next=safeID(id),reason='depth_limit',parentCount=0;
 for(let depth=0;depth<24;depth++){
  if(seen.has(next)){reason='cycle';break;}seen.add(next);
  const f=await metadata(c,next);chain.unshift(f);if(next===MEDIA_ROOT_ID)return chain;
  if(f.parents==null||Array.isArray(f.parents)&&f.parents.length===0)f.parents=await listedParent(c,f);
  parentCount=Array.isArray(f.parents)?f.parents.length:0;
  if(parentCount!==1){reason=parentCount?'multiple_parents':'missing_parent';break;}next=f.parents![0];
 }
 console.error('Media ancestry rejected',{reason,depth:chain.length,kind:mediaKind(chain.at(-1)?.mimeType||''),parentCount});
 throw new MediaFailure('Ese archivo o carpeta no pertenece a Fotografía JAC.',403);
}
async function parent(c:Context,id:string){const chain=await ancestry(c,id),f=chain.at(-1)!;if(f.mimeType!==MEDIA_FOLDER_MIME)throw new MediaFailure('Selecciona una carpeta.');if(f.capabilities?.canAddChildren!==true)throw new MediaFailure('La cuenta de Google de JAC necesita permiso para añadir contenido a esta carpeta.',403);return chain;}
const item=(f:DriveFile):MediaItem=>({id:f.id,name:f.name,mimeType:f.mimeType,kind:mediaKind(f.mimeType)!,size:Number(f.size||0),createdAt:f.createdTime||'',modifiedAt:f.modifiedTime||'',thumbnailAvailable:!!f.thumbnailLink});
export async function mediaFeed(g:MediaGuard,user:AccessUser,folder=MEDIA_ROOT_ID,pageToken?:string){safeID(folder);if(pageToken&&(pageToken.length>4096||/[\u0000-\u0020\u007f]/.test(pageToken)))throw new MediaFailure('La página solicitada no es válida.');const root={id:MEDIA_ROOT_ID,name:'Fotografía JAC'},flags={canRead:canReadMedia(user),canUpload:canUploadMedia(user),canConnect:canConnectMedia(user)};if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión cambió.',403);const cfg=await mediaConfig();if(!cfg?.credentials)return {connected:false,...flags,root,folder:root,breadcrumbs:[root],items:[]};const c=await mediaContext(g),chain=await ancestry(c,folder);if(chain.at(-1)!.mimeType!==MEDIA_FOLDER_MIME)throw new MediaFailure('Selecciona una carpeta.');const q="'"+folder+"' in parents and trashed=false and (mimeType='"+MEDIA_FOLDER_MIME+"' or mimeType contains 'image/' or mimeType contains 'video/')",data=await json<{files?:DriveFile[];nextPageToken?:string}>(c,'https://www.googleapis.com/drive/v3/files?'+new URLSearchParams({q,fields:'nextPageToken,files('+fields+')',orderBy:'folder,createdTime desc,name',pageSize:'100',supportsAllDrives:'true',includeItemsFromAllDrives:'true',...(pageToken?{pageToken}:{})}));const items=(data.files||[]).filter(f=>validMediaID(f.id)&&!f.trashed&&!f.shortcutDetails&&f.parents?.includes(folder)&&!!mediaKind(f.mimeType)).map(item).sort(mediaItemOrder);const pending=await pendingDirectIDs(items.map(i=>i.id));items.splice(0,items.length,...items.filter(i=>!pending.has(i.id)));await ancestry(c,folder);await rememberLocations(c,folder,items);await live(c);return {connected:true,...flags,root:{id:chain[0].id,name:chain[0].name},folder:{id:folder,name:chain.at(-1)!.name},breadcrumbs:chain.map(f=>({id:f.id,name:f.name})),items,...(data.nextPageToken?{nextPageToken:data.nextPageToken}:{})};}
const hash=async(v:unknown)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(v))))).map(b=>b.toString(16).padStart(2,'0')).join('');
const operation=(id:string)=>database().prepare('SELECT * FROM jac_media_operations WHERE id=?').bind(id).first<Operation>();
async function begin(c:Context,input:{id:string;parentId:string;name:string;mimeType:string;size:number;kind:string}){const digest=await hash(input),now=new Date().toISOString();await live(c);await database().prepare(`INSERT OR IGNORE INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,name,mime_type,size,connection_version,created_at,expires_at) SELECT ?,?,?,?,?,?,?,?,?,?,? WHERE ${c.guard.sql}`).bind(input.id,c.guard.actorID,input.parentId,digest,input.kind,input.name,input.mimeType,input.size,c.config.version,now,new Date(Date.now()+7*86400000).toISOString(),...c.guard.bindings).run();const row=await operation(input.id);if(!row||row.actor_id!==c.guard.actorID||row.payload_hash!==digest||row.connection_version!==c.config.version)throw new MediaFailure('Esta solicitud ya pertenece a otro archivo, cuenta o conexión.',409);if(row.status!=='ready'&&row.expires_at<now)throw new MediaFailure('La subida venció. Selecciona el archivo como una nueva subida.',410);return row;}
async function lock(c:Context,row:Operation){const claim=crypto.randomUUID(),r=await database().prepare(`UPDATE jac_media_operations SET claim=?,claim_at=? WHERE id=? AND actor_id=? AND (claim='' OR claim_at<?) AND offset=? AND status=? AND drive_id=? AND session_payload=? AND connection_version=? AND ${c.guard.sql}`).bind(claim,new Date().toISOString(),row.id,c.guard.actorID,new Date(Date.now()-120000).toISOString(),row.offset,row.status,row.drive_id,row.session_payload,row.connection_version,...c.guard.bindings).run();if(r.meta.changes!==1)throw new MediaFailure('Esta subida ya está en curso. Espera un momento y reintenta.',409);return claim;}
async function update(c:Context,id:string,claim:string,values:{driveID?:string;session?:string;offset?:number;status?:string}){await live(c);const sets:string[]=[],args:(string|number)[]=[];for(const [key,column] of [['driveID','drive_id'],['session','session_payload'],['offset','offset'],['status','status']] as const){if(values[key]!==undefined){sets.push(column+'=?');args.push(values[key]!);}}const r=await database().prepare(`UPDATE jac_media_operations SET ${sets.join(',')} WHERE id=? AND actor_id=? AND claim=? AND connection_version=? AND ${c.guard.sql}`).bind(...args,id,c.guard.actorID,claim,c.config.version,...c.guard.bindings).run();if(r.meta.changes!==1)throw new MediaFailure('Tu sesión o la subida cambió.',403);}
async function unlock(id:string,claim:string){await database().prepare("UPDATE jac_media_operations SET claim='',claim_at='' WHERE id=? AND claim=?").bind(id,claim).run();}
async function reserve(c:Context,row:Operation,claim:string){if(row.drive_id)return row.drive_id;const result=await json<{ids?:string[]}>(c,'https://www.googleapis.com/drive/v3/files/generateIds?count=1&space=drive&type=files');const id=result.ids?.[0];if(!validMediaID(id))throw new MediaFailure('Google no confirmó el identificador del archivo.',502);await update(c,row.id,claim,{driveID:id});return id;}
export async function createMediaFolder(g:MediaGuard,input:Record<string,unknown>){if(!validMediaRequestID(input.id)||!validMediaID(input.parentId))throw new MediaFailure('La solicitud de carpeta no es válida.');const name=mediaFolderName(input.name,input.date),c=await mediaContext(g);await parent(c,input.parentId);const row=await begin(c,{id:input.id,parentId:input.parentId,name,mimeType:MEDIA_FOLDER_MIME,size:0,kind:'folder'});if(row.status==='ready'){const chain=await ancestry(c,row.drive_id);return {folder:{id:row.drive_id,name:chain.at(-1)!.name}};}const claim=await lock(c,row);try{const id=await reserve(c,row,claim);let found:DriveFile|null=null;try{found=await metadata(c,id);}catch(e){if(!(e instanceof MediaFailure&&e.status===404))throw e;}if(!found){await parent(c,row.parent_id);found=await json<DriveFile>(c,'https://www.googleapis.com/drive/v3/files?'+new URLSearchParams({fields,supportsAllDrives:'true'}),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id,name,mimeType:MEDIA_FOLDER_MIME,parents:[row.parent_id],appProperties:{jac_media_request:row.id}})});}if(found.id!==id||found.mimeType!==MEDIA_FOLDER_MIME||!found.parents?.includes(row.parent_id))throw new MediaFailure('Google no confirmó la carpeta solicitada.',502);await ancestry(c,id);await update(c,row.id,claim,{status:'ready'});return {folder:{id,name:found.name}};}finally{await unlock(row.id,claim);}}
const uploadState=(r:Operation)=>({id:r.id,offset:r.offset,chunkSize:MEDIA_CHUNK_SIZE,complete:r.status==='ready'});
async function ownUpload(c:Context,id:unknown){if(!validMediaRequestID(id))throw new MediaFailure('La subida no es válida.');const r=await operation(id);if(!r||r.kind!=='upload'||r.actor_id!==c.guard.actorID)throw new MediaFailure('La subida no existe.',404);if(r.connection_version!==c.config.version||r.status!=='ready'&&r.expires_at<new Date().toISOString())throw new MediaFailure('La subida venció o cambió la conexión. Inicia otra subida.',409);await parent(c,r.parent_id);return r;}
function sessionURL(value:unknown){if(typeof value!=='string')throw new MediaFailure('Google no confirmó la sesión de subida.',502);const url=new URL(googleURL(value));if(!/^\/upload\/drive\/v3\/files(?:\/[A-Za-z0-9_-]+)?$/.test(url.pathname)||!url.searchParams.get('upload_id'))throw new MediaFailure('Google devolvió una sesión de subida inesperada.',502);return url.toString();}
export async function startMediaUpload(g:MediaGuard,input:Record<string,unknown>){const data=mediaUploadInput(input),c=await mediaContext(g);await parent(c,data.parentId);const row=await begin(c,{id:data.id,parentId:data.parentId,name:data.filename,mimeType:data.mimeType,size:data.size,kind:'upload'});if(row.status==='ready'){await ancestry(c,row.drive_id);return uploadState(row);}if(row.session_payload)return mediaUploadStatus(g,row.id);const claim=await lock(c,row);try{const id=await reserve(c,row,claim);await parent(c,row.parent_id);const r=await request(c,'https://www.googleapis.com/upload/drive/v3/files?'+new URLSearchParams({uploadType:'resumable',supportsAllDrives:'true',fields}),{method:'POST',headers:{'Content-Type':'application/json','X-Upload-Content-Type':row.mime_type,'X-Upload-Content-Length':String(row.size)},body:JSON.stringify({id,name:row.name,mimeType:row.mime_type,parents:[row.parent_id],appProperties:{jac_media_request:row.id}})});await checked(r);const url=sessionURL(r.headers.get('location'));await r.body?.cancel();await update(c,row.id,claim,{session:await encryptMail({url},mailKey()),offset:0});return uploadState((await operation(row.id))!);}finally{await unlock(row.id,claim);}}
async function reconcile(c:Context,row:Operation,claim:string,r:Response){await checked(r);let offset=0,status='pending';if(r.status===308){const range=r.headers.get('range');if(range&&!/^bytes=0-\d+$/.test(range))throw new MediaFailure('Google no confirmó el progreso de subida.',502);offset=range?Number(range.slice(8))+1:0;if(!Number.isSafeInteger(offset)||offset<row.offset||offset>row.size)throw new MediaFailure('Google devolvió un progreso de subida inesperado.',502);await r.body?.cancel();}else{const f=await r.json() as DriveFile;if(f.id!==row.drive_id)throw new MediaFailure('Google no confirmó el archivo subido.',502);const chain=await ancestry(c,row.drive_id),actual=chain.at(-1)!;if(actual.mimeType!==row.mime_type||Number(actual.size)!==row.size||actual.parents?.[0]!==row.parent_id)throw new MediaFailure('El archivo final no coincide con la subida.',502);offset=row.size;status='ready';}await update(c,row.id,claim,{offset,status});return uploadState((await operation(row.id))!);}
export async function mediaUploadStatus(g:MediaGuard,id:unknown){const c=await mediaContext(g),row=await ownUpload(c,id);if(row.status==='ready'){await ancestry(c,row.drive_id);return uploadState(row);}if(!row.session_payload)return uploadState(row);const claim=await lock(c,row);try{const {url}=await decryptMail<{url:string}>(row.session_payload,mailKey()),r=await request(c,sessionURL(url),{method:'PUT',headers:{'Content-Range':'bytes */'+row.size,'Content-Length':'0'},body:new Uint8Array()},true);if(r.status===404||r.status===410){await r.body?.cancel();let file:DriveFile|null=null;try{file=await metadata(c,row.drive_id);}catch(e){if(!(e instanceof MediaFailure&&e.status===404))throw e;}if(file&&file.mimeType===row.mime_type&&Number(file.size)===row.size&&file.parents?.[0]===row.parent_id){await ancestry(c,row.drive_id);await update(c,row.id,claim,{offset:row.size,status:'ready'});return uploadState((await operation(row.id))!);}throw new MediaFailure('La sesión de subida venció. Selecciona el archivo de nuevo.',410);}return await reconcile(c,row,claim,r);}finally{await unlock(row.id,claim);}}
export async function appendMediaUpload(g:MediaGuard,id:unknown,offset:number,bytes:Uint8Array){const c=await mediaContext(g),row=await ownUpload(c,id);if(row.status==='ready'){await ancestry(c,row.drive_id);return uploadState(row);}if(!row.session_payload)throw new MediaFailure('Prepara primero la subida.',409);if(!Number.isSafeInteger(offset)||offset!==row.offset||bytes.length===0||bytes.length>MEDIA_CHUNK_SIZE||offset+bytes.length>row.size||(offset+bytes.length<row.size&&bytes.length!==MEDIA_CHUNK_SIZE))throw new MediaFailure('El progreso cambió. Revisa el estado y reintenta la subida.',409);if(offset===0&&!mediaSignature(bytes,row.mime_type))throw new MediaFailure('El contenido no corresponde a una foto o video del tipo seleccionado.');const claim=await lock(c,row);try{const {url}=await decryptMail<{url:string}>(row.session_payload,mailKey());await parent(c,row.parent_id);const r=await request(c,sessionURL(url),{method:'PUT',headers:{'Content-Type':row.mime_type,'Content-Length':String(bytes.length),'Content-Range':`bytes ${offset}-${offset+bytes.length-1}/${row.size}`},body:bytes as BodyInit},true);return await reconcile(c,row,claim,r);}finally{await unlock(row.id,claim);}}
async function thumbnailBytes(response:Response){
 const length=response.headers.get('content-length');if(length&&/^\d+$/.test(length)&&Number(length)>MEDIA_THUMBNAIL_MAX_BYTES){await response.body?.cancel().catch(()=>{});throw new MediaFailure('La miniatura supera el tamaño permitido.',502);}
 const reader=response.body?.getReader();if(!reader)throw new MediaFailure('Google no devolvió una miniatura válida.',502);
 const parts:Uint8Array[]=[];let size=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>MEDIA_THUMBNAIL_MAX_BYTES){await reader.cancel().catch(()=>{});throw new MediaFailure('La miniatura supera el tamaño permitido.',502);}parts.push(value);}}finally{reader.releaseLock();}
 if(!size)throw new MediaFailure('Google no devolvió una miniatura válida.',502);const bytes=new Uint8Array(size);let position=0;for(const part of parts){bytes.set(part,position);position+=part.length;}return bytes;
}
export async function mediaFile(g:MediaGuard,id:string,thumbnail:boolean,range:string|null,revision?:string){
 const c=await mediaContext(g);await publishedDirect(id);const chain=await ancestry(c,safeID(id)),f=chain.at(-1)!;if(revision&&f.modifiedTime!==revision)throw new MediaFailure('El archivo cambió. Actualiza la carpeta.',409);
 if(f.mimeType===MEDIA_FOLDER_MIME||f.capabilities?.canDownload===false)throw new MediaFailure('El archivo no se puede abrir.',403);
 const requested=thumbnail?null:mediaRange(range);let r:Response,preview:Uint8Array|undefined;
 if(thumbnail){
  if(!f.thumbnailLink)throw new MediaFailure('La vista previa aún no está disponible.',404);
  const url=mediaThumbnailURL(f.thumbnailLink);await live(c);
  try{r=await fetch(url,{headers:{Authorization:'Bearer '+c.access,Accept:'image/jpeg, image/png, image/webp, image/gif'},redirect:'manual',signal:AbortSignal.timeout(15000)});}catch{throw new MediaFailure('No pudimos abrir la miniatura.',502);}
  try{await live(c);}catch(e){await r.body?.cancel().catch(()=>{});throw e;}
  if(r.status>=300&&r.status<400){await r.body?.cancel().catch(()=>{});throw new MediaFailure('La miniatura devolvió una dirección inesperada.',502);}
  await checked(r);
  if(!/^image\/(jpeg|png|gif|webp)(?:;|$)/i.test(r.headers.get('content-type')||'')){await r.body?.cancel().catch(()=>{});throw new MediaFailure('Google no devolvió una miniatura válida.',502);}
  preview=await thumbnailBytes(r);
 }else{
  r=await request(c,'https://www.googleapis.com/drive/v3/files/'+id+'?alt=media&supportsAllDrives=true',{headers:requested?{Range:requested}:{}});await checked(r);if(requested&&(r.status!==206||!/^bytes \d+-\d+\/\d+$/.test(r.headers.get('content-range')||''))){await r.body?.cancel();throw new MediaFailure('Google no confirmó el tramo solicitado.',502);}
 }
 // The preview is bounded and fully read before the final ancestry/permission
 // check. Original videos remain streamed and keep their existing range support.
 const final=await ancestry(c,id);if(revision&&final.at(-1)!.modifiedTime!==revision){await r.body?.cancel();throw new MediaFailure('El archivo cambió. Actualiza la carpeta.',409);}await live(c);
 const headers=new Headers({'Content-Type':thumbnail?r.headers.get('content-type')!:f.mimeType,'Content-Disposition':"inline; filename*=UTF-8''"+encodeURIComponent(f.name.replace(/[\u0000-\u001f\u007f]/g,'').slice(0,180)),'Accept-Ranges':thumbnail?'none':'bytes','Content-Security-Policy':"default-src 'none'; sandbox"});
 if(preview)headers.set('Content-Length',String(preview.byteLength));else for(const name of ['content-length','content-range']){const value=r.headers.get(name);if(value)headers.set(name,value);}
 return new Response(preview?preview as BodyInit:r.body,{status:thumbnail?200:r.status,headers});
}

// Direct sessions are bearer capabilities for ONE reserved new file. Google may
// keep them alive for a week; logout cannot retroactively shorten that lease.
// Initiate outside the shared tree. Only JAC can publish the completed file into
// its destination after current authorization, signature and identity checks.
async function pendingDirectIDs(ids:string[]){
 if(!ids.length)return new Set<string>();
 const rows=await database().prepare("SELECT drive_id FROM jac_media_operations WHERE kind='direct' AND status<>'ready' AND drive_id IN(SELECT value FROM json_each(?))").bind(JSON.stringify(ids)).all<{drive_id:string}>();
 return new Set(rows.results.map(r=>r.drive_id));
}
async function publishedDirect(id:string){if((await pendingDirectIDs([id])).has(id))throw new MediaFailure('El archivo aún no está disponible en Fotografía.',404);}
export async function mediaMetadata(g:MediaGuard,id:string){const c=await mediaContext(g);await publishedDirect(safeID(id));const chain=await ancestry(c,id),f=chain.at(-1)!;if(f.mimeType===MEDIA_FOLDER_MIME||f.capabilities?.canDownload===false)throw new MediaFailure('El archivo no se puede abrir.',403);await live(c);return {item:item(f)};}
async function directRow(c:Context,id:unknown){
 if(!validMediaRequestID(id))throw new MediaFailure('La subida no es válida.');
 const row=await operation(id);
 if(!row||row.actor_id!==c.guard.actorID||row.kind!=='direct')throw new MediaFailure('La subida no existe.',404);
 if(row.status==='cancelled'||row.connection_version!==c.config.version||row.status!=='ready'&&row.expires_at<new Date().toISOString())throw new MediaFailure('La subida venció o se canceló.',410);
 await parent(c,row.parent_id);return row;
}
async function directState(c:Context,row:Operation){
 await live(c);const base={id:row.id,offset:row.offset,chunkSize:MEDIA_DIRECT_CHUNK_SIZE,complete:row.status==='ready'};
 if(base.complete)return base;
 const secret=await decryptMail<{url:string}>(row.session_payload,mailKey());return {...base,uploadURL:sessionURL(secret.url)};
}
export async function startDirectMediaUpload(g:MediaGuard,input:Record<string,unknown>,origin:string){
 const data=mediaUploadInput(input),c=await mediaContext(g);await parent(c,data.parentId);
 const row=await begin(c,{id:data.id,parentId:data.parentId,name:data.filename,mimeType:data.mimeType,size:data.size,kind:'direct'});
 if(row.status==='cancelled')throw new MediaFailure('La subida fue cancelada.',410);
 if(row.session_payload||row.status==='ready')return directMediaUploadStatus(g,row.id);
 const claim=await lock(c,row);try{
  const id=await reserve(c,row,claim);await parent(c,row.parent_id);
  const response=await request(c,'https://www.googleapis.com/upload/drive/v3/files?'+new URLSearchParams({uploadType:'resumable',supportsAllDrives:'true',fields}),{method:'POST',headers:{'Content-Type':'application/json','X-Upload-Content-Type':row.mime_type,'X-Upload-Content-Length':String(row.size),Origin:origin},body:JSON.stringify({id,name:row.name,mimeType:row.mime_type,appProperties:{jac_media_request:row.id,jac_media_staged:'1'}})});
  await checked(response);const url=sessionURL(response.headers.get('location'));await response.body?.cancel();
  await update(c,row.id,claim,{session:await encryptMail({url},mailKey()),offset:0});return await directState(c,(await operation(row.id))!);
 }finally{await unlock(row.id,claim);}
}
async function finishDirect(c:Context,row:Operation,claim:string,stagingParent:string){
 const file=await metadata(c,row.drive_id);
 if(file.id!==row.drive_id||file.name!==row.name||file.mimeType!==row.mime_type||Number(file.size)!==row.size||file.appProperties?.jac_media_request!==row.id||file.appProperties?.jac_media_staged!=='1')throw new MediaFailure('El archivo final no coincide con la subida.',422);
 // A retry may find a successful move whose response was lost. Never adopt an
 // arbitrary externally moved file, even if its ID happens to be reserved here.
 if(file.parents?.length&&!(file.parents.length===1&&(file.parents[0]===row.parent_id||file.parents[0]===stagingParent)))throw new MediaFailure('La ubicación de la subida cambió.',403);
 const end=Math.min(63,row.size-1),response=await request(c,'https://www.googleapis.com/drive/v3/files/'+row.drive_id+'?alt=media&supportsAllDrives=true',{headers:{Range:`bytes=0-${end}`}});await checked(response);
 if(response.status!==206||response.headers.get('content-range')!==`bytes 0-${end}/${row.size}`){await response.body?.cancel();throw new MediaFailure('Google no confirmó el contenido del archivo.',502);}
 const bytes=await thumbnailBytes(response);if(bytes.length!==end+1||!mediaSignature(bytes,row.mime_type))throw new MediaFailure('El contenido no corresponde a la foto o video seleccionado.',422);
 await parent(c,row.parent_id);
 if(!file.parents?.includes(row.parent_id)){
  const moved=await json<DriveFile>(c,'https://www.googleapis.com/drive/v3/files/'+row.drive_id+'?'+new URLSearchParams({addParents:row.parent_id,...(file.parents?.length?{removeParents:file.parents.join(',')}:{}),supportsAllDrives:'true',fields}),{method:'PATCH',headers:{'Content-Type':'application/json'},body:'{}'});
  if(moved.id!==row.drive_id)throw new MediaFailure('Google no confirmó la carpeta del archivo.',502);
 }
 await ancestry(c,row.drive_id);await update(c,row.id,claim,{offset:row.size,status:'ready'});return directState(c,(await operation(row.id))!);
}
// New files without explicit parents are placed in the owner's My Drive root.
// Resolve that ID with Google, never accept a staging parent from the client.

export async function directMediaUploadStatus(g:MediaGuard,id:unknown){
 const c=await mediaContext(g),row=await directRow(c,id);
 if(row.status==='ready'){await ancestry(c,row.drive_id);return directState(c,row);}
 if(!row.session_payload)throw new MediaFailure('Prepara primero la subida.',409);
 const claim=await lock(c,row);try{
  const {url}=await decryptMail<{url:string}>(row.session_payload,mailKey());
  const response=await request(c,sessionURL(url),{method:'PUT',headers:{'Content-Range':'bytes */'+row.size,'Content-Length':'0'},body:new Uint8Array()},true);
  if(response.status===308){await checked(response);const range=response.headers.get('range');if(range&&!/^bytes=0-\d+$/.test(range))throw new MediaFailure('Google no confirmó el progreso.',502);const offset=range?Number(range.slice(8))+1:0;await response.body?.cancel();if(!Number.isSafeInteger(offset)||offset<row.offset||offset>=row.size)throw new MediaFailure('Google devolvió un progreso inesperado.',502);await update(c,row.id,claim,{offset});return directState(c,(await operation(row.id))!);}
  if(!response.ok&&![404,410].includes(response.status))await checked(response);else await response.body?.cancel();
  // The session may disappear after the final PUT. The fixed file ID recovers
  // that success without creating a second file.
  const root=await json<{id:string}>(c,'https://www.googleapis.com/drive/v3/files/root?fields=id');if(!validMediaID(root.id))throw new MediaFailure('Google no confirmó la ubicación temporal.',502);
  try{return await finishDirect(c,row,claim,root.id);}catch(e){if(e instanceof MediaFailure&&e.status===404)throw new MediaFailure('La sesión de subida venció. Selecciona el archivo de nuevo.',410);throw e;}
 }finally{await unlock(row.id,claim);}
}
export async function cancelDirectMediaUpload(g:MediaGuard,id:unknown){
 const c=await mediaContext(g),row=await directRow(c,id);if(row.status==='ready')return {cancelled:false};
 const claim=await lock(c,row);try{await update(c,row.id,claim,{status:'cancelled',session:''});return {cancelled:true};}finally{await unlock(row.id,claim);}
}

// Compatibility path only when a browser/network refuses the direct request.
// It resumes the SAME reserved file/session; never creates an alternate copy.
export async function relayDirectMediaUpload(g:MediaGuard,id:unknown,offset:number,bytes:Uint8Array){
 const c=await mediaContext(g),row=await directRow(c,id);
 if(row.status==='ready'){await ancestry(c,row.drive_id);return directState(c,row);}
 if(!Number.isSafeInteger(offset)||offset!==row.offset||!bytes.length||bytes.length>MEDIA_CHUNK_SIZE||offset+bytes.length>row.size||(offset+bytes.length<row.size&&bytes.length!==MEDIA_CHUNK_SIZE))throw new MediaFailure('El progreso cambió. Revisa el estado de la subida.',409);
 if(offset===0&&!mediaSignature(bytes,row.mime_type))throw new MediaFailure('El contenido no corresponde al archivo seleccionado.',422);
 const claim=await lock(c,row);try{
  const {url}=await decryptMail<{url:string}>(row.session_payload,mailKey());
  const response=await request(c,sessionURL(url),{method:'PUT',headers:{'Content-Type':row.mime_type,'Content-Length':String(bytes.length),'Content-Range':`bytes ${offset}-${offset+bytes.length-1}/${row.size}`},body:bytes as BodyInit},true);await checked(response);
  if(response.status===308){await response.body?.cancel();const range=response.headers.get('range');if(range!==`bytes=0-${offset+bytes.length-1}`)throw new MediaFailure('Google no confirmó el progreso de subida.',502);await update(c,row.id,claim,{offset:offset+bytes.length});return directState(c,(await operation(row.id))!);}
  await response.body?.cancel();const root=await json<{id:string}>(c,'https://www.googleapis.com/drive/v3/files/root?fields=id');if(!validMediaID(root.id))throw new MediaFailure('Google no confirmó la ubicación temporal.',502);
  return await finishDirect(c,row,claim,root.id);
 }finally{await unlock(row.id,claim);}
}
