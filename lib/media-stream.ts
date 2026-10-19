import {env} from 'cloudflare:workers';
import {database} from '@/db/raw';
import {MediaFailure} from './media-core';
import {mediaGuardActive,mediaStoredGuard,type MediaGuard} from './media-drive';
import {r2PresentationSource} from './media-r2-gallery';
import {ensurePresentations,presentation,type MediaPresentation} from './media-presentation-store';
import {r2Bytes,r2SourceURL} from './media-r2-s3';
import {encryptMail,decryptMail} from './payroll-mail-core';
import {mailKey} from './payroll-mail';
import {sharedPlaybackGuard} from './media-folder-shares';
import {sectionSql} from './payroll-permissions';

const ACCOUNT='9798d1043d57690ffa9aee16c74dfb93';
const settings=()=>env as unknown as {JAC_STREAM_API_TOKEN?:string};
const configured=()=>!!settings().JAC_STREAM_API_TOKEN;
class StreamFailure extends MediaFailure {constructor(public uncertain:boolean,public upstreamStatus=0,public upstreamCode=0){super(upstreamStatus===401||upstreamStatus===403?'Cloudflare Stream rechazó su credencial. Revisa el permiso Stream: Edit y la cuenta configurada.':'Cloudflare Stream no confirmó la preparación. Revisa su configuración o reintenta más tarde.',503);}}
async function streamAPI(path:string,body?:unknown,method=body?'POST':'GET'){
 const token=settings().JAC_STREAM_API_TOKEN;if(!token)throw new MediaFailure('Falta configurar Cloudflare Stream.',503);
 let response:Response;
 try{response=await fetch('https://api.cloudflare.com/client/v4/accounts/'+ACCOUNT+'/stream'+path,{method,redirect:'manual',headers:{Authorization:'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});}catch{throw new StreamFailure(method==='POST');}
 const bytes=await r2Bytes(response,2*1024*1024);let data:{success?:boolean;result?:unknown;errors?:{code?:number}[]};try{data=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new StreamFailure(method==='POST',response.status);}
 if(!response.ok||data.success===false)throw new StreamFailure(method==='POST'&&response.status>=500,response.status,Number(data.errors?.[0]?.code)||0);
 return data.result;
}
type StreamVideo={uid:string;readyToStream?:boolean;status?:{state?:string};meta?:{jac_source?:string};playback?:{hls?:string}};
const validHost=(host:string)=>/(^|\.)(videodelivery\.net|cloudflarestream\.com)$/.test(host);
function deliveryHost(video:StreamVideo){
 if(!video.playback?.hls)return 'videodelivery.net';
 const url=new URL(video.playback.hls);if(url.protocol!=='https:'||url.username||url.password||url.port||!validHost(url.hostname)||url.pathname.split('/')[1]!==video.uid)throw new MediaFailure('Stream devolvió una dirección no válida.',502);
 return url.hostname;
}
const uidValid=(uid:unknown):uid is string=>typeof uid==='string'&&/^[a-f0-9]{32}$/.test(uid);
function creator(id:string,version:number){return 'jac-'+id+'-v'+version;}
async function active(g:MediaGuard,id:string,revision?:string){const source=await r2PresentationSource(g,id);if(revision&&source.item.modifiedAt!==revision)throw new MediaFailure('El archivo cambió. Actualiza la carpeta.',409);return source;}
async function prepareVideo(g:MediaGuard,id:string){
 const source=await active(g,id);if(source.item.kind!=='video')throw new MediaFailure('Selecciona un video.');
 await ensurePresentations(g);const now=new Date().toISOString();
 await database().prepare(`INSERT OR IGNORE INTO jac_media_presentations(file_id,source_key,connection_version,updated_at) SELECT ?,?,?,? WHERE ${g.sql}`).bind(id,source.key,source.version,now,...g.bindings).run();
 let row=await presentation(id);if(!row||row.source_key!==source.key||row.connection_version!==source.version)throw new MediaFailure('La colección cambió.',409);
 if(row.stream_uid){
  if(row.stream_status==='ready'||row.stream_status==='error')return row;
  const video=await streamAPI('/'+row.stream_uid) as StreamVideo;await active(g,id);
  const state=video.readyToStream?'ready':video.status?.state==='error'?'error':'processing';
  await database().prepare(`UPDATE jac_media_presentations SET stream_status=?,stream_host=?,updated_at=? WHERE file_id=? AND stream_uid=? AND ${g.sql}`).bind(state,deliveryHost(video),now,id,row.stream_uid,...g.bindings).run();return {...row,stream_status:state,stream_host:deliveryHost(video)};
 }
 if(!configured())return row;
 const claim=crypto.randomUUID();const lock=await database().prepare(`UPDATE jac_media_presentations SET claim=?,claim_at=?,updated_at=? WHERE file_id=? AND stream_uid='' AND (claim='' OR claim_at<?) AND ${g.sql}`).bind(claim,now,now,id,new Date(Date.now()-180000).toISOString(),...g.bindings).run();
 if(lock.meta.changes!==1)return row;
 let copying=false;
 try{
  // Reconcile an interrupted copy by its stable creator before another POST.
  const known=await streamAPI('?creator='+encodeURIComponent(creator(id,source.version))) as StreamVideo[];
  let video=Array.isArray(known)?known.find(value=>uidValid(value.uid)&&value.meta?.jac_source===source.key):undefined;
  if(!video&&row.stream_status==='uncertain')return row;
  if(!video){copying=true;await active(g,id);video=await streamAPI('/copy',{url:r2SourceURL(source.secret,source.key),requireSignedURLs:true,creator:creator(id,source.version),meta:{name:id,jac_source:source.key}}) as StreamVideo;}
  if(!uidValid(video.uid))throw new StreamFailure(copying);
  await active(g,id);const state=video.readyToStream?'ready':'processing';
  const saved=await database().prepare(`UPDATE jac_media_presentations SET stream_uid=?,stream_status=?,stream_host=?,claim='',updated_at=? WHERE file_id=? AND claim=? AND source_key=? AND connection_version=? AND ${g.sql}`).bind(video.uid,state,deliveryHost(video),now,id,claim,source.key,source.version,...g.bindings).run();
  if(saved.meta.changes!==1){await streamAPI('/'+video.uid,undefined,'DELETE').catch(()=>{});throw new MediaFailure('Tu sesión o el video cambió.',403);}
  row={...row,stream_uid:video.uid,stream_status:state,stream_host:deliveryHost(video)};return row;
 }catch(error){
  const state=error instanceof StreamFailure&&error.uncertain?'uncertain':row.stream_status;
  await database().prepare('UPDATE jac_media_presentations SET stream_status=? WHERE file_id=? AND claim=?').bind(state,id,claim).run();throw error;
 }finally{await database().prepare("UPDATE jac_media_presentations SET claim='' WHERE file_id=? AND claim=?").bind(id,claim).run();}
}

type Lease={v:1;id:string;revision:string;version:number;expires:number;actorID?:string;sessionID?:string;share?:string};
export async function playbackInfo(g:MediaGuard,id:string,origin:string,authorization:{share:string}|{actorID:string;sessionID:string},mayPrepare=false){
 const source=await active(g,id);if(source.item.kind!=='video')throw new MediaFailure('Selecciona un video.');
 let row:MediaPresentation|null;
 try{row=mayPrepare&&configured()?await prepareVideo(g,id):await presentation(id);}catch(error){if(error instanceof StreamFailure)return {ready:false,status:'configuration',message:error.message};throw error;}
 await active(g,id);
 if(!row||row.connection_version!==source.version||row.source_key!==source.key||row.stream_status!=='ready'||!uidValid(row.stream_uid))return {ready:false,status:!configured()?'configuration':row?.stream_status||'preparing',message:!configured()?'La reproducción adaptativa está pendiente de configurar.':'Preparando la versión para reproducción. Puedes descargar el archivo completo.'};
 const lease:Lease={v:1,id,revision:source.item.modifiedAt,version:source.version,expires:Date.now()+3600000,...authorization};
 const token=await encryptMail(lease,mailKey());const url=new URL('/api/media/playback',origin);url.searchParams.set('lease',token);url.searchParams.set('asset','manifest/video.m3u8');
 return {ready:true,status:'ready',url:url.toString()};
}
async function leaseGuard(token:string){
 if(!token||token.length>8192)throw new MediaFailure('La reproducción venció.',403);
 let lease:Lease;try{lease=await decryptMail<Lease>(token,mailKey());}catch{throw new MediaFailure('La reproducción no es válida.',403);}
 if(lease.v!==1||!Number.isFinite(lease.expires)||lease.expires<Date.now()||lease.expires>Date.now()+3600001||typeof lease.id!=='string')throw new MediaFailure('La reproducción venció. Abre de nuevo el video.',403);
 const g=lease.share?await sharedPlaybackGuard(lease.share,lease.id):lease.actorID&&/^[a-f0-9]{64}$/.test(lease.sessionID||'')?mediaStoredGuard(lease.sessionID!,lease.actorID):null;
 if(!g||!await mediaGuardActive(g))throw new MediaFailure('La sesión o los permisos cambiaron.',403);
 // A single bounded SQL check revalidates the source, ancestors, tombstones,
 // session/share and collection. Playback never decrypts R2 credentials.
 const row=await database().prepare(`WITH RECURSIVE ancestors(id,parent_id,mime_type,depth) AS (
 SELECT id,parent_id,mime_type,0 FROM jac_media_r2_entries WHERE id=?
 UNION ALL SELECT e.id,e.parent_id,e.mime_type,a.depth+1 FROM jac_media_r2_entries e JOIN ancestors a ON e.id=a.parent_id WHERE a.depth<24)
 SELECT p.stream_uid,p.stream_host FROM jac_media_r2_entries e JOIN jac_media_presentations p ON p.file_id=e.id AND p.source_key=e.object_key
 JOIN jac_media_r2_connection c ON c.id='jac' AND c.enabled=1 AND c.version=p.connection_version
 WHERE e.id=? AND e.modified_at=? AND e.mime_type LIKE 'video/%' AND p.connection_version=? AND p.stream_status='ready'
 AND EXISTS(SELECT 1 FROM ancestors WHERE parent_id='jac_r2_root')
 AND NOT EXISTS(SELECT 1 FROM ancestors WHERE depth>0 AND mime_type<>'application/vnd.google-apps.folder')
 AND NOT EXISTS(SELECT 1 FROM ancestors a JOIN jac_media_operations d ON d.id='r2-delete:'||a.id AND d.kind IN ('r2-delete-folder','r2-delete-file')) AND ${g.sql}`).bind(lease.id,lease.id,lease.revision,lease.version,...g.bindings).first<{stream_uid:string;stream_host:string}>();
 if(!row||!uidValid(row.stream_uid)||!validHost(row.stream_host))throw new MediaFailure('El video dejó de estar disponible.',403);
 return {g,lease,uid:row.stream_uid,host:row.stream_host};
}
const signed=new Map<string,{token:string;expires:number}>();
async function streamToken(uid:string){
 const old=signed.get(uid);if(old&&old.expires>Date.now())return old.token;
 const result=await streamAPI('/'+uid+'/token',{exp:Math.floor(Date.now()/1000)+120}) as {token?:string};
 if(!result.token||!/^[-A-Za-z0-9_.]+$/.test(result.token))throw new MediaFailure('Stream no confirmó la reproducción.',502);
 if(signed.size>=128)signed.delete(signed.keys().next().value!);signed.set(uid,{token:result.token,expires:Date.now()+90000});return result.token;
}
function assetPath(asset:string){
 if(!asset||asset.length>2048||asset.startsWith('/')||asset.includes('\\')||asset.includes('#')||asset.split(/[/?]/).some(x=>x==='.'||x==='..')||!(/^(manifest|video|audio|segments)\//.test(asset)))throw new MediaFailure('El tramo no es válido.',400);
 return asset;
}
export async function playbackAsset(lease:string,asset:string,range:string|null){
 assetPath(asset);const access=await leaseGuard(lease),token=await streamToken(access.uid),remote=new URL('https://'+access.host+'/'+token+'/'+asset);
 if(range&&!/^bytes=\d+-\d*$/.test(range))throw new MediaFailure('Rango no válido.',416);
 const response=await fetch(remote,{redirect:'manual',headers:range?{Range:range}:{},signal:AbortSignal.timeout(30000)});
 if(!response.ok||response.status>=300){await response.body?.cancel();throw new MediaFailure('Cloudflare no entregó la reproducción (HTTP '+response.status+').',502);}
 await leaseGuard(lease);const headers=new Headers({'Cache-Control':'private, no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'});
 if(remote.pathname.endsWith('.m3u8')){
  const text=new TextDecoder().decode(await r2Bytes(response,1024*1024));if(!text.startsWith('#EXTM3U'))throw new MediaFailure('Stream no devolvió una lista de reproducción.',502);
  const rewrite=(value:string)=>{const url=new URL(value,remote);if(url.protocol!=='https:'||url.username||url.password||url.port||!(/(^|\.)(videodelivery\.net|cloudflarestream\.com)$/.test(url.hostname)))throw new MediaFailure('La lista contiene un destino no autorizado.',502);const parts=url.pathname.split('/').filter(Boolean);if(![token,access.uid].includes(parts.shift()||''))throw new MediaFailure('La lista cambió de video.',502);for(const [name,value] of [...url.searchParams])if(/token|auth|signature|^sig$|jwt/i.test(name)||value===token)url.searchParams.delete(name);const path=assetPath(parts.join('/')+url.search);return '/api/media/playback?'+new URLSearchParams({lease,asset:path});};
  const playlist=text.split('\n').map(line=>line.startsWith('#')?line.replace(/URI="([^"]+)"/g,(_,uri)=>'URI="'+rewrite(uri)+'"'):line.trim()?rewrite(line.trim()):line).join('\n');
  await leaseGuard(lease);headers.set('Content-Type','application/vnd.apple.mpegurl');return new Response(playlist,{headers});
 }
 for(const key of ['content-type','content-length','content-range','accept-ranges']){const value=response.headers.get(key);if(value)headers.set(key,value);}
 const reader=response.body?.getReader();if(!reader)throw new MediaFailure('El tramo está vacío.',502);
 let received=0,last=Date.now();
 return new Response(new ReadableStream({async pull(controller){try{const part=await reader.read();if(part.done){await leaseGuard(lease);controller.close();return;}received+=part.value.byteLength;if(received>=1024*1024||Date.now()-last>=5000){await leaseGuard(lease);received=0;last=Date.now();}controller.enqueue(part.value);}catch(error){await reader.cancel().catch(()=>{});controller.error(error);}},async cancel(){await reader.cancel();}}),{status:response.status,headers});
}

// Read-only incident diagnosis, reachable exclusively through the owner's
// existing connect guard. Return counts and sanitized stage outcomes, never
// credentials, signed delivery URLs, manifests, filenames or source bytes.
export async function playbackDiagnostics(g:MediaGuard,origin:string){
 if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión cambió.',403);
 type Stage={ok:boolean;status?:number;code?:number;message?:string};
 const failure=(error:unknown):Stage=>({ok:false,...(error instanceof StreamFailure?{status:error.upstreamStatus,code:error.upstreamCode}:{}),message:error instanceof MediaFailure?error.message:'No se pudo consultar esta etapa.'});
 const report:{configured:boolean;checkedAt:string;videos:number;states:{state:string;count:number}[];api?:Stage;provider?:{state:string;ready:boolean};master?:Stage;variant?:Stage}={configured:configured(),checkedAt:new Date().toISOString(),videos:0,states:[]};
 report.videos=(await database().prepare(`SELECT COUNT(*) AS n FROM jac_media_r2_entries WHERE mime_type LIKE 'video/%' AND ${g.sql}`).bind(...g.bindings).first<{n:number}>())?.n||0;
 const exists=await database().prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='jac_media_presentations'").first();
 if(exists)report.states=(await database().prepare(`SELECT COALESCE(NULLIF(p.stream_status,''),'pending') AS state,COUNT(*) AS count FROM jac_media_r2_entries e LEFT JOIN jac_media_presentations p ON p.file_id=e.id WHERE e.mime_type LIKE 'video/%' AND ${g.sql} GROUP BY state`).bind(...g.bindings).all<{state:string;count:number}>()).results;
 if(report.configured){try{await streamAPI('?limit=1');report.api={ok:true,status:200};}catch(error){report.api=failure(error);}}
 if(report.api?.ok&&exists){
  const candidate=await database().prepare(`SELECT p.file_id,p.stream_uid FROM jac_media_presentations p JOIN jac_media_r2_entries e ON e.id=p.file_id WHERE p.stream_uid<>'' AND e.mime_type LIKE 'video/%' AND ${g.sql} ORDER BY (p.stream_status='ready') DESC,p.updated_at DESC LIMIT 1`).bind(...g.bindings).first<{file_id:string;stream_uid:string}>();
  if(candidate){
   try{const video=await streamAPI('/'+candidate.stream_uid) as StreamVideo;report.provider={state:/^[a-zA-Z0-9_-]{1,40}$/.test(video.status?.state||'')?video.status!.state!:'unknown',ready:video.readyToStream===true};}catch(error){report.api=failure(error);}
   const inspect=async(url:string)=>{const q=new URL(url,origin).searchParams;const response=await playbackAsset(q.get('lease')||'',q.get('asset')||'',null);return new TextDecoder().decode(await r2Bytes(response,1024*1024));};
   try{
    const sessionID=String(g.bindings[0]),info=await playbackInfo(g,candidate.file_id,origin,{actorID:g.actorID,sessionID},false);
    if(info.ready&&info.url){const master=await inspect(info.url);report.master={ok:true,status:200};const child=master.split('\n').find(line=>line.startsWith('/api/media/playback?'));if(child){try{await inspect(child);report.variant={ok:true,status:200};}catch(error){report.variant=failure(error);}}}
    else report.master={ok:false,message:'La versión todavía no figura lista en JAC.'};
   }catch(error){report.master=failure(error);}
  }
 }
 if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión cambió.',403);
 return report;
}

// Internal scheduled work only. This guard is never accepted from HTTP input
// and does not create a user's session or expose a capability to a caller.
export async function processMediaPresentations(){
 if(!configured())return;
 const g:MediaGuard={actorID:'service:stream',bindings:[],sql:`EXISTS(SELECT 1 FROM payroll_users pu WHERE pu.active=1 AND ${sectionSql('pu','crm')} AND ${sectionSql('pu','media')})`};
 if(!await mediaGuardActive(g))return;await ensurePresentations(g);
 const removed=await database().prepare("SELECT p.* FROM jac_media_presentations p LEFT JOIN jac_media_r2_entries e ON e.id=p.file_id WHERE e.id IS NULL LIMIT 4").all<MediaPresentation>();
 for(const row of removed.results){try{if(row.stream_uid)await streamAPI('/'+row.stream_uid,undefined,'DELETE');await database().prepare('DELETE FROM jac_media_presentations WHERE file_id=? AND stream_uid=?').bind(row.file_id,row.stream_uid).run();}catch{/* Retry bounded cleanup on the next scheduled run. */}}
 const rows=await database().prepare("SELECT e.id FROM jac_media_r2_entries e LEFT JOIN jac_media_presentations p ON p.file_id=e.id WHERE e.mime_type LIKE 'video/%' AND (p.file_id IS NULL OR p.stream_status NOT IN ('ready','error')) AND NOT EXISTS(WITH RECURSIVE ancestors(id) AS (SELECT e.id UNION SELECT parent_id FROM jac_media_r2_entries JOIN ancestors ON jac_media_r2_entries.id=ancestors.id WHERE ancestors.id<>'jac_r2_root') SELECT 1 FROM ancestors JOIN jac_media_operations d ON d.parent_id=ancestors.id AND d.kind IN ('r2-delete-folder','r2-delete-file')) ORDER BY COALESCE(p.updated_at,'1970') ASC,e.created_at DESC,e.id LIMIT 1").all<{id:string}>();
 for(const row of rows.results){try{await prepareVideo(g,row.id);}catch{/* No credentials, signed sources or user filenames in logs. */}}
}
