import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {readFile,readdir} from 'node:fs/promises';

// Workerd executes the real media API and D1 guards. All Google traffic terminates
// in outboundService; no credentials, photos, videos or accounts are real.
const root='1yH4pNYQxArfynzho-IPBtx5w4AWbQ-C5',folderID='fixture_worker_folder',fileID='fixture_worker_file',outsideID='fixture_worker_outside',folderMime='application/vnd.google-apps.folder',chunkSize=1024*1024;
const scope='https://www.googleapis.com/auth/drive',base='https://media-worker.example.invalid';
const ownerID='11111111-1111-4111-8111-111111111111',photoID='22222222-2222-4222-8222-222222222222',readerID='33333333-3333-4333-8333-333333333333';
const tokens={owner:Buffer.alloc(32,1).toString('base64url'),photo:Buffer.alloc(32,2).toString('base64url'),reader:Buffer.alloc(32,3).toString('base64url')};
const tokenHash=s=>createHash('sha256').update(s).digest('hex');
const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
 import * as media from './app/api/media/route';
 import * as upload from './app/api/media/upload/route';
 import * as file from './app/api/media/file/route';
 import * as storage from './app/api/media/storage/route';
 import {ensureMediaConfig,mediaStoredGuard,storeMediaConnection} from './lib/media-drive';
 export default {async fetch(req:Request){
  globalThis.__mfMediaHeaders=new Headers(req.headers);globalThis.__mfMediaHeaders.set("host","media-worker.example.invalid");
  const path=new URL(req.url).pathname;
  if(path==='/init'){const config=await ensureMediaConfig();await storeMediaConnection({clientId:'fixture.apps.googleusercontent.com',clientSecret:'fixture-secret',refreshToken:'fixture-refresh',scopes:['${scope}']},config.version,mediaStoredGuard('${tokenHash(tokens.owner)}','${ownerID}','connect'));return Response.json({ok:true});}
  if(path==='/api/media/upload')return req.method==='PUT'?upload.PUT(req):upload.POST(req);
  if(path==='/api/media/file')return file.GET(req);
  if(path==='/api/media/storage')return req.method==='GET'?storage.GET(req):storage.POST(req);
  return req.method==='GET'?media.GET(req):media.POST(req);
 }};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*'],plugins:[{name:'mock-request-headers',setup(b){b.onResolve({filter:/^next\/headers$/},()=>({path:'headers',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const headers=async()=>globalThis.__mfMediaHeaders;',loader:'js'}));}}]});
