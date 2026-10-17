import {createHash} from 'node:crypto';
import {database} from '@/db/raw';
import {mailKey} from './payroll-mail';
import {encryptMail,decryptMail} from './payroll-mail-core';
import {mediaGuardActive,type MediaGuard} from './media-drive';
import {MediaFailure,MEDIA_ROOT_ID,MEDIA_FOLDER_MIME,MEDIA_DIRECT_CHUNK_SIZE,MEDIA_THUMBNAIL_MAX_BYTES,canReadMedia,canUploadMedia,canDeleteMedia,canConnectMedia,mediaName,mediaFolderName,mediaUploadInput,mediaSignature,mediaRange,validMediaRequestID,type MediaItem} from './media-core';
import type {AccessUser} from './payroll-permissions';
import type {MediaR2Secret} from './media-r2';
import {MEDIA_IMAGE_LIMITS} from './media-image-policy';
import {r2Request,r2PartURL,r2Bytes,r2XML,xmlValue,xmlEscape} from './media-r2-s3';

export const R2_ROOT='jac_r2_root',R2_COLLECTION='jac-r2-new-20261016';
type Config={credentials:string;enabled:number;version:number};
type Context={g:MediaGuard;config:Config;secret:MediaR2Secret};
type Entry={id:string;parent_id:string;name:string;mime_type:string;size:number;object_key:string;thumbnail_key:string;actor_id:string;payload_hash:string;created_at:string;modified_at:string};
type Upload={id:string;actor_id:string;parent_id:string;payload_hash:string;drive_id:string;name:string;mime_type:string;size:number;offset:number;status:string;session_payload:string;connection_version:number;claim:string;claim_at:string;expires_at:string};
const config=()=>database().prepare("SELECT credentials,enabled,version FROM jac_media_r2_connection WHERE id='jac'").first<Config>();
export async function usesMediaR2(){return (await config())?.enabled===1;}
const same=(c:Context)=>`EXISTS(SELECT 1 FROM jac_media_r2_connection WHERE id='jac' AND enabled=1 AND version=${c.config.version}) AND ${c.g.sql}`;
async function live(c:Context){const row=await config();if(!row||row.enabled!==1||row.version!==c.config.version||row.credentials!==c.config.credentials||!await mediaGuardActive(c.g))throw new MediaFailure('La sesión, los permisos o la galería cambiaron. Actualiza Fotografía.',403);}
async function context(g:MediaGuard){if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión cambió.',403);const row=await config();if(!row?.enabled||!row.credentials)throw new MediaFailure('El archivo nuevo de Fotografía todavía no está activo.',409);const c={g,config:row,secret:await decryptMail<MediaR2Secret>(row.credentials,mailKey())};await live(c);return c;}
const hash=(v:unknown)=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const entry=(id:string)=>database().prepare('SELECT * FROM jac_media_r2_entries WHERE id=?').bind(id).first<Entry>();
const operation=(id:string)=>database().prepare("SELECT * FROM jac_media_operations WHERE id=? AND kind='r2-upload'").bind(id).first<Upload>();
const objectKey=(row:Upload)=>'originals/'+row.id.toLowerCase();
const rootID=(id:string)=>id===MEDIA_ROOT_ID||!id?R2_ROOT:id;
function checkedID(id:string){if(!/^r2_[a-f0-9-]{36}$/.test(id))throw new MediaFailure('Este archivo pertenece al archivo anterior de Drive. Abre el archivo nuevo de Fotografía.',410);return id;}
const deletionID=(id:string)=>'r2-delete:'+id;
const deletion=(id:string)=>database().prepare("SELECT * FROM jac_media_operations WHERE id=? AND kind='r2-delete-folder'").bind(deletionID(id)).first<Upload>();
function subtree(id:string){checkedID(id);return `WITH RECURSIVE tree(id) AS (SELECT '${id}' UNION SELECT e.id FROM jac_media_r2_entries e JOIN tree t ON e.parent_id=t.id)`;}
// Checked server IDs only; the primary-key lookup avoids scanning upload history.
function availableSQL(id:string){if(id!==R2_ROOT)checkedID(id);return `NOT EXISTS(WITH RECURSIVE ancestors(id) AS (SELECT '${id}' UNION SELECT e.parent_id FROM jac_media_r2_entries e JOIN ancestors a ON e.id=a.id WHERE a.id<>'${R2_ROOT}') SELECT 1 FROM ancestors a JOIN jac_media_operations d ON d.id='r2-delete:'||a.id AND d.kind='r2-delete-folder')`;}
async function chain(c:Context,id:string){
 const result:Entry[]=[],seen=new Set<string>();let next=rootID(id);
 for(let depth=0;depth<24;depth++){
  if(next===R2_ROOT){await live(c);return result;}
  checkedID(next);if(await deletion(next))throw new MediaFailure('Esta carpeta se eliminó de Fotografía.',410);if(seen.has(next))break;seen.add(next);const row=await entry(next);if(!row)throw new MediaFailure('El archivo o carpeta ya no está disponible.',404);
  if(result.length&&row.mime_type!==MEDIA_FOLDER_MIME)break;result.unshift(row);next=row.parent_id;
 }
 throw new MediaFailure('Ese archivo o carpeta no pertenece a Fotografía JAC.',403);
}
async function parent(c:Context,id:string){const rows=await chain(c,id);if(rows.length&&rows.at(-1)!.mime_type!==MEDIA_FOLDER_MIME)throw new MediaFailure('Selecciona una carpeta.');return rows;}
const item=(r:Entry):MediaItem=>({id:r.id,name:r.name,mimeType:r.mime_type,kind:r.mime_type===MEDIA_FOLDER_MIME?'folder':r.mime_type.startsWith('image/')?'image':'video',size:r.size,createdAt:r.created_at,modifiedAt:r.modified_at,thumbnailAvailable:!!r.thumbnail_key});
async function call(c:Context,method:Parameters<typeof r2Request>[1],key='',query:Record<string,string>={},headers:Record<string,string>={},body?:string|Uint8Array){
 await live(c);const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),60000);let response:Response;
 try{response=await fetch(r2Request(c.secret,method,key,query,headers,body),{redirect:'manual',signal:controller.signal});}catch{throw new MediaFailure('La conexión con Fotografía se interrumpió. Puedes reintentar sin duplicar archivos.',502);}finally{clearTimeout(timer);}
 try{await live(c);}catch(e){await response.body?.cancel();throw e;}
 if(response.status>=300&&response.status<400){await response.body?.cancel();throw new MediaFailure('R2 devolvió una redirección inesperada.',502);}return response;
}
async function checked(response:Response){if(response.ok)return;await response.body?.cancel();throw new MediaFailure(response.status===404?'El archivo no está disponible.':'R2 no confirmó la operación. Puedes reintentar.',response.status===404?404:response.status===416?416:502);}

