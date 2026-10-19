import {createHash,randomBytes} from 'node:crypto';
import {database} from '@/db/raw';
import {mailKey} from './payroll-mail';
import {encryptMail,decryptMail} from './payroll-mail-core';
import {mediaGuardActive,type MediaGuard} from './media-drive';
import {r2Feed,r2File,R2_ROOT} from './media-r2-gallery';
import {MediaFailure,validMediaRequestID} from './media-core';
import {sectionSql,type AccessUser} from './payroll-permissions';
import {mediaArchiveName,uniqueMediaArchiveName,type MediaZipFile} from './media-download-zip';
import type {MediaItem} from './media-core';
import {r2Request} from './media-r2-s3';
import type {MediaR2Secret} from './media-r2';

type Share={id:string;folder_id:string;token_hash:string;token_cipher:string;actor_id:string;actor_version:number;connection_version:number;expires_at:string;revoked_at:string;created_at:string};
let storageReady=false;
// Initialize only this additive feature through the Worker's existing D1
// binding, after authorization. This also supports deployments whose token may
// publish Workers but cannot invoke D1's administrative migration API.
async function ensureStorage(g:MediaGuard){
 if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión o tus permisos cambiaron.',403);
 if(!storageReady){await database().batch([
  database().prepare("CREATE TABLE IF NOT EXISTS jac_media_folder_shares (id TEXT PRIMARY KEY NOT NULL,folder_id TEXT NOT NULL,token_hash TEXT NOT NULL UNIQUE,token_cipher TEXT NOT NULL,actor_id TEXT NOT NULL,actor_version INTEGER NOT NULL,connection_version INTEGER NOT NULL,expires_at TEXT NOT NULL,revoked_at TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL)"),
  database().prepare('CREATE INDEX IF NOT EXISTS jac_media_folder_shares_folder ON jac_media_folder_shares(folder_id,created_at)')
 ]);storageReady=true;}
 if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión o tus permisos cambiaron.',403);
}
const guest:AccessUser={id:'shared-folder',email:'',username:'',displayName:'Invitado',fullName:null,isOwner:false,permissions:[],sections:['media']};
const invalid=()=>new MediaFailure('Este enlace no está disponible o ya venció.',410);
const hash=(token:string)=>createHash('sha256').update(token).digest('hex');
function folderID(value:unknown):string {if(typeof value!=='string'||!/^r2_[a-f0-9-]{36}$/.test(value))throw new MediaFailure('Selecciona una carpeta del archivo actual.');return value;}
async function checked(g:MediaGuard,folder:string){if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión o tus permisos cambiaron.',403);const feed=await r2Feed(g,guest,folder);if(feed.folder.id===R2_ROOT)throw new MediaFailure('Selecciona una carpeta, no el archivo completo.');return feed;}
async function visible(row:Share){const secret=await decryptMail<{token:string}>(row.token_cipher,mailKey());return {id:row.id,url:'/compartir/'+secret.token,createdAt:row.created_at,expiresAt:row.expires_at};}
export async function listFolderShares(g:MediaGuard,folder:unknown){
 const id=folderID(folder);await checked(g,id);await ensureStorage(g);
 const rows=await database().prepare("SELECT * FROM jac_media_folder_shares WHERE folder_id=? AND revoked_at='' AND expires_at>? ORDER BY created_at DESC LIMIT 100").bind(id,new Date().toISOString()).all<Share>();
 const result=await Promise.all(rows.results.map(visible));await checked(g,id);return {links:result};
}
export async function createFolderShare(g:MediaGuard,input:Record<string,unknown>){
 const folder=folderID(input.folderId);if(!validMediaRequestID(input.id)||![7,30,90].includes(input.days as number))throw new MediaFailure('Revisa la duración del enlace.');
 await checked(g,folder);await ensureStorage(g);
 const previous=await database().prepare('SELECT * FROM jac_media_folder_shares WHERE id=?').bind(input.id).first<Share>();
 if(previous){if(previous.actor_id!==g.actorID||previous.folder_id!==folder||previous.revoked_at||previous.expires_at<=new Date().toISOString())throw new MediaFailure('La solicitud de enlace cambió. Crea otro enlace.',409);await checked(g,folder);return {link:await visible(previous)};}
 const token=randomBytes(32).toString('base64url'),now=new Date(),expires=new Date(now.getTime()+Number(input.days)*86400000).toISOString();
 const cipher=await encryptMail({token},mailKey());
 const saved=await database().prepare(`INSERT OR IGNORE INTO jac_media_folder_shares(id,folder_id,token_hash,token_cipher,actor_id,actor_version,connection_version,expires_at,created_at)
 SELECT ?,?,?,?,?,u.version,c.version,?,? FROM payroll_users u CROSS JOIN jac_media_r2_connection c
 WHERE u.id=? AND c.id='jac' AND c.enabled=1 AND ${g.sql}`)
 .bind(input.id,folder,hash(token),cipher,g.actorID,expires,now.toISOString(),g.actorID,...g.bindings).run();
 if(saved.meta.changes!==1)throw new MediaFailure('Tu sesión cambió o la solicitud ya fue utilizada. Reintenta.',409);
 // A concurrent deletion/permission change cannot return a usable capability.
 await checked(g,folder);const row=await database().prepare('SELECT * FROM jac_media_folder_shares WHERE id=?').bind(input.id).first<Share>();if(!row)throw invalid();return {link:await visible(row)};
}
export async function revokeFolderShare(g:MediaGuard,input:Record<string,unknown>){
 const folder=folderID(input.folderId);if(!validMediaRequestID(input.id))throw new MediaFailure('El enlace no es válido.');await checked(g,folder);await ensureStorage(g);
 await database().prepare(`UPDATE jac_media_folder_shares SET revoked_at=? WHERE id=? AND folder_id=? AND revoked_at='' AND ${g.sql}`).bind(new Date().toISOString(),input.id,folder,...g.bindings).run();
 await checked(g,folder);return {revoked:true};
}

// A capability is a separate read-only guard. Never manufacture a JAC session
// or pass it to write operations. Every S3/SQL boundary rechecks this predicate.
async function sharedGuard(token:unknown,target?:string){
 if(typeof token!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(token))throw invalid();
 if(!storageReady){const exists=await database().prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='jac_media_folder_shares'").first();if(!exists)throw invalid();storageReady=true;}
 const digest=hash(token),row=await database().prepare('SELECT * FROM jac_media_folder_shares WHERE token_hash=?').bind(digest).first<Share>();if(!row)throw invalid();
 const selected=target?folderID(target):row.folder_id;
 const g:MediaGuard={actorID:row.actor_id,bindings:[digest,selected],sql:`EXISTS(
 SELECT 1 FROM jac_media_folder_shares s JOIN payroll_users u ON u.id=s.actor_id AND u.version=s.actor_version
 JOIN jac_media_r2_connection c ON c.id='jac' AND c.enabled=1 AND c.version=s.connection_version
 WHERE s.token_hash=? AND s.revoked_at='' AND s.expires_at>strftime('%Y-%m-%dT%H:%M:%fZ','now')
 AND u.active=1 AND u.password_hash<>'' AND ${sectionSql('u','media')} AND ${sectionSql('u','mediaUpload')}
 AND EXISTS(WITH RECURSIVE ancestors(id) AS (SELECT ? UNION SELECT e.parent_id FROM jac_media_r2_entries e JOIN ancestors a ON e.id=a.id WHERE a.id<>'${R2_ROOT}') SELECT 1 FROM ancestors WHERE id=s.folder_id))`};
 if(!await mediaGuardActive(g))throw invalid();return {g,row,selected};
}
export async function sharedFolderFeed(token:unknown,folder?:string,page?:string){
 const {g,row,selected}=await sharedGuard(token,folder),feed=await r2Feed(g,guest,selected,page);
 const index=feed.breadcrumbs.findIndex(folder=>folder.id===row.folder_id);if(index<0)throw invalid();
 // Omit full-gallery roots, deleted IDs, roles, upload state and actor details.
 return {folder:feed.folder,breadcrumbs:feed.breadcrumbs.slice(index),items:feed.items,nextPageToken:feed.nextPageToken||'',expiresAt:row.expires_at};
}
export async function sharedFolderFile(token:unknown,id:string,thumbnail:boolean,range:string|null,revision?:string,preview=false){
 const {g}=await sharedGuard(token,id);return r2File(g,id,thumbnail,range,revision,preview);
}

export type SharedDownloadMode='selected'|'photos'|'all';
export async function sharedFolderDownloadPlan(token:unknown,folder:string,mode:SharedDownloadMode,selected:{id:string;revision:string}[]=[]){
 if(!['selected','photos','all'].includes(mode)||mode==='selected'&&(!selected.length||selected.length>5000))throw new MediaFailure('Selecciona las fotos o videos que quieres descargar.');
 const wanted=new Map(selected.map(item=>[folderID(item.id),item.revision]));
 if(wanted.size!==selected.length||selected.some(item=>typeof item.revision!=='string'||item.revision.length>100))throw new MediaFailure('La selección no es válida.');
 const first=await sharedFolderFeed(token,folder||undefined),pending:{id:string;path:string;feed?:typeof first}[]=[{id:first.folder.id,path:'',feed:first}],visited=new Set<string>(),seen=new Set<string>(),used=new Set<string>(),files:MediaZipFile[]=[];
 const {g}=await sharedGuard(token,first.folder.id),connection=await database().prepare("SELECT credentials FROM jac_media_r2_connection WHERE id='jac' AND enabled=1").first<{credentials:string}>();
 if(!connection)throw invalid();const secret=await decryptMail<MediaR2Secret>(connection.credentials,mailKey());
 while(pending.length){
  const current=pending.shift()!;if(visited.has(current.id))throw new MediaFailure('La estructura de la carpeta cambió. Actualiza y reintenta.',409);visited.add(current.id);
  let feed=current.feed??await sharedFolderFeed(token,current.id);
  while(true){
   for(const item of feed.items){
    if(item.kind==='folder'){
     if(mode!=='selected')pending.push({id:item.id,path:uniqueMediaArchiveName(current.path+mediaArchiveName(item.name),used)+'/'});
    }else if(mode==='selected'?wanted.has(item.id):mode==='all'||item.kind==='image'){
     if(seen.has(item.id))continue;seen.add(item.id);
     if(mode==='selected'&&wanted.get(item.id)!==item.modifiedAt)throw new MediaFailure('Un archivo seleccionado cambió. Actualiza la carpeta.',409);
     if(!Number.isSafeInteger(item.size)||item.size<=0)throw new MediaFailure('El tamaño de un archivo no es válido.',409);
     const name=uniqueMediaArchiveName(current.path+mediaArchiveName(item.name),used);
     files.push({name,size:item.size,open:signal=>openSharedDownloadFile(g,connection.credentials,secret,item,signal)});wanted.delete(item.id);
    }
   }
   if(!feed.nextPageToken)break;feed=await sharedFolderFeed(token,current.id,feed.nextPageToken);
  }
 }
 if(mode==='selected'&&wanted.size)throw new MediaFailure('Un archivo seleccionado ya no está en esta carpeta.',409);
 if(!files.length)throw new MediaFailure(mode==='photos'?'No hay fotos para descargar en esta carpeta.':'No hay archivos para descargar en esta carpeta.',404);
 await sharedGuard(token,first.folder.id);
 return {name:mediaArchiveName(first.folder.name)+(mode==='photos'?' - Fotos':mode==='selected'?' - Selección':'')+'.zip',files};
}

async function openSharedDownloadFile(folderGuard:MediaGuard,credentials:string,secret:MediaR2Secret,item:MediaItem,signal?:AbortSignal){
 const g={...folderGuard,bindings:[folderGuard.bindings[0],item.id]};
 const check=async()=>{
  // One checked query per streamed window: current capability, creator and
  // connection, current ancestry/revision/key and deletion of any ancestor.
  const row=await database().prepare(`SELECT 1 FROM jac_media_r2_entries e WHERE e.id=? AND e.modified_at=? AND e.size=? AND e.object_key=? AND e.mime_type=? AND ${g.sql}
   AND EXISTS(SELECT 1 FROM jac_media_r2_connection c WHERE c.id='jac' AND c.enabled=1 AND c.credentials=?)
   AND NOT EXISTS(WITH RECURSIVE ancestors(id) AS (SELECT e.id UNION SELECT p.parent_id FROM jac_media_r2_entries p JOIN ancestors a ON p.id=a.id WHERE a.id<>'${R2_ROOT}') SELECT 1 FROM ancestors a JOIN jac_media_operations d ON d.id='r2-delete:'||a.id AND d.kind IN ('r2-delete-folder','r2-delete-file'))`)
   .bind(item.id,item.modifiedAt,item.size,'originals/'+item.id.slice(3),item.mimeType,...g.bindings,credentials).first();
  if(!row)throw invalid();
 };
 await check();signal?.throwIfAborted();const timeout=new AbortController(),timer=setTimeout(()=>timeout.abort(),60000);let response:Response;
 try{response=await fetch(r2Request(secret,'GET','originals/'+item.id.slice(3)),{redirect:'manual',signal:signal?AbortSignal.any([signal,timeout.signal]):timeout.signal});}finally{clearTimeout(timer);}
 try{if(!response.ok||response.status!==200||!response.body)throw new MediaFailure('No se pudo leer el archivo completo.',502);await check();}catch(e){await response.body?.cancel();throw e;}
 if(!response.body)throw new MediaFailure('No se pudo leer el archivo.',502);
 return {body:response.body,check};
}

export async function sharedPlaybackGuard(token:string,id:string){return (await sharedGuard(token,id)).g;}