async function fixture({readyFile=false,omitFileParents=false,readerPermissions=[]}={}){
 const state={offset:readyFile?13:0,size:readyFile?13:chunkSize+13,metadata:readyFile?{id:fileID,name:"Foto 'ficticia' \\ local.png",mimeType:'image/png',parents:[folderID]}:null,calls:[],redirect:false,revoke:null,omitFileParents,listedID:fileID,afterRead:null,afterThumbnail:null,thumbnailSize:4,thumbnailRedirect:false,listPages:null};
 const metadata=id=>id===root?{id,name:'Raíz ficticia',mimeType:folderMime,parents:[],capabilities:{canAddChildren:true}}:id===folderID?{id,name:'2026-10-16 · Show ficticio',mimeType:folderMime,parents:[root],createdTime:'2026-10-16T00:00:00Z',capabilities:{canAddChildren:true}}:id===outsideID?{id,name:'Fuera de Fotografía JAC',mimeType:folderMime,parents:[]}:id===fileID&&state.offset===state.size?{...state.metadata,size:String(state.size),createdTime:'2026-10-16T01:00:00Z',thumbnailLink:'https://lh3.googleusercontent.com/worker-preview=s220',capabilities:{canDownload:true}}:null;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-media-worker'},bindings:{PAYROLL_AUTH_KEY:'fixture-workerd-independent-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')},outboundService:async req=>{
  const url=new URL(req.url);assert.ok(['https://oauth2.googleapis.com','https://www.googleapis.com','https://lh3.googleusercontent.com','https://'+'1'.repeat(32)+'.r2.cloudflarestorage.com'].includes(url.origin),'The worker must never reach an external destination or redirect');
  const entry={url:req.url,method:req.method,authorization:req.headers.get('authorization'),range:req.headers.get('content-range'),requestedRange:req.headers.get('range'),accept:req.headers.get('accept'),bytes:new Uint8Array(await req.arrayBuffer())};state.calls.push(entry);
  if(url.hostname.endsWith('.r2.cloudflarestorage.com')){
   assert.match(req.headers.get('authorization'),/^AWS4-HMAC-SHA256 Credential=/);assert.equal(req.headers.get('cookie'),null);
   if(state.r2Redirect)return new Response(null,{status:307,headers:{location:'https://untrusted.example.invalid/collect'}});
   state.s3 ??= {parts:new Map(),objects:new Map()};const s3=state.s3,key=url.pathname.slice('/jac-fotografia/'.length),uploadID=url.searchParams.get('uploadId');
   if(url.pathname==='/jac-fotografia'){assert.equal(req.method,'HEAD');return new Response(null);}
   if(req.method==='POST'&&url.searchParams.has('uploads')){s3.key=key;s3.mime=req.headers.get('content-type');s3.id=req.headers.get('x-amz-meta-jac-request');return new Response('<InitiateMultipartUploadResult><UploadId>worker-r2-fixture</UploadId></InitiateMultipartUploadResult>');}
   if(uploadID&&req.method==='GET')return new Response('<ListPartsResult><IsTruncated>false</IsTruncated>'+[...s3.parts].map(([n,b])=>'<Part><PartNumber>'+n+'</PartNumber><Size>'+b.length+'</Size><ETag>"'+'a'.repeat(32)+'"</ETag></Part>').join('')+'</ListPartsResult>');
   if(uploadID&&req.method==='POST'){assert.equal(key,s3.key);s3.objects.set(key,{bytes:s3.parts.get(1),mime:s3.mime,id:s3.id});return new Response('<CompleteMultipartUploadResult><Key>'+key+'</Key></CompleteMultipartUploadResult>');}
   if(req.method==='PUT'){s3.objects.set(key,{bytes:entry.bytes,mime:req.headers.get('content-type')});return new Response(null);}
   const object=s3.objects.get(key);if(!object)return new Response(null,{status:404});const headers={'content-type':object.mime,'content-length':String(object.bytes.length),...(object.id?{'x-amz-meta-jac-request':object.id}:{})};
   if(req.method==='HEAD')return new Response(null,{headers});
   if(req.method==='GET'){if(state.afterR2Read)await state.afterR2Read();const match=req.headers.get('range')?.match(/^bytes=(\d+)-(\d+)$/);if(match){const a=Number(match[1]),b=Number(match[2]);return new Response(object.bytes.slice(a,b+1),{status:206,headers:{...headers,'content-length':String(b-a+1),'content-range':`bytes ${a}-${b}/${object.bytes.length}`}});}return new Response(object.bytes,{headers});}
   throw new Error('Unrecognized simulated R2 request');
  }
  if(url.origin==='https://oauth2.googleapis.com'){assert.equal(req.method,'POST');return Response.json({access_token:'fixture-worker-access'});}
  assert.equal(req.headers.get('authorization'),'Bearer fixture-worker-access');
  if(url.origin==='https://lh3.googleusercontent.com'){
   assert.equal(url.pathname,'/worker-preview=s320');if(state.thumbnailRedirect)return new Response(null,{status:307,headers:{Location:'https://untrusted.example.invalid/collect'}});
   if(state.afterThumbnail)await state.afterThumbnail();const bytes=new Uint8Array(state.thumbnailSize);bytes.set([255,216,255,1].slice(0,bytes.length));return new Response(bytes,{headers:{'Content-Type':'image/jpeg','Content-Length':String(bytes.length)}});
  }
  if(url.pathname==='/drive/v3/files/root')return Response.json({id:'worker_my_drive_root'});
  if(url.pathname==='/drive/v3/files/generateIds')return Response.json({ids:[fileID]});
  if(url.pathname==='/upload/drive/v3/files'&&req.method==='POST'){state.metadata=JSON.parse(new TextDecoder().decode(entry.bytes));state.size=Number(req.headers.get('x-upload-content-length'));return new Response(null,{headers:{Location:'https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture-worker-session'}});}
  if(url.pathname==='/upload/drive/v3/files'&&req.method==='PUT'){
   if(entry.range.startsWith('bytes */'))return state.offset===state.size?Response.json(metadata(fileID)):new Response(null,{status:308,headers:state.offset?{Range:'bytes=0-'+(state.offset-1)}:{}});
   const match=entry.range.match(/^bytes (\d+)-(\d+)\/(\d+)$/);assert.ok(match);const start=Number(match[1]),end=Number(match[2]);assert.equal(start,state.offset);assert.equal(Number(match[3]),state.size);assert.equal(entry.bytes.length,end-start+1);state.offset=end+1;if(state.revoke)await state.revoke();
   return state.offset===state.size?Response.json(metadata(fileID),{status:201}):new Response(null,{status:308,headers:{Range:'bytes=0-'+(state.offset-1)}});
  }
  if(url.pathname==='/drive/v3/files'&&req.method==='GET'){
   const file=metadata(fileID),q=url.searchParams.get('q');
   assert.equal(url.searchParams.get('supportsAllDrives'),'true');assert.equal(url.searchParams.get('includeItemsFromAllDrives'),'true');
   const escapedName=file?.name.replace(/\\/g,'\\\\').replace(/'/g,"\\'");
   const ordinary="'"+folderID+"' in parents and trashed=false and (mimeType='"+folderMime+"' or mimeType contains 'image/' or mimeType contains 'video/')",targeted="'"+folderID+"' in parents and name = '"+escapedName+"' and trashed=false";
   assert.ok(q===ordinary||q===targeted,'Every photo lookup must be constrained to its server-observed folder');
   if(q===ordinary&&state.listPages){assert.equal(url.searchParams.get('orderBy'),'folder,createdTime desc,name');assert.match(url.searchParams.get('fields'),/createdTime/);const token=url.searchParams.get('pageToken')||'';assert.ok(token in state.listPages);return Response.json(state.listPages[token]);}
   return Response.json({files:file?.parents?.includes(folderID)?[{...file,id:state.listedID}]:[]});
  }
  const id=url.pathname.split('/').at(-1),value=metadata(id);if(!value)return new Response(null,{status:404});if(req.method==='PATCH'){state.metadata.parents=[url.searchParams.get('addParents')];return Response.json(metadata(id));}
  if(url.searchParams.get('alt')==='media'){
   if(state.redirect)return new Response(null,{status:307,headers:{Location:'https://untrusted.example.invalid/collect'}});
   if(state.afterRead)await state.afterRead();
   const range=req.headers.get('range');if(range&&state.metadata?.appProperties?.jac_media_staged==='1'){assert.equal(range,'bytes=0-12');const bytes=new Uint8Array(13);bytes.set([137,80,78,71,13,10,26,10]);return new Response(bytes,{status:206,headers:{'content-type':'image/png','content-range':'bytes 0-12/13'}});}
   if(range){assert.equal(range,'bytes=2-5');return new Response(new Uint8Array([1,2,3,4]),{status:206,headers:{'content-type':'image/png','content-range':'bytes 2-5/'+state.size,'content-length':'4'}});}
   return new Response(new Uint8Array(state.size),{headers:{'content-type':'image/png','content-length':String(state.size)}});
  }
  if(state.omitFileParents&&id===fileID){const {parents,...withoutParents}=value;return Response.json(withoutParents);}
  return Response.json(value);
 }});
 const db=await mf.getD1Database('DB');for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
 for(const [role,id] of [['owner',ownerID],['photo',photoID],['reader',readerID]]){
  await db.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,owner,permissions,media_only,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)').bind(id,role+'-fixture',role==='owner'?'camilo@mac2you.co':role+'@example.invalid',role+' ficticio','fixture',Number(role==='owner'),JSON.stringify(role==='reader'?readerPermissions:[]),Number(role==='photo'),'fixture','fixture').run();
  await db.prepare('INSERT INTO payroll_sessions(id,user_id,user_version,expires_at,persistent) VALUES (?,?,1,?,1)').bind(tokenHash(tokens[role]),id,'').run();
 }
 const call=(path,{role='photo',method='GET',body,headers={}}={})=>mf.dispatchFetch(base+path,{method,headers:{origin:base,cookie:'__Host-jac_session='+tokens[role],...headers},...(body!==undefined?{body}: {})});
 assert.equal((await call('/init',{role:'owner',method:'POST'})).status,200);
 return {mf,db,state,call};
}
async function listReadyFile({db,call}){
 const response=await call('/api/media?folder='+folderID,{role:'reader'});assert.equal(response.status,200);const feed=await response.json();assert.equal(feed.folder.id,folderID);assert.deepEqual(feed.items.map(item=>item.id),[fileID]);
 const location=await db.prepare('SELECT parent_id,connection_version FROM jac_media_locations WHERE file_id=?').bind(fileID).first(),connection=await db.prepare("SELECT version FROM jac_media_connection WHERE id='jac'").first();
 assert.equal(location?.parent_id,folderID);assert.equal(location.connection_version,connection.version);
}
test('Workerd signs R2 requests, stores only encrypted staged credentials, and rejects redirected or unauthorized saves',async()=>{
 const {mf,db,state,call}=await fixture();try{
  const body=JSON.stringify({accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64),version:0});
  const before=await db.prepare("SELECT credentials FROM jac_media_connection WHERE id='jac'").first();
  assert.equal((await call('/api/media/storage',{method:'POST',body})).status,403);
  state.r2Redirect=true;assert.equal((await call('/api/media/storage',{role:'owner',method:'POST',body})).status,502);assert.equal(await db.prepare('SELECT * FROM jac_media_r2_connection').first(),null);
  state.r2Redirect=false;const response=await call('/api/media/storage',{role:'owner',method:'POST',body});assert.equal(response.status,200);const data=await response.json();assert.equal(data.active,false);assert.equal(data.configured,true);assert.ok(!JSON.stringify(data).includes('3'.repeat(64)));
  const saved=await db.prepare('SELECT * FROM jac_media_r2_connection').first();assert.ok(saved.credentials&&!saved.credentials.includes('3'.repeat(64)));assert.equal(saved.enabled,0);
  assert.deepEqual(await db.prepare("SELECT credentials FROM jac_media_connection WHERE id='jac'").first(),before);
  assert.equal((await call('/api/media/storage',{role:'reader'})).status,403);assert.equal((await call('/api/media/storage',{role:'owner',method:'POST',body})).status,409);
  assert.ok(state.calls.every(c=>!c.url.includes('untrusted')));
 }finally{await mf.dispose();}
});
test('Workerd/D1 resumes binary chunks through manual Google 308 and serves private video/photo ranges',async()=>{
 const {mf,state,call}=await fixture();try{
  const id=crypto.randomUUID(),record={action:'start',id,parentId:folderID,filename:'foto-ficticia.png',mimeType:'image/png',size:chunkSize+13};
  const start=await call('/api/media/upload',{method:'POST',body:JSON.stringify(record)});assert.equal(start.status,200);assert.equal((await start.json()).offset,0);
  const first=new Uint8Array(chunkSize);first.set([137,80,78,71,13,10,26,10]);let response=await call('/api/media/upload?id='+id+'&offset=0',{method:'PUT',body:first});assert.equal(response.status,200);assert.deepEqual(await response.json(),{id,offset:chunkSize,chunkSize,complete:false});
  response=await call('/api/media/upload',{method:'POST',body:JSON.stringify({action:'status',id})});assert.equal(response.status,200);assert.equal((await response.json()).offset,chunkSize);
  response=await call('/api/media/upload?id='+id+'&offset='+chunkSize,{method:'PUT',body:new Uint8Array(13)});assert.equal(response.status,200);assert.equal((await response.json()).complete,true);
  response=await call('/api/media/file?id='+fileID,{role:'owner',headers:{range:'bytes=2-5'}});assert.equal(response.status,206);assert.equal(response.headers.get('content-range'),'bytes 2-5/'+record.size);assert.match(response.headers.get('cache-control'),/private, no-store/);assert.equal((await response.arrayBuffer()).byteLength,4);
  assert.equal(state.calls.filter(c=>c.method==='PUT'&&c.range==='bytes 0-1048575/'+record.size).length,1);assert.equal(state.calls.filter(c=>c.method==='PUT'&&c.range==='bytes 1048576-1048588/'+record.size).length,1);
 }finally{await mf.dispose();}
});
test('Workerd blocks unauthorized readers, wrong origin, redirects and revoked photo sessions',async()=>{
 const {mf,db,state,call}=await fixture();try{
  const record={action:'start',id:crypto.randomUUID(),parentId:folderID,filename:'foto-ficticia.png',mimeType:'image/png',size:13},before=state.calls.length;
  assert.equal((await call('/api/media',{role:'reader'})).status,403);assert.equal((await call('/api/media/upload',{method:'POST',headers:{origin:'https://untrusted.example.invalid'},body:JSON.stringify(record)})).status,403);assert.equal(state.calls.length,before);
  assert.equal((await call('/api/media/upload',{method:'POST',body:JSON.stringify(record)})).status,200);const bytes=new Uint8Array(13);bytes.set([137,80,78,71,13,10,26,10]);state.revoke=async()=>{await db.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').bind(photoID).run();};
  const revoked=await call('/api/media/upload?id='+record.id+'&offset=0',{method:'PUT',body:bytes});assert.equal(revoked.status,403);assert.equal((await db.prepare('SELECT status FROM jac_media_operations WHERE id=?').bind(record.id).first()).status,'pending');
  state.redirect=true;const count=state.calls.length,response=await call('/api/media/file?id='+fileID,{role:'owner',headers:{range:'bytes=2-5'}});assert.equal(response.status,502);assert.ok(state.calls.slice(count).every(c=>!c.url.includes('untrusted')));
 }finally{await mf.dispose();}
});
test('Workerd opens a shared photo and ranges using a freshly verified folder-scoped location',async()=>{
 const context=await fixture({readyFile:true,omitFileParents:true,readerPermissions:['administrator']}),{mf,state,call}=context;try{
  await listReadyFile(context);const before=state.calls.length;
  let response=await call('/api/media/file?id='+fileID,{role:'reader'});
  assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),'image/png');assert.match(response.headers.get('cache-control'),/private, no-store/);assert.equal((await response.arrayBuffer()).byteLength,13);
  response=await call('/api/media/file?id='+fileID,{role:'reader',headers:{range:'bytes=2-5'}});
  assert.equal(response.status,206);assert.equal(response.headers.get('content-range'),'bytes 2-5/13');assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[1,2,3,4]);
  const lists=state.calls.slice(before).filter(c=>new URL(c.url).pathname==='/drive/v3/files');
  assert.equal(lists.length,4,'Each read must resolve the exact current parent before and after fetching');
  for(const entry of lists){const q=new URL(entry.url).searchParams.get('q');assert.equal(q,"'"+folderID+"' in parents and name = 'Foto \\'ficticia\\' \\\\ local.png' and trashed=false");}
  assert.equal(state.calls.filter(c=>new URL(c.url).searchParams.get('alt')==='media').length,2);
  assert.ok(state.calls.every(c=>c.method==='GET'||new URL(c.url).origin==='https://oauth2.googleapis.com'),'Read-only media must not create or upload files');
 }finally{await mf.dispose();}
});
test('Workerd denies a same-name listing with a different file ID when parents are omitted',async()=>{
 const context=await fixture({readyFile:true,omitFileParents:true,readerPermissions:['administrator']}),{mf,state,call}=context;try{
  await listReadyFile(context);const before=state.calls.length;
  state.listedID='fixture_worker_same_name_different_id';
  const response=await call('/api/media/file?id='+fileID,{role:'reader'});
  assert.equal(response.status,403);assert.equal((await response.json()).error,'Ese archivo o carpeta no pertenece a Fotografía JAC.');
  assert.equal(state.calls.slice(before).filter(c=>new URL(c.url).pathname==='/drive/v3/files').length,1);
  assert.equal(state.calls.filter(c=>new URL(c.url).searchParams.get('alt')==='media').length,0,'A duplicate name must not authorize the requested file');
 }finally{await mf.dispose();}
});
test('Workerd rechecks the listed parent after fetching and denies a photo moved outside JAC',async()=>{
 const context=await fixture({readyFile:true,omitFileParents:true,readerPermissions:['administrator']}),{mf,state,call}=context;try{
  await listReadyFile(context);const before=state.calls.length;
  state.afterRead=async()=>{state.metadata.parents=[outsideID];};
  const response=await call('/api/media/file?id='+fileID,{role:'reader',headers:{range:'bytes=2-5'}});
  assert.equal(response.status,403);assert.equal((await response.json()).error,'Ese archivo o carpeta no pertenece a Fotografía JAC.');
  assert.equal(state.calls.filter(c=>new URL(c.url).searchParams.get('alt')==='media').length,1);
  assert.equal(state.calls.slice(before).filter(c=>new URL(c.url).pathname==='/drive/v3/files').length,2,'The post-fetch check must query the hinted folder again and find no exact file');
 }finally{await mf.dispose();}
});
test('Workerd refuses missing folder locations without searching globally or downloading',async()=>{
 const {mf,state,call}=await fixture({readyFile:true,omitFileParents:true,readerPermissions:['administrator']});try{
  const before=state.calls.length,response=await call('/api/media/file?id='+fileID,{role:'reader'});
  assert.equal(response.status,403);assert.equal((await response.json()).error,'Ese archivo o carpeta no pertenece a Fotografía JAC.');
  assert.equal(state.calls.slice(before).filter(c=>new URL(c.url).pathname==='/drive/v3/files'||new URL(c.url).searchParams.get('alt')==='media').length,0,'An unobserved file must not cause a global name search or content request');
 }finally{await mf.dispose();}
});
test('Workerd rejects a stale observed location when the file was moved before opening',async()=>{
 const context=await fixture({readyFile:true,omitFileParents:true,readerPermissions:['administrator']}),{mf,state,call}=context;try{
  await listReadyFile(context);state.metadata.parents=[outsideID];const before=state.calls.length;
  const response=await call('/api/media/file?id='+fileID,{role:'reader'});assert.equal(response.status,403);
  assert.equal(state.calls.slice(before).filter(c=>new URL(c.url).pathname==='/drive/v3/files').length,1);
  assert.equal(state.calls.filter(c=>new URL(c.url).searchParams.get('alt')==='media').length,0,'A stored folder relationship must never authorize moved content');
 }finally{await mf.dispose();}
});
test('Workerd invalidates observed locations after the Google connection version changes',async()=>{
 const context=await fixture({readyFile:true,omitFileParents:true,readerPermissions:['administrator']}),{mf,db,state,call}=context;try{
  await listReadyFile(context);await db.prepare("UPDATE jac_media_connection SET version=version+1 WHERE id='jac'").run();const before=state.calls.length;
  const response=await call('/api/media/file?id='+fileID,{role:'reader'});assert.equal(response.status,403);
  assert.equal(state.calls.slice(before).filter(c=>new URL(c.url).pathname==='/drive/v3/files'||new URL(c.url).searchParams.get('alt')==='media').length,0,'A hint from the previous connection cannot participate in a fresh location proof');
 }finally{await mf.dispose();}
});