// No Drive listing, import or fallback exists in this provider. Its root is an
// independent empty catalogue populated only by new JAC uploads.
export async function r2Feed(g:MediaGuard,user:AccessUser,folder=R2_ROOT,pageToken?:string){
 const c=await context(g);folder=rootID(folder);const rows=await parent(c,folder);
 if(pageToken&&!/^\d{1,8}$/.test(pageToken))throw new MediaFailure('La página solicitada no es válida.');const offset=Number(pageToken||0);
 const listed=await database().prepare(`SELECT * FROM jac_media_r2_entries WHERE parent_id=? AND NOT EXISTS(SELECT 1 FROM jac_media_operations d WHERE d.id='r2-delete:'||jac_media_r2_entries.id AND d.kind='r2-delete-folder') ORDER BY (mime_type=?) DESC,created_at DESC,name,id LIMIT 101 OFFSET ?`).bind(folder,MEDIA_FOLDER_MIME,offset).all<Entry>();
 await parent(c,folder);await live(c);const root={id:R2_ROOT,name:'Fotografía JAC'},breadcrumbs=[root,...rows.map(r=>({id:r.id,name:r.name}))];
 const removed=await database().prepare("SELECT parent_id FROM jac_media_operations WHERE kind='r2-delete-folder' AND connection_version=?").bind(c.config.version).all<{parent_id:string}>();const pending=canDeleteMedia(user)?await database().prepare("SELECT parent_id AS id,drive_id AS parentId,name,offset AS removed FROM jac_media_operations WHERE kind='r2-delete-folder' AND connection_version=? AND status='pending' ORDER BY created_at LIMIT 100").bind(c.config.version).all():null;await parent(c,folder);await live(c);
 return {canDelete:canDeleteMedia(user),deletedFolders:removed.results.map(x=>x.parent_id),pendingDeletions:pending?.results??[],connected:true,canRead:canReadMedia(user),canUpload:canUploadMedia(user),canConnect:canConnectMedia(user),provider:'r2',collectionID:R2_COLLECTION,root,folder:breadcrumbs.at(-1)!,breadcrumbs,items:listed.results.slice(0,100).map(item),...(listed.results.length>100?{nextPageToken:String(offset+100)}:{})};
}
export async function r2Folder(g:MediaGuard,input:Record<string,unknown>){
 if(!validMediaRequestID(input.id)||typeof input.parentId!=='string')throw new MediaFailure('La solicitud de carpeta no es válida.');
 const c=await context(g),id='r2_'+input.id.toLowerCase(),parentID=rootID(input.parentId),name=mediaName(input.name),digest=hash([c.g.actorID,parentID,name]),now=new Date().toISOString();await parent(c,parentID);
 await database().prepare(`INSERT OR IGNORE INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,thumbnail_key,actor_id,payload_hash,created_at,modified_at) SELECT ?,?,?,?,0,'','',?,?,?,? WHERE ${same(c)} AND ${availableSQL(parentID)}`).bind(id,parentID,name,MEDIA_FOLDER_MIME,g.actorID,digest,now,now,...g.bindings).run();
 const found=await entry(id);await live(c);let legacyDigest='';if(found&&found.payload_hash!==digest&&typeof input.date==='string'){try{legacyDigest=hash([g.actorID,parentID,mediaFolderName(input.name,input.date)]);}catch{}}if(!found||(found.payload_hash!==digest&&found.payload_hash!==legacyDigest)||found.mime_type!==MEDIA_FOLDER_MIME)throw new MediaFailure('Esta solicitud ya pertenece a otra carpeta o cuenta.',409);await parent(c,id);return {folder:{id,name:found.name}};
}
export async function r2Metadata(g:MediaGuard,id:string){const c=await context(g),rows=await chain(c,id),row=rows.at(-1);if(!row||row.mime_type===MEDIA_FOLDER_MIME)throw new MediaFailure('Selecciona una foto o video.');await live(c);return {item:item(row)};}
export async function r2File(g:MediaGuard,id:string,thumbnail:boolean,range:string|null,revision?:string){
 const c=await context(g),rows=await chain(c,id),row=rows.at(-1);if(!row||row.mime_type===MEDIA_FOLDER_MIME)throw new MediaFailure('Selecciona una foto o video.');
 if(revision&&revision!==row.modified_at)throw new MediaFailure('El archivo cambió. Actualiza la carpeta.',409);const key=thumbnail?row.thumbnail_key:row.object_key;if(!key)throw new MediaFailure('La miniatura todavía no está disponible.',404);
 const requested=thumbnail?null:mediaRange(range),response=await call(c,'GET',key,{},requested?{Range:requested}:{});await checked(response);
 if(requested&&response.status!==206){await response.body?.cancel();throw new MediaFailure('R2 no confirmó el rango solicitado.',502);}
 await chain(c,id);const after=await entry(id);if(after?.modified_at!==row.modified_at||after.object_key!==row.object_key){await response.body?.cancel();throw new MediaFailure('El archivo cambió. Actualiza la carpeta.',409);}await live(c);
 const headers=new Headers({'content-type':thumbnail?'image/jpeg':row.mime_type,'content-disposition':"inline; filename*=UTF-8''"+encodeURIComponent(thumbnail?'miniatura.jpg':row.name),'x-content-type-options':'nosniff','accept-ranges':thumbnail?'none':'bytes'});
 for(const key of ['content-length','content-range','etag']){const value=response.headers.get(key);if(value)headers.set(key,value);}
 if(thumbnail){const bytes=await r2Bytes(response,MEDIA_THUMBNAIL_MAX_BYTES);if(!jpegThumbnail(bytes))throw new MediaFailure('La miniatura no es válida.',502);await live(c);return new Response(bytes,{headers});}
 return new Response(response.body,{status:response.status,headers});
}
async function own(c:Context,id:unknown){if(!validMediaRequestID(id))throw new MediaFailure('La subida no es válida.');const row=await operation(id);if(!row||row.actor_id!==c.g.actorID||row.connection_version!==c.config.version)throw new MediaFailure('Esta subida no pertenece a tu cuenta o conexión.',403);if(row.status==='cancelled'||row.status!=='ready'&&row.expires_at<new Date().toISOString())throw new MediaFailure('La subida venció. Selecciona el archivo otra vez.',410);await parent(c,row.parent_id);return row;}
async function lock(c:Context,row:Upload){const claim=crypto.randomUUID(),result=await database().prepare(`UPDATE jac_media_operations SET claim=?,claim_at=? WHERE id=? AND actor_id=? AND kind='r2-upload' AND status=? AND offset=? AND session_payload=? AND (claim='' OR claim_at<?) AND ${same(c)} AND ${availableSQL(row.parent_id)}`).bind(claim,new Date().toISOString(),row.id,c.g.actorID,row.status,row.offset,row.session_payload,new Date(Date.now()-180000).toISOString(),...c.g.bindings).run();if(result.meta.changes!==1)throw new MediaFailure('Esta subida ya está en curso. Reintenta en un momento.',409);return claim;}
async function update(c:Context,row:Upload,claim:string,offset:number,status:string,session:string){await live(c);const result=await database().prepare(`UPDATE jac_media_operations SET offset=?,status=?,session_payload=? WHERE id=? AND actor_id=? AND claim=? AND connection_version=? AND ${same(c)} AND ${availableSQL(row.parent_id)}`).bind(offset,status,session,row.id,c.g.actorID,claim,c.config.version,...c.g.bindings).run();if(result.meta.changes!==1)throw new MediaFailure('La sesión o la subida cambió.',403);}
async function unlock(id:string,claim:string){await database().prepare("UPDATE jac_media_operations SET claim='',claim_at='' WHERE id=? AND claim=?").bind(id,claim).run();}
async function uploadID(row:Upload){const data=await decryptMail<{uploadId:string}>(row.session_payload,mailKey());if(typeof data.uploadId!=='string'||!data.uploadId||data.uploadId.length>2048||/[<>\s]/.test(data.uploadId))throw new MediaFailure('La sesión de subida no es válida.',502);return data.uploadId;}
async function state(c:Context,row:Upload){await live(c);if(row.status==='ready')return {id:row.id,offset:row.size,chunkSize:MEDIA_DIRECT_CHUNK_SIZE,complete:true,provider:'r2',fileId:row.drive_id};const part=Math.floor(row.offset/MEDIA_DIRECT_CHUNK_SIZE)+1,length=Math.min(MEDIA_DIRECT_CHUNK_SIZE,row.size-row.offset);if(row.offset%MEDIA_DIRECT_CHUNK_SIZE||length<=0)throw new MediaFailure('El progreso de la subida no es válido.',502);return {id:row.id,offset:row.offset,chunkSize:MEDIA_DIRECT_CHUNK_SIZE,complete:false,provider:'r2',uploadURL:r2PartURL(c.secret,objectKey(row),await uploadID(row),part,length,row.mime_type)};}
export async function r2Start(g:MediaGuard,input:Record<string,unknown>){
 const valid=mediaUploadInput(input);if(valid.id!==valid.id.toLowerCase())throw new MediaFailure('Usa el identificador original de la subida en minúsculas.');
 const imageLimit=input.imageLimit===undefined?0:Number(input.imageLimit);if(!MEDIA_IMAGE_LIMITS.includes(imageLimit as 0|2000000|4000000|6000000))throw new MediaFailure('El nivel de compresión no es válido.');
 if(valid.mimeType.startsWith('image/')&&imageLimit&&valid.size>imageLimit)throw new MediaFailure('La imagen supera el nivel elegido. Vuelve a seleccionarla o elige Sin compresión.',413);
 const c=await context(g),parentID=rootID(valid.parentId),digest=hash([g.actorID,parentID,valid.filename,valid.mimeType,valid.size,...(input.imageLimit===undefined?[]:[imageLimit])]),now=new Date().toISOString();await parent(c,parentID);
 await database().prepare(`INSERT OR IGNORE INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,drive_id,name,mime_type,size,connection_version,created_at,expires_at) SELECT ?,?,?,?,'r2-upload',?,?,?,?,?,?,? WHERE ${same(c)} AND ${availableSQL(parentID)}`).bind(valid.id,g.actorID,parentID,digest,'r2_'+valid.id.toLowerCase(),valid.filename,valid.mimeType,valid.size,c.config.version,now,new Date(Date.now()+7*86400000).toISOString(),...g.bindings).run();
 let row=await own(c,valid.id);if(row.payload_hash!==digest)throw new MediaFailure('Esta solicitud ya pertenece a otro archivo.',409);if(row.status==='ready'||row.session_payload)return state(c,row);
 const claim=await lock(c,row);try{
  const response=await call(c,'POST',objectKey(row),{uploads:''},{'content-type':row.mime_type,'x-amz-meta-jac-request':row.id});await checked(response);const id=xmlValue(await r2XML(response),'UploadId');if(!id||id.length>2048||/[<>\s]/.test(id))throw new MediaFailure('R2 no confirmó la sesión de subida.',502);
  await update(c,row,claim,0,'pending',await encryptMail({uploadId:id,imageLimit},mailKey()));row=(await operation(row.id))!;return state(c,row);
 }finally{await unlock(row.id,claim);}
}
async function finalObject(c:Context,row:Upload){
 const response=await call(c,'HEAD',objectKey(row));if(response.status===404){await response.body?.cancel();return false;}await checked(response);await response.body?.cancel();
 if(Number(response.headers.get('content-length'))!==row.size||response.headers.get('content-type')!==row.mime_type||response.headers.get('x-amz-meta-jac-request')!==row.id)throw new MediaFailure('El archivo final no coincide con la subida.',422);
 const end=Math.min(63,row.size-1),first=await call(c,'GET',objectKey(row),{},{Range:`bytes=0-${end}`});await checked(first);if(first.status!==206||first.headers.get('content-range')!==`bytes 0-${end}/${row.size}`){await first.body?.cancel();throw new MediaFailure('R2 no confirmó el contenido del archivo.',502);}
 const bytes=await r2Bytes(first,64);if(bytes.length!==end+1||!mediaSignature(bytes,row.mime_type))throw new MediaFailure('El contenido no corresponde a la foto o video seleccionado.',422);return true;
}
async function publish(c:Context,row:Upload,claim:string){
 const policy=await decryptMail<{imageLimit?:number}>(row.session_payload,mailKey());if(row.mime_type.startsWith('image/')&&policy.imageLimit&&row.size>policy.imageLimit)throw new MediaFailure('La imagen supera el nivel de compresión elegido.',413);
 await parent(c,row.parent_id);await live(c);const now=new Date().toISOString();
 await database().prepare(`INSERT OR IGNORE INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,thumbnail_key,actor_id,payload_hash,created_at,modified_at) SELECT ?,?,?,?,?,?,'',?,?,?,? WHERE ${same(c)} AND ${availableSQL(row.parent_id)} AND EXISTS(SELECT 1 FROM jac_media_operations WHERE id=? AND claim=? AND connection_version=? AND status='pending')`).bind(row.drive_id,row.parent_id,row.name,row.mime_type,row.size,objectKey(row),c.g.actorID,row.payload_hash,now,now,...c.g.bindings,row.id,claim,c.config.version).run();
 const found=await entry(row.drive_id);if(found?.payload_hash!==row.payload_hash||found.object_key!==objectKey(row))throw new MediaFailure('No se pudo publicar el archivo.',409);await update(c,row,claim,row.size,'ready',row.session_payload);return state(c,(await operation(row.id))!);
}
type SinglePartReceipt={partNumber:1;etag:string;size:number};
function singlePartReceipt(input:unknown,row:Upload):SinglePartReceipt|undefined {
 if(input===undefined)return;
 if(!input||typeof input!=='object'||Array.isArray(input))throw new MediaFailure('El recibo de la parte no es válido.');
 const value=input as Record<string,unknown>;
 if(Object.keys(value).length!==3||!['partNumber','etag','size'].every(key=>Object.hasOwn(value,key))||value.partNumber!==1||typeof value.etag!=='string'||!/^"[a-f0-9]{32}"$/i.test(value.etag)||typeof value.size!=='number'||!Number.isSafeInteger(value.size)||value.size<=0)throw new MediaFailure('El recibo de la parte no es válido.');
 if(row.size>MEDIA_DIRECT_CHUNK_SIZE||value.size!==row.size||(row.status!=='ready'&&row.offset!==0))throw new MediaFailure('Este recibo no corresponde a un archivo de una sola parte.',422);
 return value as SinglePartReceipt;
}
async function completeParts(c:Context,row:Upload,id:string,parts:{number:number;etag:string}[]){
 const xml='<CompleteMultipartUpload>'+parts.map(p=>'<Part><PartNumber>'+p.number+'</PartNumber><ETag>'+xmlEscape(p.etag)+'</ETag></Part>').join('')+'</CompleteMultipartUpload>',response=await call(c,'POST',objectKey(row),{uploadId:id},{'content-type':'application/xml'},xml);await checked(response);const result=await r2XML(response);if(!result.includes('<CompleteMultipartUploadResult')||result.includes('<Error>'))throw new MediaFailure('R2 no confirmó el archivo final.',502);
}
export async function r2Status(g:MediaGuard,id:unknown,partReceipt?:unknown){
 const c=await context(g),row=await own(c,id),receipt=singlePartReceipt(partReceipt,row);if(row.status==='ready')return state(c,row);if(!row.session_payload)throw new MediaFailure('Prepara primero la subida.',409);const claim=await lock(c,row);
 try{
  if(receipt){
   // The receipt is only a completion hint. R2 must accept its real ETag, and
   // the final size/MIME/request metadata/signature still authorize publication.
   // Keep multipart: a used part capability cannot overwrite a ready original.
   try{await completeParts(c,row,await uploadID(row),[{number:receipt.partNumber,etag:receipt.etag}]);}
   catch(error){
    if(!(error instanceof MediaFailure)||![404,502,503].includes(error.status))throw error;
    // A lost completion response (or NoSuchUpload on retry) may already have
    // committed the immutable object. Recover by its server-owned key only.
    if(await finalObject(c,row))return await publish(c,row,claim);
    throw error;
   }
   if(!await finalObject(c,row))throw new MediaFailure('R2 todavía no confirmó el archivo final.',502);
   return await publish(c,row,claim);
  }
  // A successful completion whose response was lost is recovered by its fixed
  // object key and metadata, without a second file or trusting client offsets.
  if(await finalObject(c,row))return await publish(c,row,claim);
  const id=await uploadID(row),parts:{number:number;size:number;etag:string}[]=[];let marker='';
  for(let page=0;page<4;page++){
   const response=await call(c,'GET',objectKey(row),{uploadId:id,'max-parts':'1000',...(marker?{'part-number-marker':marker}:{})});await checked(response);const xml=await r2XML(response);
   for(const match of xml.matchAll(/<Part>([\s\S]*?)<\/Part>/g)){const number=Number(xmlValue(match[1],'PartNumber')),size=Number(xmlValue(match[1],'Size')),etag=xmlValue(match[1],'ETag');if(!Number.isSafeInteger(number)||!Number.isSafeInteger(size)||!/^"[a-f0-9]{32}"$/i.test(etag))throw new MediaFailure('R2 no confirmó las partes del archivo.',502);parts.push({number,size,etag});}
   if(xmlValue(xml,'IsTruncated')!=='true')break;const next=xmlValue(xml,'NextPartNumberMarker');if(!/^\d+$/.test(next)||Number(next)<=Number(marker))throw new MediaFailure('R2 no confirmó el progreso.',502);marker=next;if(page===3)throw new MediaFailure('La respuesta de R2 excede el límite.',502);
  }
  let offset=0;for(const [index,part]of parts.entries()){const expected=Math.min(MEDIA_DIRECT_CHUNK_SIZE,row.size-offset);if(part.number!==index+1||part.size!==expected||expected<=0)throw new MediaFailure('Una parte no coincide con el archivo seleccionado.',422);offset+=part.size;}
  if(offset<row.offset)throw new MediaFailure('El progreso cambió. Reintenta la subida.',409);
  if(offset===row.size){await completeParts(c,row,id,parts);if(!await finalObject(c,row))throw new MediaFailure('R2 todavía no confirmó el archivo final.',502);return await publish(c,row,claim);}
  await update(c,row,claim,offset,'pending',row.session_payload);return state(c,(await operation(row.id))!);
 }finally{await unlock(row.id,claim);}
}
export async function r2Cancel(g:MediaGuard,id:unknown){const c=await context(g),row=await own(c,id);if(row.status==='ready')return {cancelled:false};const claim=await lock(c,row);try{if(row.session_payload){const response=await call(c,'DELETE',objectKey(row),{uploadId:await uploadID(row)});if(response.status!==404)await checked(response);await response.body?.cancel();}await update(c,row,claim,row.offset,'cancelled','');return {cancelled:true};}finally{await unlock(row.id,claim);}}