test('Workerd lets administrators upload photos with the same guarded binary flow',async()=>{
 const {mf,state,call}=await fixture();try{
  const id=crypto.randomUUID(),record={action:'start',id,parentId:folderID,filename:'admin-ficticio.png',mimeType:'image/png',size:13};
  let response=await call('/api/media/upload',{role:'owner',method:'POST',body:JSON.stringify(record)});assert.equal(response.status,200);
  const bytes=new Uint8Array(13);bytes.set([137,80,78,71,13,10,26,10]);response=await call('/api/media/upload?id='+id+'&offset=0',{role:'owner',method:'PUT',body:bytes});assert.equal(response.status,200);assert.equal((await response.json()).complete,true);assert.equal(state.metadata.name,'admin-ficticio.png');
 }finally{await mf.dispose();}
});

test('Workerd streams only bounded private previews and revalidates permission without original fallback',async()=>{
 const {mf,db,state,call}=await fixture({readyFile:true});try{
  let response=await call('/api/media/file?id='+fileID+'&thumbnail=1',{role:'owner',headers:{Range:'bytes=2-5'}});assert.equal(response.status,200);assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[255,216,255,1]);assert.equal(response.headers.get('Content-Length'),'4');assert.match(response.headers.get('Cache-Control'),/private, no-store/);assert.equal(response.headers.get('Accept-Ranges'),'none');
  const preview=state.calls.find(call=>new URL(call.url).origin==='https://lh3.googleusercontent.com');assert.equal(preview.requestedRange,null);assert.match(preview.accept,/image\/jpeg/);assert.equal(state.calls.some(call=>new URL(call.url).searchParams.get('alt')==='media'),false);
  state.thumbnailSize=512*1024+1;response=await call('/api/media/file?id='+fileID+'&thumbnail=1',{role:'owner'});assert.equal(response.status,502);state.thumbnailSize=4;
  state.thumbnailRedirect=true;response=await call('/api/media/file?id='+fileID+'&thumbnail=1',{role:'owner'});assert.equal(response.status,502);state.thumbnailRedirect=false;
  state.afterThumbnail=async()=>{await db.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').bind(ownerID).run();};response=await call('/api/media/file?id='+fileID+'&thumbnail=1',{role:'owner'});assert.equal(response.status,403);assert.equal(state.calls.some(call=>new URL(call.url).searchParams.get('alt')==='media'),false);
 }finally{await mf.dispose();}
});

test('Workerd requests globally ordered creation pages rather than sorting by last modification or folder name',async()=>{
 const {mf,state,call}=await fixture({readyFile:true});try{
  const item=(id,name,createdTime,modifiedTime)=>({id,name,mimeType:folderMime,parents:[folderID],createdTime,modifiedTime});
  const newest=item('worker_new_folder','Z recién creada','2026-10-16T00:00:00Z','2026-01-01T00:00:00Z'),middle=item('worker_mid_folder','M intermedia','2026-09-01T00:00:00Z','2026-12-01T00:00:00Z'),oldest=item('worker_old_folder','A antigua','2026-01-01T00:00:00Z','2026-12-31T00:00:00Z');
  state.listPages={'':{files:[middle,newest],nextPageToken:'page_2'},page_2:{files:[oldest]}};
  const first=await call('/api/media?folder='+folderID,{role:'owner'});assert.equal(first.status,200);const feed=await first.json();assert.equal(feed.nextPageToken,'page_2');assert.deepEqual(feed.items.map(item=>item.id),[newest.id,middle.id]);
  const second=await call('/api/media?folder='+folderID+'&pageToken='+feed.nextPageToken,{role:'owner'});assert.equal(second.status,200);const page=await second.json();assert.deepEqual(page.items.map(item=>item.id),[oldest.id]);assert.equal(page.items[0].createdAt,oldest.createdTime);assert.equal(page.items[0].modifiedAt,oldest.modifiedTime);assert.equal(page.nextPageToken,undefined);
  assert.equal(state.calls.filter(call=>new URL(call.url).searchParams.get('orderBy')==='folder,createdTime desc,name').length,2);
 }finally{await mf.dispose();}
});