// Accept a small JPEG variant, never arbitrary HTML/SVG or an oversized decoded
// raster. Originals remain unchanged. This is also used for native video covers.
export function jpegThumbnail(bytes:Uint8Array){
 if(bytes.length<10||bytes.length>MEDIA_THUMBNAIL_MAX_BYTES||!mediaSignature(bytes,'image/jpeg'))return false;
 let p=2;while(p+4<=bytes.length){if(bytes[p++]!==255)return false;let marker=bytes[p++];while(marker===255)marker=bytes[p++];if(marker===217||marker===218)return false;const length=(bytes[p]<<8)|bytes[p+1];if(length<2||p+length>bytes.length)return false;if([192,193,194].includes(marker)){const h=(bytes[p+3]<<8)|bytes[p+4],w=(bytes[p+5]<<8)|bytes[p+6];return length>=8&&w>0&&h>0&&w<=640&&h<=640;}p+=length;}return false;
}
export async function r2SaveThumbnail(g:MediaGuard,id:unknown,bytes:Uint8Array){
 if(!jpegThumbnail(bytes))throw new MediaFailure('La miniatura debe ser un JPEG de hasta 640 px y 512 KB.',422);const c=await context(g),row=await own(c,id);if(row.status!=='ready')throw new MediaFailure('Termina de subir el archivo antes de su miniatura.',409);const claim=await lock(c,row);try{const file=await entry(row.drive_id);if(!file||file.actor_id!==g.actorID)throw new MediaFailure('Este archivo no pertenece a tu subida.',403);const key='thumbnails/'+row.id.toLowerCase()+'.jpg';
 // Immutable once attached: lost responses can safely retry the same operation.
 if(file.thumbnail_key)return {saved:true};const response=await call(c,'PUT',key,{}, {'content-type':'image/jpeg'},bytes);await checked(response);await response.body?.cancel();await parent(c,row.parent_id);await live(c);
 const saved=await database().prepare(`UPDATE jac_media_r2_entries SET thumbnail_key=?,modified_at=? WHERE id=? AND thumbnail_key='' AND actor_id=? AND ${same(c)} AND ${availableSQL(row.parent_id)}`).bind(key,new Date().toISOString(),file.id,g.actorID,...g.bindings).run();if(saved.meta.changes!==1&&!((await entry(file.id))?.thumbnail_key))throw new MediaFailure('La sesión o el archivo cambió.',403);await live(c);return {saved:true};}finally{await unlock(row.id,claim);}
}

// Resumable, idempotent deletion. A durable tombstone hides the entire subtree
// before any I/O; every writer checks it in the same SQL statement as its write.
// Folder metadata is retained as a tombstone, while original/thumbnail bytes and
// file entries are removed. No S3 bucket listing or Drive operation is used.
function deletionState(row:Upload,complete=row.status==='ready',waiting=false){return {id:row.parent_id,parentId:row.drive_id,name:row.name,removed:row.offset,complete,waiting};}
async function deleteKeys(c:Context,keys:string[]){
 keys=[...new Set(keys)].filter(Boolean);if(!keys.length)return;
 if(keys.length>200||keys.some(k=>! /^(originals\/[a-f0-9-]{36}|thumbnails\/[a-f0-9-]{36}\.jpg)$/.test(k)))throw new MediaFailure('Los archivos de la carpeta no son válidos.',409);
 const body='<Delete>'+keys.map(k=>'<Object><Key>'+xmlEscape(k)+'</Key></Object>').join('')+'<Quiet>false</Quiet></Delete>';
 const response=await call(c,'POST','',{delete:''},{'content-type':'application/xml','content-md5':createHash('md5').update(body).digest('base64')},body);await checked(response);const xml=await r2XML(response);
 const confirmed=[...xml.matchAll(/<Deleted>([\s\S]*?)<\/Deleted>/g)].map(m=>xmlValue(m[1],'Key'));
 if(!/<DeleteResult(?:\s|>)/.test(xml)||/<Error(?:\s|>)/.test(xml)||confirmed.length!==keys.length||new Set(confirmed).size!==keys.length||confirmed.some(k=>!keys.includes(k)))throw new MediaFailure('R2 no confirmó todos los archivos. Reintenta la eliminación.',502);
}
export async function r2DeleteFolder(g:MediaGuard,id:unknown){
 if(typeof id!=='string'||id===R2_ROOT||id===MEDIA_ROOT_ID||!id)throw new MediaFailure('La carpeta principal de Fotografía no se puede eliminar.',400);checkedID(id);
 const c=await context(g);let job=await deletion(id);
 if(!job){
  const rows=await parent(c,id),folder=rows.at(-1);if(!folder)throw new MediaFailure('La carpeta no está disponible.',404);
  const now=new Date().toISOString();await database().prepare(`INSERT OR IGNORE INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,drive_id,name,mime_type,connection_version,created_at,expires_at) SELECT ?,?,?,?,'r2-delete-folder',?,?,?,?,?,? WHERE ${same(c)} AND ${availableSQL(id)} AND EXISTS(SELECT 1 FROM jac_media_r2_entries WHERE id=? AND mime_type=?)`).bind(deletionID(id),g.actorID,id,hash([id,c.config.version]),folder.parent_id,folder.name,MEDIA_FOLDER_MIME,c.config.version,now,'9999-12-31T00:00:00Z',...g.bindings,id,MEDIA_FOLDER_MIME).run();
  job=await deletion(id);
 }
 await live(c);if(!job||job.connection_version!==c.config.version)throw new MediaFailure('La carpeta o su conexión cambió. Actualiza Fotografía.',409);if(job.status==='ready')return deletionState(job);
 const claim=crypto.randomUUID(),claimed=await database().prepare(`UPDATE jac_media_operations SET claim=?,claim_at=? WHERE id=? AND kind='r2-delete-folder' AND status='pending' AND connection_version=? AND (claim='' OR claim_at<?) AND ${same(c)}`).bind(claim,new Date().toISOString(),job.id,c.config.version,new Date(Date.now()-180000).toISOString(),...g.bindings).run();
 if(claimed.meta.changes!==1)return deletionState(job,false,true);
 const owned=`EXISTS(SELECT 1 FROM jac_media_operations d WHERE d.id='${job.id}' AND d.kind='r2-delete-folder' AND d.status='pending' AND d.claim='${claim}' AND d.connection_version=${c.config.version})`,tree=subtree(id);
 try{
  // Let a server-side finalization already in flight release its claim first.
  // New claims/publications cannot enter the tombstoned tree.
  const busy=await database().prepare(`${tree} SELECT 1 FROM jac_media_operations WHERE kind='r2-upload' AND parent_id IN (SELECT id FROM tree) AND claim<>'' AND claim_at>? LIMIT 1`).bind(new Date(Date.now()-180000).toISOString()).first();
  if(busy)return deletionState(job,false,true);
  const pending=await database().prepare(`${tree} SELECT * FROM jac_media_operations WHERE kind='r2-upload' AND parent_id IN (SELECT id FROM tree) AND status IN ('pending','cancelled') LIMIT 4`).all<Upload>();
  for(const upload of pending.results){
   if(upload.connection_version!==c.config.version)throw new MediaFailure('Una subida pertenece a otra conexión. Revisa la carpeta antes de continuar.',409);
   await live(c);const stopped=await database().prepare(`UPDATE jac_media_operations SET status='cancelled',claim='',claim_at='' WHERE id=? AND kind='r2-upload' AND status IN ('pending','cancelled') AND ${same(c)} AND ${owned}`).bind(upload.id,...g.bindings).run();if(stopped.meta.changes!==1)throw new MediaFailure('La eliminación cambió. Reintenta.',409);
   if(upload.session_payload){const response=await call(c,'DELETE',objectKey(upload),{uploadId:await uploadID(upload)});if(response.status!==404)await checked(response);await response.body?.cancel();}
   await deleteKeys(c,[objectKey(upload),'thumbnails/'+upload.id.toLowerCase()+'.jpg']);
   await database().prepare(`UPDATE jac_media_operations SET status='deleted',session_payload='' WHERE id=? AND kind='r2-upload' AND status='cancelled' AND ${same(c)} AND ${owned}`).bind(upload.id,...g.bindings).run();await live(c);
  }
  const files=await database().prepare(`${tree} SELECT * FROM jac_media_r2_entries WHERE id IN (SELECT id FROM tree) AND mime_type<>? LIMIT 100`).bind(MEDIA_FOLDER_MIME).all<Entry>();
  if(files.results.length){
   for(const file of files.results){checkedID(file.id);const uuid=file.id.slice(3);if(file.object_key!=='originals/'+uuid||file.thumbnail_key&&file.thumbnail_key!=='thumbnails/'+uuid+'.jpg')throw new MediaFailure('El contenido de la carpeta cambió. Revisa antes de continuar.',409);}
   await deleteKeys(c,files.results.flatMap(f=>[f.object_key,'thumbnails/'+f.id.slice(3)+'.jpg']));await live(c);
   // Each ID and key is server-observed; guard the catalogue removal too.
   const placeholders=files.results.map(()=>'?').join(','),removed=await database().prepare(`DELETE FROM jac_media_r2_entries WHERE id IN (${placeholders}) AND mime_type<>? AND ${same(c)} AND ${owned}`).bind(...files.results.map(f=>f.id),MEDIA_FOLDER_MIME,...g.bindings).run();
   const saved=await database().prepare(`UPDATE jac_media_operations SET offset=offset+? WHERE id=? AND claim=? AND ${same(c)}`).bind(removed.meta.changes,job.id,claim,...g.bindings).run();if(saved.meta.changes!==1)throw new MediaFailure('La sesión cambió durante la eliminación.',403);
  }
  const left=await database().prepare(`${tree} SELECT 1 FROM jac_media_r2_entries WHERE id IN (SELECT id FROM tree) AND mime_type<>? UNION ALL SELECT 1 FROM jac_media_operations WHERE kind='r2-upload' AND parent_id IN (SELECT id FROM tree) AND status IN ('pending','cancelled') LIMIT 1`).bind(MEDIA_FOLDER_MIME).first();
  if(!left){await database().prepare(`UPDATE jac_media_operations SET status='ready' WHERE id=? AND claim=? AND ${same(c)}`).bind(job.id,claim,...g.bindings).run();}
  await live(c);const result=await deletion(id);if(!result)throw new MediaFailure('No se pudo confirmar la eliminación.',409);return deletionState(result);
 }finally{await unlock(job.id,claim);}
}