test('Workerd separates direct file bytes from JAC control and publishes only after guarded checks',async()=>{
 const {mf,db,state,call}=await fixture();try{
  const id=crypto.randomUUID(),body={action:'start',transport:'direct',id,parentId:folderID,filename:'directa-ficticia.png',mimeType:'image/png',size:13};
  let response=await call('/api/media/upload',{role:'photo',method:'POST',body:JSON.stringify(body)});assert.equal(response.status,200);const plan=await response.json();assert.equal(plan.chunkSize,8*1024*1024);assert.ok(plan.uploadURL.includes('upload_id=fixture-worker-session'));assert.ok(!JSON.stringify(plan).includes('fixture-worker-access'));assert.equal(state.metadata.parents,undefined);
  // Represents a direct device -> fake Drive transfer; no bytes reach Workerd.
  state.offset=state.size;state.metadata.parents=['worker_my_drive_root'];
  response=await call('/api/media/file?id='+fileID,{role:'owner'});assert.equal(response.status,404);
  response=await call('/api/media/upload',{role:'owner',method:'POST',body:JSON.stringify({action:'status',transport:'direct',id})});assert.equal(response.status,404);
  response=await call('/api/media/upload',{role:'photo',method:'POST',body:JSON.stringify({action:'status',transport:'direct',id})});assert.equal(response.status,200);assert.equal((await response.json()).complete,true);assert.deepEqual(state.metadata.parents,[folderID]);
  assert.ok(state.calls.filter(c=>c.method==='PUT').every(c=>c.bytes.length===0));assert.equal(state.calls.filter(c=>c.method==='PATCH').length,1);
  const row=await db.prepare('SELECT session_payload FROM jac_media_operations WHERE id=?').bind(id).first();assert.ok(!row.session_payload.includes('upload_id'));
 }finally{await mf.dispose();}
});

test('Workerd starts a fresh R2-only gallery, publishes direct bytes, serves private previews and enforces revocation',async()=>{
 const {mf,db,state,call}=await fixture();try{
  const storage={accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64),version:0};
  assert.equal((await call('/api/media/storage',{role:'owner',method:'POST',body:JSON.stringify(storage)})).status,200);
  assert.equal((await call('/api/media/storage',{role:'owner',method:'POST',body:JSON.stringify({action:'activateNewCollection',version:1})})).status,200);
  assert.equal((await db.prepare("SELECT credentials FROM jac_media_connection WHERE id='jac'").first()).credentials,'');
  let response=await call('/api/media',{role:'photo'});assert.equal(response.status,200);const root=(await response.json()).root.id;assert.equal(root,'jac_r2_root');assert.equal((await call('/api/media?folder='+folderID)).status,410);
  const id=crypto.randomUUID(),request={action:'start',transport:'direct',id,parentId:root,filename:'Foto-nueva.png',mimeType:'image/png',size:13};
  response=await call('/api/media/upload',{role:'photo',method:'POST',body:JSON.stringify(request)});assert.equal(response.status,200);const plan=await response.json();assert.equal(plan.provider,'r2');assert.ok(plan.uploadURL.includes('X-Amz-Expires=300'));assert.ok(!JSON.stringify(plan).includes(storage.secretAccessKey));
  assert.equal((await (await call('/api/media')).json()).items.length,0);
  // Represents device -> intercepted S3; original bytes never enter Workerd's
  // upload endpoint. Workerd independently lists, completes, HEADs and validates.
  const png=new Uint8Array(13);png.set([137,80,78,71,13,10,26,10]);state.s3.parts.set(1,png);
  response=await call('/api/media/upload',{role:'photo',method:'POST',body:JSON.stringify({action:'status',transport:'direct',id})});assert.equal(response.status,200);const done=await response.json();assert.equal(done.complete,true);
  response=await call('/api/media/file?id='+done.fileId+'&metadata=1',{role:'owner'});assert.equal(response.status,200);assert.equal((await response.json()).item.name,'Foto-nueva.png');
  response=await call('/api/media/file?id='+done.fileId,{role:'owner',headers:{range:'bytes=2-5'}});assert.equal(response.status,206);assert.equal(response.headers.get('content-range'),'bytes 2-5/13');assert.match(response.headers.get('cache-control'),/private, no-store/);
  const jpeg=new Uint8Array([255,216,255,192,0,11,8,0,16,0,16,1,1,17,0,255,217]);response=await call('/api/media/upload?thumbnail=1&id='+id,{role:'photo',method:'PUT',body:jpeg});assert.equal(response.status,200);
  response=await call('/api/media/file?id='+done.fileId+'&thumbnail=1',{role:'owner'});assert.equal(response.status,200);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),jpeg);
  assert.ok(state.calls.every(c=>new URL(c.url).hostname.endsWith('.r2.cloudflarestorage.com')),'No Google/Drive request is allowed after or during R2 activation');
  state.afterR2Read=async()=>{await db.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').bind(ownerID).run();};response=await call('/api/media/file?id='+done.fileId,{role:'owner'});assert.equal(response.status,403);
 }finally{await mf.dispose();}
});
