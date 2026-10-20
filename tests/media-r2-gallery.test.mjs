import test,{beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import {readFile,readdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {build} from 'esbuild';

// Only in-memory D1 and a pinned, intercepted S3 endpoint. No real credentials.
const sql=new DatabaseSync(':memory:');
for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+name,'utf8'));
let beforeQuery;
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};return {results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async first(){await beforeQuery?.(this);return sql.prepare(this.text).get(...this.args)||null;}
 async all(){await beforeQuery?.(this);return {results:sql.prepare(this.text).all(...this.args)};}
 async run(){await beforeQuery?.(this);return {meta:{changes:Number(sql.prepare(this.text).run(...this.args).changes)}};}
}
globalThis.__r2Fixture={DB:{prepare:text=>new Query(text),batch:async queries=>{sql.exec('BEGIN');try{const out=queries.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},PAYROLL_AUTH_KEY:'separate-r2-fixture-auth-key-2026',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')};
globalThis.__r2Headers=new Headers();
const bundled=await build({stdin:{contents:"export * from './lib/media-r2';export * from './lib/media-r2-gallery';export * from './lib/media-r2-s3';export * from './lib/media-upload-client';export * from './lib/media-drive';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export {decryptMail} from './lib/payroll-mail-core';export * as api from './app/api/media/storage/route';export * as gallery from './app/api/media/route';export * as files from './app/api/media/file/route';export * as offline from './app/api/media/offline/route';export * as uploads from './app/api/media/upload/route';export * as playback from './app/api/media/playback/route';export {processMediaPresentations} from './lib/media-stream';export * as shares from './app/api/media/shares/route';export * as shared from './app/api/media/shared/route';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'r2-fixtures',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__r2Fixture;export const waitUntil=p=>{globalThis.__r2Background.push(p);};':'export const headers=async()=>globalThis.__r2Headers;',loader:'js'}));}}]});
const dir=await mkdtemp(resolve('work/r2-fixture-')),file=dir+'/fixture.mjs';await writeFile(file,bundled.outputFiles[0].contents);const m=await import(pathToFileURL(file).href);await rm(dir,{recursive:true});
const ownerID=await m.bootstrapOwner('independent-new-gallery-owner','fixture'),photographer=crypto.randomUUID(),anderson=crypto.randomUUID(),stamp=new Date().toISOString();
sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)').run(photographer,'new-photo','photo@example.invalid','Fotógrafo ficticio','fixture','[]',1,stamp,stamp);
sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)').run(anderson,'anderson','anderson@example.invalid','Anderson ficticio','fixture','[]',1,stamp,stamp);
const input={accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64),version:0},origin='https://r2.example.invalid',host=input.accountId+'.r2.cloudflarestorage.com';
const jpeg=new Uint8Array([255,216,255,192,0,11,8,0,16,0,16,1,1,17,0,255,217]);
let token,photoToken,calls,objects,multiparts,hook,loseComplete,loseDelete;
let streamCalls,streamVideos,streamReady,streamHook;globalThis.__r2Background=[];
beforeEach(async()=>{
 globalThis.__r2Background=[];delete globalThis.__r2Fixture.IMAGES;
 globalThis.__r2Fixture.JAC_STREAM_API_TOKEN='fixture-stream-only';streamCalls=[];streamVideos=new Map();streamReady=true;streamHook=undefined;
 beforeQuery=undefined;hook=undefined;loseComplete=false;loseDelete=false;calls=[];objects=new Map();multiparts=new Map();sql.exec('DELETE FROM jac_media_folder_shares;DELETE FROM jac_media_r2_entries;DELETE FROM jac_media_operations;DELETE FROM jac_media_r2_connection;UPDATE payroll_users SET active=1');sql.prepare('UPDATE payroll_users SET section_access=NULL WHERE id IN (?,?)').run(photographer,anderson);token=await m.makeSession(ownerID);photoToken=await m.makeSession(photographer);
 sql.prepare("INSERT OR REPLACE INTO jac_media_connection(id,credentials,email,version,updated_at) VALUES('jac','previous-photo-drive','jacmusicestudios@gmail.com',7,?)").run(stamp);
 globalThis.fetch=async(request,options={})=>{
  const r=request instanceof Request?request:new Request(request,options),url=new URL(r.url);
  if(url.hostname==='api.cloudflare.com'){
   assert.equal(r.headers.get('authorization'),'Bearer fixture-stream-only');assert.equal(r.redirect,'manual');assert.equal(r.headers.has('cookie'),false);streamCalls.push({method:r.method,url});
   if(streamHook){const answer=await streamHook(r);if(answer)return answer;}
   const ok=result=>Response.json({success:true,result});
   if(url.pathname.endsWith('/copy')){const body=await r.json(),source=new URL(body.url);assert.equal(source.hostname,host);assert.equal(source.searchParams.get('X-Amz-Expires'),'3600');assert.equal(body.requireSignedURLs,true);const uid=crypto.randomUUID().replaceAll('-',''),video={uid,creator:body.creator,meta:body.meta,readyToStream:false};streamVideos.set(uid,video);return ok(video);}
   if(url.pathname.endsWith('/token')){const body=await r.json();assert.ok(body.exp>=Math.floor(Date.now()/1000)+3800,'Provider URLs must remain valid for the one-hour JAC lease');return ok({token:'fixture.stream.signature'});}
   if(url.searchParams.has('limit'))return ok([...streamVideos.values()]);
   if(url.searchParams.has('creator'))return ok([...streamVideos.values()].filter(v=>v.creator===url.searchParams.get('creator')));
   const uid=url.pathname.split('/').at(-1),video=streamVideos.get(uid);if(r.method==='DELETE'){streamVideos.delete(uid);return ok({});}assert.ok(video);return ok({...video,readyToStream:streamReady});
  }
  if(url.hostname==='videodelivery.net'||url.hostname==='customer-fixture.cloudflarestream.com'){
   assert.equal(r.headers.has('authorization'),false);assert.equal(r.headers.has('cookie'),false);assert.equal(r.redirect,'manual');streamCalls.push({method:r.method,url});
   if(streamHook){const answer=await streamHook(r);if(answer)return answer;}
   if(url.pathname.endsWith('/manifest/video.m3u8'))return new Response('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=1800000\nhigh.m3u8\n',{headers:{'Content-Type':'application/vnd.apple.mpegurl'}});
   if(url.pathname.endsWith('.m3u8'))return new Response('#EXTM3U\n#EXTINF:4,\n../video/segment.ts\n#EXT-X-ENDLIST\n',{headers:{'Content-Type':'application/vnd.apple.mpegurl'}});
   return new Response(new Uint8Array([71,0,1,2]),{headers:{'Content-Type':'video/mp2t'}});
  }
  assert.equal(url.hostname,host,'No Google, Drive, redirect or other network destination is allowed');assert.ok(url.pathname.startsWith('/jac-fotografia'));assert.equal(r.headers.has('cookie'),false);assert.equal(r.headers.has('origin'),false);
  const direct=url.searchParams.has('X-Amz-Signature');if(direct){assert.equal(r.method,'PUT');assert.equal(r.headers.has('authorization'),false);assert.equal(r.headers.has('content-range'),false);assert.equal(options.credentials,'omit');assert.equal(options.referrerPolicy,'no-referrer');}else{assert.equal(r.redirect,'manual');assert.match(r.headers.get('authorization'),/^AWS4-HMAC-SHA256 Credential=/);}
  calls.push({url,method:r.method,direct});if(hook){const response=await hook(r);if(response)return response;}
  const key=url.pathname.slice('/jac-fotografia/'.length),uploadId=url.searchParams.get('uploadId');
  if(url.searchParams.has('delete')&&r.method==='POST'){
   const body=await r.text();assert.equal(r.headers.get('content-md5'),createHash('md5').update(body).digest('base64'));const keys=[...body.matchAll(/<Key>([^<]+)<\/Key>/g)].map(m=>m[1]);assert.ok(keys.length<=200);for(const key of keys){assert.match(key,/^(originals|thumbnails|previews)\/[a-f0-9-]{36}(\.jpg)?$/);objects.delete(key);}if(loseDelete){loseDelete=false;throw new Error('lost delete response');}return new Response('<DeleteResult>'+keys.map(k=>'<Deleted><Key>'+k+'</Key></Deleted>').join('')+'</DeleteResult>');
  }
  if(url.pathname==='/jac-fotografia'&&r.method==='HEAD')return new Response(null);
  if(r.method==='POST'&&url.searchParams.has('uploads')){const id='fixture-'+crypto.randomUUID();multiparts.set(id,{key,mime:r.headers.get('content-type'),request:r.headers.get('x-amz-meta-jac-request'),parts:new Map()});return new Response('<InitiateMultipartUploadResult><UploadId>'+id+'</UploadId></InitiateMultipartUploadResult>');}
  const upload=multiparts.get(uploadId);
  if(direct){assert.ok(upload);const bytes=new Uint8Array(await r.arrayBuffer());upload.parts.set(Number(url.searchParams.get('partNumber')),bytes);return new Response(null,{headers:{ETag:'"'+'a'.repeat(32)+'"'}});}
  if(uploadId&&r.method==='GET'){if(!upload)return new Response(null,{status:404});return new Response('<ListPartsResult><IsTruncated>false</IsTruncated>'+[...upload.parts].sort(([a],[b])=>a-b).map(([n,b])=>'<Part><PartNumber>'+n+'</PartNumber><Size>'+b.length+'</Size><ETag>"'+'a'.repeat(32)+'"</ETag></Part>').join('')+'</ListPartsResult>');}
  if(uploadId&&r.method==='POST'){
   if(!upload)return new Response('<Error><Code>NoSuchUpload</Code></Error>',{status:404});
   const xml=await r.text(),parts=[...xml.matchAll(/<Part><PartNumber>(\d+)<\/PartNumber><ETag>(.*?)<\/ETag><\/Part>/g)].map(match=>({number:Number(match[1]),etag:match[2].replaceAll('&quot;','"')}));
   if(!parts.length||parts.some((part,index)=>!upload.parts.has(part.number)||part.etag!=='"'+'a'.repeat(32)+'"'||index>0&&part.number<=parts[index-1].number))return new Response('<Error><Code>InvalidPart</Code></Error>',{status:400});
   const bytes=new Uint8Array(parts.reduce((count,part)=>count+upload.parts.get(part.number).length,0));let offset=0;for(const part of parts){const data=upload.parts.get(part.number);bytes.set(data,offset);offset+=data.length;}
   objects.set(key,{bytes,mime:upload.mime,request:upload.request});multiparts.delete(uploadId);if(loseComplete){loseComplete=false;throw new Error('simulated lost completion response');}return new Response('<CompleteMultipartUploadResult><Key>'+key+'</Key></CompleteMultipartUploadResult>');
  }
  if(uploadId&&r.method==='DELETE'){multiparts.delete(uploadId);return new Response(null,{status:204});}
  if(r.method==='PUT'){objects.set(key,{bytes:new Uint8Array(await r.arrayBuffer()),mime:r.headers.get('content-type'),profile:r.headers.get('x-amz-meta-jac-preview-profile')});return new Response(null);}
  if(r.method==='DELETE'){objects.delete(key);return new Response(null,{status:204});}
  const object=objects.get(key);if(!object)return new Response(null,{status:404});const headers={'content-type':object.mime,'content-length':String(object.bytes.length),...(object.request?{'x-amz-meta-jac-request':object.request}:{}),...(object.profile?{'x-amz-meta-jac-preview-profile':object.profile}:{})};if(r.method==='HEAD')return new Response(null,{headers});
  if(r.method==='GET'){const range=r.headers.get('range');if(range){const match=range.match(/^bytes=(\d+)-(\d+)$/);assert.ok(match);const begin=Number(match[1]),end=Number(match[2]);return new Response(object.bytes.slice(begin,end+1),{status:206,headers:{...headers,'content-length':String(end-begin+1),'content-range':`bytes ${begin}-${end}/${object.bytes.length}`}});}return new Response(object.bytes,{headers});}
  throw new Error('Unhandled fixture operation');
 };
 assert.equal((await storage(input)).status,200);
});
function req(path,body,session=token,method='POST',extra={}){const headers={origin,cookie:'__Host-jac_session='+session,...extra};globalThis.__r2Headers=new Headers({host:'r2.example.invalid',...headers});return new Request(origin+path,{method,headers,...(body!==undefined?{body:typeof body==='string'||body instanceof Uint8Array?body:JSON.stringify(body)}:{})});}
const storage=(body,session=token)=>m.api.POST(req('/api/media/storage',body,session));
const activate=()=>storage({action:'activateNewCollection',version:1});
const api=(body,session=photoToken)=>m.gallery.POST(req('/api/media',body,session));
const command=(body,session=photoToken)=>m.uploads.POST(req('/api/media/upload',body,session));
const feed=(folder='',session=photoToken)=>m.gallery.GET(req('/api/media'+(folder?'?folder='+folder:''),undefined,session,'GET'));
async function folder(){const r=await api({action:'createFolder',id:crypto.randomUUID(),parentId:m.R2_ROOT,name:'Show ficticio',date:'2026-10-16'});assert.equal(r.status,200);return (await r.json()).folder.id;}
async function start(bytes=jpeg,parentId=m.R2_ROOT,id=crypto.randomUUID(),mimeType='image/jpeg'){const data={action:'start',transport:'direct',id,parentId,filename:mimeType==='video/mp4'?'Video.mp4':mimeType==='image/png'?'Foto.png':'Foto.jpg',mimeType,size:bytes.length};const r=await command(data);assert.equal(r.status,200);return {data,plan:await r.json(),bytes};}
async function send(upload){const p=upload.plan,bytes=upload.bytes.slice(p.offset,Math.min(p.offset+p.chunkSize,upload.bytes.length));await m.sendMediaDirectChunk(p.uploadURL,upload.data.mimeType,new Blob([bytes]),p.offset,upload.bytes.length,new AbortController().signal);const r=await command({action:'status',transport:'direct',id:p.id});return r;}
const partReceipt=(upload,extra={})=>({partNumber:1,etag:'"'+'a'.repeat(32)+'"',size:upload.bytes.length,...extra});
async function sendPart(upload){await m.sendMediaDirectChunk(upload.plan.uploadURL,upload.data.mimeType,new Blob([upload.bytes]),0,upload.bytes.length,new AbortController().signal);}
const receiptStatus=(upload,receipt=partReceipt(upload),session=photoToken)=>command({action:'status',transport:'direct',id:upload.data.id,partReceipt:receipt},session);

const shareCommand=(body,session=photoToken,headers={})=>m.shares.POST(req('/api/media/shares',body,session,'POST',headers));
const publicRead=(token,query={})=>m.shared.GET(new Request(origin+'/api/media/shared?'+new URLSearchParams({token,...query})));
async function sharedFixture(){
 await activate();const parent=await folder(),childResponse=await api({action:'createFolder',id:crypto.randomUUID(),parentId:parent,name:'Solo subcarpeta',date:'2026-10-16'}),child=(await childResponse.json()).folder.id;
 const upload=await start(jpeg,child);assert.equal((await send(upload)).status,200);
 const response=await shareCommand({action:'create',id:crypto.randomUUID(),folderId:parent,days:30});assert.equal(response.status,200);const {link}=await response.json();return {parent,child,upload,link,token:link.url.split('/').at(-1)};
}

test('folder links are random, encrypted at rest, bounded in time and idempotent on lost responses',async()=>{
 const {parent,link,token:capability}=await sharedFixture();assert.match(capability,/^[A-Za-z0-9_-]{43}$/);
 const row=sql.prepare('SELECT * FROM jac_media_folder_shares WHERE id=?').get(link.id);
 assert.equal(row.token_hash,createHash('sha256').update(capability).digest('hex'));assert.ok(!JSON.stringify(row).includes(capability));assert.equal(row.actor_id,photographer);
 const repeat=await shareCommand({action:'create',id:link.id,folderId:parent,days:30});assert.equal(repeat.status,200);assert.deepEqual((await repeat.json()).link,link);
 assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_folder_shares').get().n,1);
 assert.ok(Date.parse(link.expiresAt)-Date.now()>29*86400000);
 const list=await m.shares.GET(req('/api/media/shares?folder='+parent,undefined,photoToken,'GET'));assert.deepEqual((await list.json()).links,[link]);
 assert.equal((await shareCommand({action:'create',id:crypto.randomUUID(),folderId:parent,days:36500})).status,400);
 assert.equal((await shareCommand({action:'create',id:crypto.randomUUID(),folderId:m.R2_ROOT,days:30})).status,400);
 assert.equal((await shareCommand({action:'create',id:crypto.randomUUID(),folderId:parent,days:30},'',{})).status,401);
 assert.equal((await shareCommand({action:'create',id:crypto.randomUUID(),folderId:parent,days:30},photoToken,{origin:'https://evil.invalid'})).status,403);
});
test('anonymous link readers see only the shared subtree, never ancestors, siblings or private endpoints',async()=>{
 const fixture=await sharedFixture(),sibling=await folder(),response=await publicRead(fixture.token),feed=await response.json();
 assert.equal(response.status,200);assert.deepEqual(feed.breadcrumbs.map(x=>x.id),[fixture.parent]);assert.equal(feed.folder.id,fixture.parent);assert.equal(feed.items[0].id,fixture.child);
 for(const key of ['root','canUpload','canConnect','canDelete','deletedFolders','pendingDeletions','collectionID'])assert.equal(key in feed,false);
 const nested=await publicRead(fixture.token,{folder:fixture.child});assert.equal(nested.status,200);assert.deepEqual((await nested.json()).breadcrumbs.map(x=>x.id),[fixture.parent,fixture.child]);
 assert.equal((await publicRead(fixture.token,{folder:sibling})).status,410);
 assert.equal((await publicRead(fixture.token,{folder:m.R2_ROOT})).status,400);
 assert.equal((await publicRead('a'.repeat(43))).status,410);
 const privateAPI=await m.gallery.GET(req('/api/media?folder='+fixture.parent,undefined,'','GET'));assert.equal(privateAPI.status,401);
 assert.match(response.headers.get('cache-control'),/no-store/);assert.equal(response.headers.get('referrer-policy'),'no-referrer');assert.match(response.headers.get('x-robots-tag'),/noindex/);
});
test('shared originals, thumbnails and ranges retain subtree checks and never return storage credentials',async()=>{
 const fixture=await sharedFixture(),id=fixture.upload.plan.fileId||'r2_'+fixture.upload.data.id;
 const cover=await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+fixture.upload.data.id,jpeg,photoToken,'PUT',{'Content-Type':'image/jpeg'}));assert.equal(cover.status,200);
 const file=await publicRead(fixture.token,{id});assert.equal(file.status,200);assert.deepEqual(new Uint8Array(await file.arrayBuffer()),jpeg);
 const thumbnail=await publicRead(fixture.token,{id,thumbnail:'1'});assert.equal(thumbnail.status,200);assert.equal(thumbnail.headers.get('content-type'),'image/jpeg');
 const range=await m.shared.GET(new Request(origin+'/api/media/shared?'+new URLSearchParams({token:fixture.token,id}),{headers:{Range:'bytes=0-3'}}));assert.equal(range.status,206);assert.deepEqual(new Uint8Array(await range.arrayBuffer()),jpeg.slice(0,4));
 assert.equal(file.headers.has('authorization'),false);assert.equal(file.headers.has('set-cookie'),false);
 const outside=await start(jpeg,await folder());assert.equal((await send(outside)).status,200);const before=calls.length;
 assert.equal((await publicRead(fixture.token,{id:'r2_'+outside.data.id})).status,410);assert.equal(calls.length,before);
});
test('revocation, expiry and creator permission changes invalidate anonymous links',async()=>{
 const fixture=await sharedFixture();assert.equal((await publicRead(fixture.token)).status,200);
 sql.prepare("UPDATE jac_media_folder_shares SET expires_at='2000-01-01T00:00:00.000Z' WHERE id=?").run(fixture.link.id);assert.equal((await publicRead(fixture.token)).status,410);
 sql.prepare('UPDATE jac_media_folder_shares SET expires_at=? WHERE id=?').run(fixture.link.expiresAt,fixture.link.id);
 sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(photographer);assert.equal((await publicRead(fixture.token)).status,410);sql.prepare('UPDATE payroll_users SET active=1 WHERE id=?').run(photographer);
 sql.prepare("UPDATE payroll_users SET section_access='[\"media\"]' WHERE id=?").run(photographer);assert.equal((await publicRead(fixture.token)).status,410);sql.prepare('UPDATE payroll_users SET section_access=NULL WHERE id=?').run(photographer);
 assert.equal((await publicRead(fixture.token)).status,200);
 assert.equal((await shareCommand({action:'revoke',folderId:fixture.parent,id:fixture.link.id})).status,200);
 assert.equal((await publicRead(fixture.token)).status,410);assert.equal((await publicRead(fixture.token,{id:'r2_'+fixture.upload.data.id})).status,410);
 assert.equal((await shareCommand({action:'revoke',folderId:fixture.parent,id:fixture.link.id})).status,200);
});
test('a share revoked while S3 is reading cannot disclose the late bytes',async()=>{
 const fixture=await sharedFixture();hook=async request=>{if(request.method==='GET'){sql.prepare("UPDATE jac_media_folder_shares SET revoked_at=? WHERE id=?").run(new Date().toISOString(),fixture.link.id);hook=undefined;}};
 const response=await publicRead(fixture.token,{id:'r2_'+fixture.upload.data.id});assert.equal(response.status,403);assert.ok(!(await response.text()).includes('secretAccessKey'));
});
test('moved files, rotated storage and deleted folders cannot remain accessible through an old share',async()=>{
 const fixture=await sharedFixture(),id='r2_'+fixture.upload.data.id,sibling=await folder();
 sql.prepare('UPDATE jac_media_r2_entries SET parent_id=? WHERE id=?').run(sibling,id);assert.equal((await publicRead(fixture.token,{id})).status,410);
 sql.prepare('UPDATE jac_media_r2_entries SET parent_id=? WHERE id=?').run(fixture.child,id);assert.equal((await publicRead(fixture.token,{id})).status,200);
 sql.prepare("UPDATE jac_media_r2_connection SET version=version+1 WHERE id='jac'").run();assert.equal((await publicRead(fixture.token)).status,410);
 sql.prepare("UPDATE jac_media_r2_connection SET version=version-1 WHERE id='jac'").run();assert.equal((await publicRead(fixture.token)).status,200);
 const deletion=await api({action:'deleteFolder',id:fixture.parent},token);assert.equal(deletion.status,200);
 assert.equal((await publicRead(fixture.token)).status,410);assert.equal((await publicRead(fixture.token,{id})).status,410);
});

test('a confirmed single-part receipt removes two S3 roundtrips but keeps final metadata and signature validation',async()=>{
 await activate();const legacy=await start();await sendPart(legacy);let before=calls.length;
 assert.equal((await command({action:'status',id:legacy.data.id})).status,200);const oldCalls=calls.slice(before);assert.deepEqual(oldCalls.map(call=>call.method),['HEAD','GET','POST','HEAD','GET']);
 const upload=await start();await sendPart(upload);before=calls.length;
 const response=await receiptStatus(upload);assert.equal(response.status,200);const done=await response.json(),fastCalls=calls.slice(before);
 assert.equal(done.complete,true);assert.equal(done.offset,jpeg.length);assert.deepEqual(fastCalls.map(call=>call.method),['POST','HEAD','GET']);assert.equal(fastCalls.some(call=>call.url.searchParams.has('max-parts')),false);
 assert.equal(oldCalls.length-fastCalls.length,2);assert.deepEqual(objects.get('originals/'+upload.data.id).bytes,jpeg);
 const beforeRetry=calls.length;assert.deepEqual(await (await receiptStatus(upload)).json(),done);assert.equal(calls.length,beforeRetry,'The ready state remains idempotent');
});
test('malformed receipts and multi-part uploads cannot activate the one-part fast path',async()=>{
 await activate();const upload=await start(),before=calls.length;
 for(const receipt of [null,[],{},[partReceipt(upload)],partReceipt(upload,{partNumber:2}),partReceipt(upload,{etag:'unquoted'}),partReceipt(upload,{etag:'"<xml>"'}),partReceipt(upload,{size:'17'}),partReceipt(upload,{parts:[]})])assert.equal((await receiptStatus(upload,receipt)).status,400);
 assert.equal((await receiptStatus(upload,partReceipt(upload,{size:jpeg.length+1}))).status,422);assert.equal(calls.length,before);
 const large=await start(new Uint8Array(8*1024*1024+1));const afterStart=calls.length;assert.equal((await receiptStatus(large)).status,422);assert.equal(calls.length,afterStart);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0);
});
test('a forged well-formed ETag is not authorization and legacy reconciliation still confirms the real part',async()=>{
 await activate();const upload=await start();await sendPart(upload);
 assert.equal((await receiptStatus(upload,partReceipt(upload,{etag:'"'+'b'.repeat(32)+'"'}))).status,502);assert.equal(objects.size,0);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0);
 const confirmed=await command({action:'status',id:upload.data.id});assert.equal(confirmed.status,200);assert.equal((await confirmed.json()).complete,true);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,1);assert.deepEqual(objects.get('originals/'+upload.data.id).bytes,jpeg);
});
test('a lost one-part completion response is recovered by verified object metadata without another multipart',async()=>{
 await activate();const upload=await start();await sendPart(upload);loseComplete=true;const before=calls.length;
 const response=await receiptStatus(upload);assert.equal(response.status,200);assert.equal((await response.json()).complete,true);assert.deepEqual(calls.slice(before).map(call=>call.method),['POST','HEAD','GET']);assert.equal(multiparts.size,0);assert.equal(objects.size,1);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,1);
});
test('NoSuchUpload after a completed object and interrupted database commit resumes the same catalogue entry',async()=>{
 await activate();const upload=await start();await sendPart(upload);let interrupted=false;
 beforeQuery=query=>{if(!interrupted&&query.text.startsWith('UPDATE jac_media_operations SET offset=')&&query.args[1]==='ready'){interrupted=true;throw new Error('simulated interrupted state commit');}};
 assert.equal((await receiptStatus(upload)).status,503);assert.equal(interrupted,true);assert.equal(objects.size,1);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,1);
 beforeQuery=undefined;const before=calls.length,response=await receiptStatus(upload);assert.equal(response.status,200);assert.equal((await response.json()).complete,true);assert.deepEqual(calls.slice(before).map(call=>call.method),['POST','HEAD','GET']);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,1);
});
test('receipt finalization still rejects changed size, MIME, request identity and an invalid media signature',async()=>{
 await activate();
 for(const change of ['size','mime','request','signature']){
  const upload=await start();await sendPart(upload);const multipart=multiparts.get(new URL(upload.plan.uploadURL).searchParams.get('uploadId'));
  if(change==='size')multipart.parts.set(1,jpeg.slice(0,-1));if(change==='mime')multipart.mime='image/png';if(change==='request')multipart.request=crypto.randomUUID();if(change==='signature')multipart.parts.set(1,new Uint8Array(jpeg.length));
  assert.equal((await receiptStatus(upload)).status,422,change);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0,change);
 }
});
test('single-part receipt finalization preserves ownership, live revocation and the final SQL session guard',async()=>{
 await activate();let upload=await start();await sendPart(upload);let before=calls.length;
 assert.equal((await receiptStatus(upload,partReceipt(upload),token)).status,403);assert.equal(calls.length,before);
 hook=request=>{if(request.method==='POST'&&new URL(request.url).searchParams.has('uploadId'))sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(photographer);};
 assert.equal((await receiptStatus(upload)).status,403);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0);hook=undefined;
 sql.prepare('UPDATE payroll_users SET active=1 WHERE id=?').run(photographer);upload=await start();await sendPart(upload);let fired=false;
 beforeQuery=query=>{if(!fired&&query.text.startsWith('INSERT OR IGNORE INTO jac_media_r2_entries')){fired=true;sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(photographer);}};
 assert.equal((await receiptStatus(upload)).status,409);assert.equal(fired,true);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0);
});

test('activation starts empty, discards only the Photography Drive connection, and never reads Drive',async()=>{
 const gmail='unrelated-existing-cipher';sql.prepare("INSERT OR REPLACE INTO payroll_gmail(id,credentials,updated_at) VALUES('jac',?,?)").run(gmail,stamp);
 sql.prepare("INSERT INTO payroll_oauth(id,payload,expires_at) VALUES('jac-media:old','old-photo','future'),('calendar:untouched','other','future')").run();
 assert.equal((await activate()).status,200);const old=sql.prepare("SELECT * FROM jac_media_connection WHERE id='jac'").get();assert.equal(old.credentials,'');assert.equal(old.email,'');assert.equal(old.version,8);assert.equal(sql.prepare("SELECT credentials FROM payroll_gmail WHERE id='jac'").get().credentials,gmail);assert.equal(sql.prepare("SELECT 1 FROM payroll_oauth WHERE id='jac-media:old'").get(),undefined);assert.ok(sql.prepare("SELECT 1 FROM payroll_oauth WHERE id='calendar:untouched'").get());
 const r=await feed();assert.equal(r.status,200);const f=await r.json();assert.equal(f.provider,'r2');assert.equal(f.collectionID,m.R2_COLLECTION);assert.deepEqual(f.items,[]);assert.equal(f.root.id,m.R2_ROOT);assert.equal(calls.length,1,'Only the initial bucket HEAD, never an inventory or copy');assert.equal((await feed('some_previous_drive_id')).status,410);
 assert.equal((await m.gallery.POST(req('/api/media',{action:'connect'}))).status,409);assert.equal(calls.length,1);
});
test('folder creation is private, idempotent, chronological and isolated from legacy identifiers',async()=>{
 await activate();const body={action:'createFolder',id:crypto.randomUUID(),parentId:m.R2_ROOT,name:'Pereira',date:'2026-10-16'},first=await (await api(body)).json();assert.deepEqual(await (await api(body)).json(),first);assert.equal((await api({...body,name:'Different'})).status,409);assert.equal((await api(body,token)).status,409);assert.equal((await api({...body,id:crypto.randomUUID(),parentId:'foreign_drive_folder'})).status,410);
 const f=await (await feed()).json();assert.equal(f.items.length,1);assert.equal(f.items[0].kind,'folder');assert.equal(f.items[0].name,'Pereira');assert.equal(calls.length,1);assert.equal((await command({action:'start',id:crypto.randomUUID(),parentId:'foreign_drive_folder',filename:'x.jpg',mimeType:'image/jpeg',size:17})).status,410);
});
test('direct multipart upload publishes once only after server-confirmed bytes, type and complete metadata',async()=>{
 await activate();const parentId=await folder(),upload=await start(jpeg,parentId);assert.equal((await (await feed(parentId)).json()).items.length,0);assert.equal(upload.plan.provider,'r2');assert.ok(!JSON.stringify(upload.plan).includes(input.secretAccessKey));
 const r=await send(upload);assert.equal(r.status,200);const done=await r.json();assert.equal(done.complete,true);assert.equal(done.offset,jpeg.length);assert.deepEqual(await (await command({action:'status',id:done.id})).json(),done);assert.deepEqual(await (await command(upload.data)).json(),done);
 const f=await (await feed(parentId)).json();assert.equal(f.items.length,1);assert.equal(f.items[0].id,done.fileId);const response=await m.files.GET(req('/api/media/file?id='+done.fileId,undefined,photoToken,'GET'));assert.equal(response.status,200);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),jpeg);assert.equal(response.headers.get('cache-control'),'private, no-store, max-age=0');
 const ranged=await m.files.GET(req('/api/media/file?id='+done.fileId,undefined,token,'GET',{range:'bytes=2-5'}));assert.equal(ranged.status,206);assert.equal(ranged.headers.get('content-range'),'bytes 2-5/17');
});
test('multiple parts, timed-out completion and repeated status resume without duplicate objects or entries',async()=>{
 await activate();const bytes=new Uint8Array(8*1024*1024+17);bytes.set([137,80,78,71,13,10,26,10]);const upload=await start(bytes,m.R2_ROOT,crypto.randomUUID(),'image/png'),first=await send(upload);assert.equal(first.status,200);upload.plan=await first.json();assert.equal(upload.plan.offset,8*1024*1024);assert.equal(upload.plan.complete,false);assert.equal((await (await feed()).json()).items.length,0);
 loseComplete=true;assert.equal((await send(upload)).status,502);const retry=await command({action:'status',id:upload.data.id});assert.equal(retry.status,200);assert.equal((await retry.json()).complete,true);assert.equal(objects.size,1);assert.equal((await (await feed()).json()).items.length,1);
});
test('invalid signatures, short parts and client offsets cannot publish media',async()=>{
 await activate();const upload=await start(new Uint8Array(17));assert.equal((await send(upload)).status,422);assert.equal((await (await feed()).json()).items.length,0);
 const other=await start(new Uint8Array(8*1024*1024+17),m.R2_ROOT,crypto.randomUUID(),'image/png'),id=new URL(other.plan.uploadURL).searchParams.get('uploadId');multiparts.get(id).parts.set(1,jpeg);assert.equal((await command({action:'status',id:other.data.id,offset:other.bytes.length,complete:true})).status,422);assert.equal((await (await feed()).json()).items.length,0);
});
test('current permissions, actor, origin, connection and SQL guard are checked before publication',async()=>{
 await activate();const upload=await start();assert.equal((await command({action:'status',id:upload.data.id},token)).status,403);assert.equal((await m.uploads.POST(req('/api/media/upload',upload.data,photoToken,'POST',{origin:'https://untrusted.invalid'}))).status,403);
 await m.sendMediaDirectChunk(upload.plan.uploadURL,'image/jpeg',new Blob([jpeg]),0,jpeg.length,new AbortController().signal);
 hook=r=>{if(r.method==='POST'&&new URL(r.url).searchParams.has('uploadId'))sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(photographer);};assert.equal((await command({action:'status',id:upload.data.id})).status,403);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0);
});
test('stale configuration and redirects cannot leak credentials or publish pending files',async()=>{
 await activate();const upload=await start();sql.exec("UPDATE jac_media_r2_connection SET version=version+1 WHERE id='jac'");assert.equal((await command({action:'status',id:upload.data.id})).status,403);
 const other=await start();hook=()=>new Response(null,{status:307,headers:{location:'https://attacker.invalid'}});const response=await command({action:'status',id:other.data.id});assert.equal(response.status,502);assert.ok(!(await response.text()).includes(input.secretAccessKey));assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0);
});
test('thumbnails are bounded JPEG variants attached only to the same completed upload',async()=>{
 await activate();const upload=await start(),done=await (await send(upload)).json(),path='/api/media/upload?thumbnail=1&id='+done.id;
 assert.equal((await m.uploads.PUT(req(path,jpeg,token,'PUT'))).status,403);assert.equal((await m.uploads.PUT(req(path,new Uint8Array(513*1024),photoToken,'PUT'))).status,502);
 assert.equal((await m.uploads.PUT(req(path,new TextEncoder().encode('<svg>'),photoToken,'PUT'))).status,422);assert.equal((await m.uploads.PUT(req(path,jpeg,photoToken,'PUT'))).status,200);
 const f=await (await feed()).json();assert.equal(f.items[0].thumbnailAvailable,true);const r=await m.files.GET(req('/api/media/file?id='+done.fileId+'&thumbnail=1',undefined,photoToken,'GET'));assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'image/jpeg');assert.deepEqual(new Uint8Array(await r.arrayBuffer()),jpeg);
});
test('server cancellation aborts only its multipart; issued capabilities cannot publish afterwards',async()=>{
 await activate();const upload=await start(),cancel=await command({action:'directCancel',id:upload.data.id});assert.equal(cancel.status,200);assert.equal(multiparts.size,0);assert.equal((await command({action:'status',id:upload.data.id})).status,410);assert.equal((await (await feed()).json()).items.length,0);
});
test('UUID case aliases cannot create two operations writing the same object key',async()=>{
 await activate();const upload=await start();assert.equal((await command({...upload.data,id:upload.data.id.toUpperCase()},token)).status,400);assert.equal(sql.prepare("SELECT COUNT(*) AS n FROM jac_media_operations WHERE kind='r2-upload'").get().n,1);assert.equal(multiparts.size,1);
});
test('revocation immediately before the publish SQL and after fetching bytes denies visibility',async()=>{
 await activate();const upload=await start();await m.sendMediaDirectChunk(upload.plan.uploadURL,'image/jpeg',new Blob([jpeg]),0,jpeg.length,new AbortController().signal);
 let fired=false;beforeQuery=q=>{if(!fired&&q.text.startsWith('INSERT OR IGNORE INTO jac_media_r2_entries')){fired=true;sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(photographer);}};
 assert.equal((await command({action:'status',id:upload.data.id})).status,409);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').get().n,0);assert.equal(fired,true);
});

test('new folder names are exact and creation order descends independently of names and supplied dates',async()=>{
 await activate();const ids=[];
 for(const name of ['Zulu · Ensayo','Álbum Pereira','Bogotá 2026']){const r=await api({action:'createFolder',id:crypto.randomUUID(),parentId:m.R2_ROOT,name,date:'2099-12-31'});assert.equal(r.status,200);const folder=(await r.json()).folder;assert.equal(folder.name,name);ids.push(folder.id);}
 for(let i=0;i<ids.length;i++)sql.prepare('UPDATE jac_media_r2_entries SET created_at=?,modified_at=? WHERE id=?').run('2026-10-'+String(10+i)+'T12:00:00Z','2099-12-31T00:00:00Z',ids[i]);
 const f=await (await feed()).json();assert.deepEqual(f.items.map(x=>x.id),ids.toReversed());
});
test('JPEG limit is 2,000,000 bytes, enforced before any S3 allocation, while PNG and existing photos remain available',async()=>{
 await activate();const before=calls.length,id=crypto.randomUUID(),body={action:'start',transport:'direct',id,parentId:m.R2_ROOT,filename:'Grande.JPG',mimeType:'image/jpeg',size:2_000_001,imageLimit:2_000_000};
 const r=await command(body);assert.equal(r.status,413);assert.match((await r.json()).error,/nivel elegido/);assert.equal(calls.length,before);assert.equal(sql.prepare('SELECT 1 FROM jac_media_operations WHERE id=?').get(id),undefined);
 const bytes=new Uint8Array(2_000_000);bytes.set(jpeg);const atLimit=await start(bytes);assert.equal((await send(atLimit)).status,200);
 // A pre-existing, already published JPEG is not removed/recompressed by the new upload rule.
 sql.prepare('UPDATE jac_media_r2_entries SET size=15000000 WHERE id=?').run('r2_'+atLimit.data.id);const f=await (await feed()).json();assert.equal(f.items[0].size,15000000);
 assert.equal((await m.files.GET(req('/api/media/file?id='+f.items[0].id+'&metadata=1',undefined,photoToken,'GET'))).status,200);
 const png=new Uint8Array(2_000_001);png.set([137,80,78,71,13,10,26,10]);assert.equal((await send(await start(png,m.R2_ROOT,crypto.randomUUID(),'image/png'))).status,200);
});

test('a retry across the folder naming release returns the earlier folder without renaming it or widening ownership',async()=>{
 await activate();const body={action:'createFolder',id:crypto.randomUUID(),parentId:m.R2_ROOT,name:'Pereira',date:'2026-10-16'},first=await (await api(body)).json(),name='2026-10-16 · Pereira';
 sql.prepare('UPDATE jac_media_r2_entries SET name=?,payload_hash=? WHERE id=?').run(name,createHash('sha256').update(JSON.stringify([photographer,m.R2_ROOT,name])).digest('hex'),first.folder.id);
 const retry=await api(body);assert.equal(retry.status,200);assert.equal((await retry.json()).folder.name,name);assert.equal((await api({...body,date:'2026-10-17'})).status,409);assert.equal((await api(body,token)).status,409);assert.equal((await (await feed()).json()).items.length,1);
});

test('image quality accepts 2/4/6 MB or original, is immutable on retries and does not cap videos',async()=>{
 await activate();
 for(const [limit,size] of [[4_000_000,3_000_000],[6_000_000,5_000_000],[0,9_000_000]]){
  const body={action:'start',transport:'direct',id:crypto.randomUUID(),parentId:m.R2_ROOT,filename:'Foto.jpg',mimeType:'image/jpeg',size,imageLimit:limit};const r=await command(body);assert.equal(r.status,200);assert.equal((await command({...body,imageLimit:limit===0?undefined:0})).status,409);
 }
 assert.equal((await command({action:'start',transport:'direct',id:crypto.randomUUID(),parentId:m.R2_ROOT,filename:'Video.mov',mimeType:'video/quicktime',size:15_000_000,imageLimit:2_000_000})).status,200);
 assert.equal((await command({action:'start',transport:'direct',id:crypto.randomUUID(),parentId:m.R2_ROOT,filename:'Foto.jpg',mimeType:'image/jpeg',size:17,imageLimit:123})).status,400);
 const bytes=new Uint8Array(3_000_000);bytes.set(jpeg);const upload=await start(bytes);assert.equal((await send(upload)).status,200,'Older/native original uploads remain supported without an imposed 2 MB cap');
});

test('unprivileged uploaders cannot delete folders; root, files, Drive IDs and foreign origins are refused',async()=>{
 await activate();const id=await folder(),before=calls.length;
 const ownerFeed=await (await feed('',token)).json(),photoFeed=await (await feed()).json();assert.equal(ownerFeed.canDelete,true);assert.equal(photoFeed.canDelete,false);
 assert.equal((await api({action:'deleteFolder',id})).status,403);assert.equal(calls.length,before);assert.equal(sql.prepare("SELECT 1 FROM jac_media_operations WHERE kind='r2-delete-folder'").get(),undefined);
 for(const target of [m.R2_ROOT,m.MEDIA_ROOT_ID])assert.equal((await api({action:'deleteFolder',id:target},token)).status,400);
 assert.equal((await api({action:'deleteFolder',id:'legacy_drive_id'},token)).status,410);
 assert.equal((await m.gallery.POST(req('/api/media',{action:'deleteFolder',id},token,'POST',{origin:'https://other.invalid'}))).status,403);
 const done=await (await send(await start())).json();assert.equal((await api({action:'deleteFolder',id:done.fileId},token)).status,400);
});
test('empty folder deletion is durable and idempotent without touching S3 or recreating its identifier',async()=>{
 await activate();const body={action:'createFolder',id:crypto.randomUUID(),parentId:m.R2_ROOT,name:'Carpeta de prueba',date:'2026-10-16'},created=await (await api(body)).json(),id=created.folder.id,before=calls.length;
 const r=await api({action:'deleteFolder',id},token);assert.equal(r.status,200);const result=await r.json();assert.equal(result.complete,true);assert.equal(result.parentId,m.R2_ROOT);assert.equal(calls.length,before);assert.deepEqual(await (await api({action:'deleteFolder',id},token)).json(),result);
 assert.equal((await feed(id)).status,410);assert.equal((await api(body)).status,410);const f=await (await feed()).json();assert.equal(f.items.length,0);assert.deepEqual(f.deletedFolders,[id]);
});
test('recursive deletion removes originals and variants but preserves another identically named folder',async()=>{
 await activate();const target=await folder(),other=await folder(),child=await (await api({action:'createFolder',id:crypto.randomUUID(),parentId:target,name:'Dentro',date:'2026-10-16'})).json();
 const one=await start(jpeg,target),oneDone=await (await send(one)).json();await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+one.data.id,jpeg,photoToken,'PUT'));
 const two=await (await send(await start(jpeg,child.folder.id))).json(),outside=await (await send(await start(jpeg,other))).json();
 const r=await api({action:'deleteFolder',id:target},token);assert.equal(r.status,200);assert.equal((await r.json()).complete,true);assert.equal(objects.size,1);
 for(const id of [target,child.folder.id])assert.equal((await feed(id)).status,410);
 for(const file of [oneDone,two])assert.equal((await m.files.GET(req('/api/media/file?id='+file.fileId,undefined,token,'GET'))).status,404);
 assert.equal((await (await feed(other)).json()).items[0].id,outside.fileId);assert.equal((await m.files.GET(req('/api/media/file?id='+outside.fileId,undefined,token,'GET'))).status,200);
});
test('lost deletion responses and partial S3 failures remain resumable and never hide failed cleanup as success',async()=>{
 await activate();const target=await folder(),done=await (await send(await start(jpeg,target))).json();loseDelete=true;
 assert.equal((await api({action:'deleteFolder',id:target},token)).status,502);assert.equal((await feed(target)).status,410);assert.equal((await (await feed('',token)).json()).pendingDeletions[0].id,target);
 hook=r=>new URL(r.url).searchParams.has('delete')?new Response('<DeleteResult><Error><Key>not-confirmed</Key></Error></DeleteResult>'):undefined;
 assert.equal((await api({action:'deleteFolder',id:target},token)).status,502);assert.ok(sql.prepare('SELECT 1 FROM jac_media_r2_entries WHERE id=?').get(done.fileId));
 hook=undefined;const r=await api({action:'deleteFolder',id:target},token);assert.equal(r.status,200);assert.equal((await r.json()).complete,true);assert.deepEqual((await (await feed('',token)).json()).pendingDeletions,[]);
});
test('deletion blocks a finalization paused immediately before SQL, then cancels and cleans that pending multipart',async()=>{
 await activate();const target=await folder(),upload=await start(jpeg,target);let paused=false;
 beforeQuery=async q=>{if(!paused&&q.text.startsWith('INSERT OR IGNORE INTO jac_media_r2_entries')&&q.text.includes('EXISTS(SELECT 1 FROM jac_media_operations')){paused=true;beforeQuery=undefined;const r=await api({action:'deleteFolder',id:target},token);assert.equal(r.status,200);assert.equal((await r.json()).waiting,true);}};
 assert.equal((await send(upload)).status,409);assert.equal(paused,true);assert.equal((await command({action:'start',transport:'direct',id:crypto.randomUUID(),parentId:target,filename:'Late.jpg',mimeType:'image/jpeg',size:17})).status,410);
 const result=await api({action:'deleteFolder',id:target},token);assert.equal(result.status,200);assert.equal((await result.json()).complete,true);assert.equal(objects.size,0);assert.equal((await command({action:'status',id:upload.data.id})).status,410);
});
test('deletion waits for an in-flight thumbnail and also removes a variant that could not be attached',async()=>{
 await activate();const target=await folder(),upload=await start(jpeg,target);await send(upload);let waited=false;
 hook=async r=>{if(r.method==='PUT'&&new URL(r.url).pathname.includes('/thumbnails/')){const old=hook;hook=undefined;const result=await api({action:'deleteFolder',id:target},token);assert.equal((await result.json()).waiting,true);waited=true;hook=old;}};
 assert.equal((await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+upload.data.id,jpeg,photoToken,'PUT'))).status,410);assert.equal(waited,true);hook=undefined;
 assert.equal((await (await api({action:'deleteFolder',id:target},token)).json()).complete,true);assert.equal(objects.size,0);
});
test('large folder deletion is bounded and a second administrator can resume the same operation',async()=>{
 await activate();const target=await folder(),second=crypto.randomUUID();sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)').run(second,'jac-admin','admin@example.invalid','Admin ficticio','fixture',JSON.stringify(['administrator']),stamp,stamp);const secondToken=await m.makeSession(second);
 for(let i=0;i<101;i++){const id=crypto.randomUUID(),key='originals/'+id;sql.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,?,?,?,?,?,?)').run('r2_'+id,target,'Photo.jpg','image/jpeg',jpeg.length,key,photographer,'fixture',stamp,stamp);objects.set(key,{bytes:jpeg,mime:'image/jpeg'});}
 const first=await api({action:'deleteFolder',id:target},token);assert.equal(first.status,200);const pending=await first.json();assert.equal(pending.complete,false);assert.equal(pending.removed,100);assert.equal(objects.size,1);
 const final=await api({action:'deleteFolder',id:target},secondToken);assert.equal(final.status,200);const ready=await final.json();assert.equal(ready.complete,true);assert.equal(ready.removed,101);assert.equal(objects.size,0);
});
test('permission/configuration changes during deletion stop further actions and keys outside the folder cannot be supplied',async()=>{
 await activate();const target=await folder(),done=await (await send(await start(jpeg,target))).json();sql.prepare('UPDATE jac_media_r2_entries SET object_key=? WHERE id=?').run('originals/'+crypto.randomUUID(),done.fileId);const before=calls.length;
 assert.equal((await api({action:'deleteFolder',id:target},token)).status,409);assert.equal(calls.length,before);
 sql.prepare('UPDATE jac_media_r2_entries SET object_key=? WHERE id=?').run('originals/'+done.id,done.fileId);
 hook=r=>{if(new URL(r.url).searchParams.has('delete')){sql.exec("UPDATE jac_media_r2_connection SET version=version+1 WHERE id='jac'");return new Response('<DeleteResult/>');}};
 assert.equal((await api({action:'deleteFolder',id:target},token)).status,403);hook=undefined;const seen=calls.length;assert.equal((await api({action:'deleteFolder',id:target},token)).status,409);assert.equal(calls.length,seen);
});

test('individual deletion requires delete permission, same origin and observed revision and cannot target a folder',async()=>{
 await activate();const parent=await folder(),done=await (await send(await start(jpeg,parent))).json(),photo=(await (await feed(parent)).json()).items[0],body={action:'deleteFile',id:photo.id,revision:photo.modifiedAt},before=calls.length;
 assert.equal((await api(body)).status,403);
 assert.equal((await m.gallery.POST(req('/api/media',body,token,'POST',{origin:'https://foreign.invalid'}))).status,403);
 assert.equal((await api({...body,revision:'stale'},token)).status,409);
 assert.equal((await api({action:'deleteFile',id:parent,revision:photo.modifiedAt},token)).status,400);
 assert.equal((await api({action:'deleteFile',id:m.R2_ROOT},token)).status,400);
 assert.equal(calls.length,before);assert.equal(objects.has('originals/'+done.id),true);
});
test('individual deletion removes exactly one original and thumbnail, is idempotent and cannot be republished',async()=>{
 await activate();const parent=await folder(),upload=await start(jpeg,parent),done=await (await send(upload)).json();
 await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+upload.data.id,jpeg,photoToken,'PUT'));
 const kept=await (await send(await start(jpeg,parent))).json(),photo=(await (await feed(parent)).json()).items.find(p=>p.id===done.fileId),body={action:'deleteFile',id:photo.id,revision:photo.modifiedAt};
 const response=await api(body,token);assert.equal(response.status,200);const result=await response.json();assert.equal(result.complete,true);assert.equal(result.removed,1);
 assert.equal(objects.size,1);assert.equal(objects.has('originals/'+kept.id),true);
 assert.deepEqual(await (await api(body,token)).json(),result);
 const after=await (await feed(parent)).json();assert.deepEqual(after.items.map(p=>p.id),[kept.fileId]);assert.deepEqual(after.deletedFiles,[photo.id]);
 for(const suffix of ['', '&metadata=1','&thumbnail=1'])assert.equal((await m.files.GET(req('/api/media/file?id='+photo.id+suffix,undefined,token,'GET'))).status,410);
 assert.equal((await command({action:'status',id:upload.data.id})).status,410);
 assert.equal((await command(upload.data)).status,410);
 assert.equal((await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+upload.data.id,jpeg,photoToken,'PUT'))).status,410);
});
test('a lost individual S3 deletion stays hidden and resumable by another administrator without a second original',async()=>{
 await activate();const done=await (await send(await start())).json(),photo=(await (await feed()).json()).items[0];loseDelete=true;
 assert.equal((await api({action:'deleteFile',id:photo.id,revision:photo.modifiedAt},token)).status,502);
 const pending=await (await feed('',token)).json();assert.equal(pending.items.length,0);assert.equal(pending.pendingFileDeletions[0].id,done.fileId);
 assert.equal((await (await feed()).json()).pendingFileDeletions.length,0);
 const second=crypto.randomUUID();sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)').run(second,'photo-delete-admin','photo-delete-admin@example.invalid','Admin ficticio','fixture',JSON.stringify(['administrator']),stamp,stamp);
 const result=await api({action:'deleteFile',id:photo.id},await m.makeSession(second));assert.equal(result.status,200);assert.equal((await result.json()).complete,true);assert.equal(objects.size,0);
});
test('a thumbnail in flight cannot revive a photo tombstoned during its S3 request',async()=>{
 await activate();const upload=await start(),done=await (await send(upload)).json();let intercepted=false;
 hook=async r=>{if(r.method==='PUT'&&new URL(r.url).pathname.includes('/thumbnails/')){
  hook=undefined;intercepted=true;const photo=(await (await feed()).json()).items[0];const response=await api({action:'deleteFile',id:photo.id,revision:photo.modifiedAt},token);assert.equal(response.status,200);assert.equal((await response.json()).waiting,true);
 }};
 assert.equal((await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+upload.data.id,jpeg,photoToken,'PUT'))).status,403);assert.equal(intercepted,true);
 assert.equal((await api({action:'deleteFile',id:done.fileId},token)).status,200);assert.equal(objects.size,0);assert.equal(sql.prepare('SELECT 1 FROM jac_media_r2_entries WHERE id=?').get(done.fileId),undefined);
});
test('an invalid object key, partial delete, redirect or revoked session never reports individual deletion success',async()=>{
 await activate();const upload=await start(),done=await (await send(upload)).json(),photo=(await (await feed()).json()).items[0],body={action:'deleteFile',id:photo.id,revision:photo.modifiedAt};
 sql.prepare('UPDATE jac_media_r2_entries SET object_key=? WHERE id=?').run('originals/'+crypto.randomUUID(),photo.id);const before=calls.length;assert.equal((await api(body,token)).status,409);assert.equal(calls.length,before);
 sql.prepare('UPDATE jac_media_r2_entries SET object_key=? WHERE id=?').run('originals/'+done.id,photo.id);
 hook=r=>new URL(r.url).searchParams.has('delete')?new Response(null,{status:307,headers:{location:'https://foreign.invalid'}}):undefined;assert.equal((await api(body,token)).status,502);
 hook=r=>new URL(r.url).searchParams.has('delete')?new Response('<DeleteResult><Error/></DeleteResult>'):undefined;assert.equal((await api(body,token)).status,502);
 hook=r=>{if(new URL(r.url).searchParams.has('delete')){sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(ownerID);return new Response('<DeleteResult/>');}};assert.equal((await api(body,token)).status,403);
 assert.equal(sql.prepare("SELECT status FROM jac_media_operations WHERE id=?").get('r2-delete:'+photo.id).status,'pending');
});
test('offline encryption capabilities are session scoped, require media access and never expose login or application secrets',async()=>{
 const read=async session=>m.offline.GET(req('/api/media/offline',undefined,session,'GET'));
 const first=await read(photoToken);assert.equal(first.status,200);assert.match(first.headers.get('cache-control'),/no-store/);const context=await first.json();
 assert.match(context.scope,/^[A-Za-z0-9_-]{43}$/);assert.match(context.key,/^[A-Za-z0-9_-]{43}$/);assert.ok(!JSON.stringify(context).includes(photoToken));
 assert.deepEqual(await (await read(photoToken)).json(),context);const another=await m.makeSession(photographer);assert.notDeepEqual(await (await read(another)).json(),context);
 sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',photographer);assert.equal((await read(photoToken)).status,403);assert.equal((await read('invalid')).status,401);
});


test('Anderson can delete existing photos, videos and folders created by another uploader without administrator access',async()=>{
 await activate();const parent=await folder(),kept=await folder();
 const photo=await (await send(await start(jpeg,parent))).json();
 const videoBytes=new Uint8Array([0,0,0,24,102,116,121,112,105,115,111,109,0,0,0,0,105,115,111,109,109,112,52,50]);
 const video=await (await send(await start(videoBytes,parent,crypto.randomUUID(),'video/mp4'))).json();
 const andersonToken=await m.makeSession(anderson),user=await m.authenticatedSession(andersonToken);
 assert.equal(user.isOwner,false);assert.deepEqual(user.permissions,[]);
 assert.equal(user.mediaOnly,true);assert.equal(user.sections,undefined);
 assert.equal((await (await feed(parent,andersonToken)).json()).canDelete,true);
 for(const uploaded of [photo,video]){
  const entry=(await (await feed(parent,andersonToken)).json()).items.find(x=>x.id===uploaded.fileId);
  assert.equal(sql.prepare('SELECT actor_id FROM jac_media_r2_entries WHERE id=?').get(entry.id).actor_id,photographer);
  const response=await api({action:'deleteFile',id:entry.id,revision:entry.modifiedAt},andersonToken);
  assert.equal(response.status,200);assert.equal((await response.json()).complete,true);
  assert.equal(objects.has('originals/'+uploaded.id),false);
 }
 const inside=await (await send(await start(jpeg,parent))).json();
 const removed=await api({action:'deleteFolder',id:parent},andersonToken);
 assert.equal(removed.status,200);assert.equal((await removed.json()).complete,true);
 assert.equal(objects.has('originals/'+inside.id),false);assert.equal((await feed(kept)).status,200);
 assert.equal((await storage(input,andersonToken)).status,403);
});

test('Anderson delete permission requires Photography and the current active session in the SQL guard',async()=>{
 const session=await m.makeSession(anderson),guard=m.mediaStoredGuard(m.tokenHash(session),anderson,'delete');
 const allowed=()=>m.mediaGuardActive(guard);
 assert.equal(await allowed(),true);
 try{
  sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',anderson);assert.equal(await allowed(),false);
  sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["media"]',anderson);assert.equal(await allowed(),true);
  sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(anderson);assert.equal(await allowed(),false);
  sql.prepare('UPDATE payroll_users SET active=1,version=version+1 WHERE id=?').run(anderson);assert.equal(await allowed(),false);
 }finally{sql.prepare('UPDATE payroll_users SET active=1,section_access=NULL WHERE id=?').run(anderson);}
 const other=await m.authenticatedSession(photoToken),forged={...other,username:'anderson'};
 const forgedGuard=m.mediaGuard(req('/api/media',{},photoToken),forged,'delete');
 assert.equal(await m.mediaGuardActive(forgedGuard),false,'The database identity, not a supplied username, authorizes deletion');
});

test('revoking Anderson Photography access while deleting stops the operation before reporting success',async()=>{
 await activate();const target=await folder(),uploaded=await (await send(await start(jpeg,target))).json(),session=await m.makeSession(anderson);
 hook=request=>{if(new URL(request.url).searchParams.has('delete')){sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',anderson);return new Response('<DeleteResult/>');}};
 try{assert.equal((await api({action:'deleteFolder',id:target},session)).status,403);hook=undefined;const before=calls.length;assert.equal((await api({action:'deleteFolder',id:target},session)).status,403);assert.equal(calls.length,before);assert.equal(objects.has('originals/'+uploaded.id),true);}
 finally{hook=undefined;sql.prepare('UPDATE payroll_users SET section_access=NULL WHERE id=?').run(anderson);}
});


test('light photo previews preserve the original, refuse thumbnail fallback and are removed with the photo',async()=>{
 await activate();const parent=await folder(),upload=await start(jpeg,parent),done=await (await send(upload)).json();
 await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+upload.data.id,jpeg,photoToken,'PUT'));
 const entry=(await (await feed(parent)).json()).items[0],before=objects.get('originals/'+done.id).bytes.slice();
 const fallback=await m.files.GET(req('/api/media/file?id='+entry.id+'&preview=1',undefined,photoToken,'GET'));assert.equal(fallback.status,503);assert.equal(calls.some(call=>call.method==='GET'&&call.url.pathname.includes('/thumbnails/')),false);
 const light=jpeg.slice();light[7]=6;light[8]=64;light[9]=6;light[10]=64;
 const response=await m.uploads.PUT(req('/api/media/upload?preview=1&id='+upload.data.id,light,photoToken,'PUT'));assert.equal(response.status,200);
 const preview=await m.files.GET(req('/api/media/file?id='+entry.id+'&preview=1&revision='+entry.modifiedAt,undefined,photoToken,'GET'));assert.equal(preview.status,200);assert.equal(preview.headers.get('content-type'),'image/jpeg');assert.deepEqual(new Uint8Array(await preview.arrayBuffer()),light);assert.deepEqual(objects.get('originals/'+done.id).bytes,before);
 assert.equal((await api({action:'deleteFile',id:entry.id,revision:entry.modifiedAt},token)).status,200);assert.equal(objects.has('previews/'+done.id+'.jpg'),false);
});

const sizedJPEG=edge=>{const bytes=jpeg.slice(),height=Math.floor(edge*0.75);bytes[7]=height>>8;bytes[8]=height&255;bytes[9]=edge>>8;bytes[10]=edge&255;return bytes;};
function previewImages(output){
 const transformations=[];
 globalThis.__r2Fixture.IMAGES={input(stream){return {transform(options){return {async output(encoding){
  const source=new Uint8Array(await new Response(stream).arrayBuffer());transformations.push({options,encoding,source});
  const bytes=await (output?.(options,encoding,source)??sizedJPEG(options.width));return {response:()=>new Response(bytes,{headers:{'content-type':'image/jpeg','content-length':String(bytes.length)}})};
 }}}};}};
 return transformations;
}
async function photoPreviewFixture(){await activate();const parent=await folder(),upload=await start(jpeg,parent),done=await(await send(upload)).json();await m.uploads.PUT(req('/api/media/upload?thumbnail=1&id='+upload.data.id,jpeg,photoToken,'PUT'));return {upload,id:done.fileId,item:(await(await feed(parent)).json()).items[0]};}
const photoPreview=(id,session=photoToken)=>m.files.GET(req('/api/media/file?id='+id+'&preview=1',undefined,session,'GET'));

test('balanced photo preview is generated once from the original, keeps the grid cover and survives reopening',async()=>{
 const {id,item}=await photoPreviewFixture(),transforms=previewImages(),before=objects.get('originals/'+id.slice(3)).bytes.slice();
 for(let attempt=0;attempt<2;attempt++){const response=await photoPreview(id);assert.equal(response.status,200);assert.equal(response.headers.get('x-jac-preview-profile'),'balanced-2400-q84-v2');assert.deepEqual(new Uint8Array(await response.arrayBuffer()),sizedJPEG(2400));}
 assert.equal(transforms.length,1);assert.deepEqual(transforms[0].options,{width:2400,height:2400,fit:'scale-down'});assert.deepEqual(transforms[0].encoding,{format:'image/jpeg',quality:84});assert.deepEqual(transforms[0].source,before);
 assert.deepEqual(objects.get('originals/'+id.slice(3)).bytes,before);assert.deepEqual(objects.get('thumbnails/'+id.slice(3)+'.jpg').bytes,jpeg);
 assert.equal(sql.prepare('SELECT modified_at FROM jac_media_r2_entries WHERE id=?').get(id).modified_at,item.modifiedAt);
 const original=await m.files.GET(req('/api/media/file?id='+id,undefined,photoToken,'GET'));assert.deepEqual(new Uint8Array(await original.arrayBuffer()),before);
 assert.equal((await api({action:'deleteFile',id,revision:item.modifiedAt},token)).status,200);assert.equal(objects.has('previews/'+id.slice(3)+'.jpg'),false);
});

test('balanced photo preview upgrades an existing 1600px copy and keeps moderate quality when a smaller raster is needed',async()=>{
 const {id,upload}=await photoPreviewFixture();assert.equal((await m.uploads.PUT(req('/api/media/upload?preview=1&id='+upload.data.id,sizedJPEG(1600),photoToken,'PUT'))).status,200);
 const transforms=previewImages(options=>options.width===2400?new Uint8Array(2*1024*1024+1):sizedJPEG(2048));
 const response=await photoPreview(id);assert.equal(response.status,200);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),sizedJPEG(2048));assert.deepEqual(transforms.map(value=>[value.options.width,value.encoding.quality]),[[2400,84],[2048,84]]);
 assert.equal(objects.get('previews/'+id.slice(3)+'.jpg').profile,'balanced-2400-q84-v2');
});

test('balanced photo preview failures keep an existing intermediate view but never return a thumbnail or original',async()=>{
 const {id,upload}=await photoPreviewFixture(),transforms=previewImages(()=>{throw Error('quota unavailable');});
 const unavailable=await photoPreview(id);assert.equal(unavailable.status,503);assert.equal(transforms.length,1);assert.equal(objects.has('previews/'+id.slice(3)+'.jpg'),false);
 assert.equal((await photoPreview(id)).status,503);assert.equal(transforms.length,1,'Failure cooldown must not repeatedly transform the same photo');
 assert.equal((await m.uploads.PUT(req('/api/media/upload?preview=1&id='+upload.data.id,sizedJPEG(1600),photoToken,'PUT'))).status,200);
 const fallback=await photoPreview(id);assert.equal(fallback.status,200);assert.deepEqual(new Uint8Array(await fallback.arrayBuffer()),sizedJPEG(1600));assert.equal(transforms.length,1);
 assert.equal(calls.some(call=>call.method==='GET'&&call.url.pathname.includes('/thumbnails/')),false);
});

test('balanced photo preview revocation after transformation prevents publication and returns no bytes',async()=>{
 const {id}=await photoPreviewFixture();previewImages(()=>{sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(photographer);return sizedJPEG(2400);});
 assert.equal((await photoPreview(id)).status,403);assert.equal(objects.has('previews/'+id.slice(3)+'.jpg'),false);assert.equal(objects.has('originals/'+id.slice(3)),true);
 assert.equal(calls.some(call=>call.method==='PUT'&&call.url.pathname.includes('/previews/')),false);
});

test('balanced photo preview generation cannot revive a photo deleted while its derived PUT is in flight',async()=>{
 const {id,item}=await photoPreviewFixture();previewImages();let intercepted=false;
 hook=async request=>{if(!intercepted&&request.method==='PUT'&&new URL(request.url).pathname.includes('/previews/')){intercepted=true;assert.equal((await api({action:'deleteFile',id,revision:item.modifiedAt},token)).status,200);}};
 assert.ok([403,410].includes((await photoPreview(id)).status));assert.equal(objects.has('previews/'+id.slice(3)+'.jpg'),false);assert.equal(objects.has('originals/'+id.slice(3)),false);
});

test('balanced photo preview concurrent readers reuse one preparation without changing the photo revision',async()=>{
 const {id,item}=await photoPreviewFixture();let release,started;
 const gate=new Promise(resolve=>release=resolve),begun=new Promise(resolve=>started=resolve);
 const transforms=previewImages(async()=>{started();await gate;return sizedJPEG(2400);});
 const first=photoPreview(id);await begun;const second=photoPreview(id);release();
 for(const response of await Promise.all([first,second])){assert.equal(response.status,200);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),sizedJPEG(2400));}
 assert.equal(transforms.length,1);assert.equal(sql.prepare('SELECT modified_at FROM jac_media_r2_entries WHERE id=?').get(id).modified_at,item.modifiedAt);
});

test('balanced photo previews through a shared link remain folder scoped and are withdrawn when the link is revoked',async()=>{
 const {parent,upload,link,token:capability}=await sharedFixture(),id='r2_'+upload.data.id,transforms=previewImages();
 const response=await publicRead(capability,{id,preview:'1'});assert.equal(response.status,200);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),sizedJPEG(2400));assert.equal(transforms.length,1);
 const outside=await start(jpeg);await send(outside);assert.equal((await publicRead(capability,{id:'r2_'+outside.data.id,preview:'1'})).status,410);assert.equal(transforms.length,1);
 assert.equal((await shareCommand({action:'revoke',folderId:parent,id:link.id})).status,200);assert.ok([403,410].includes((await publicRead(capability,{id,preview:'1'})).status));assert.equal(transforms.length,1);
});

async function videoFixture(){await activate();const parent=await folder(),bytes=new Uint8Array([0,0,0,24,102,116,121,112,105,115,111,109,0,0,0,0,105,115,111,109,109,112,52,50]),done=await (await send(await start(bytes,parent,crypto.randomUUID(),'video/mp4'))).json();return {parent,id:done.fileId};}
const playbackInfo=id=>m.playback.GET(req('/api/media/playback?id='+id,undefined,photoToken,'GET'));
const leased=url=>m.playback.GET(new Request(url.startsWith('/')?origin+url:url));
async function readyVideo(id){assert.equal((await (await playbackInfo(id)).json()).ready,false);const response=await playbackInfo(id);assert.equal(response.status,200);const info=await response.json();assert.equal(info.ready,true);return info;}

test('adaptive playback prepares a private Stream asset once, rewrites HLS and never reads an original for playback',async()=>{
 const {id}=await videoFixture(),before=calls.length,info=await readyVideo(id);assert.equal(streamVideos.size,1);assert.equal(streamCalls.filter(x=>x.url.pathname.endsWith('/copy')).length,1);
 assert.ok(!JSON.stringify(info).includes(photoToken));const master=await leased(info.url);assert.equal(master.status,200);const text=await master.text();assert.ok(text.includes('BANDWIDTH=500000')&&text.includes('BANDWIDTH=1800000'));assert.ok(!text.includes('fixture.stream.signature'));assert.ok(!text.includes('cloudflarestorage'));
 const child=text.split('\n').find(line=>line.startsWith('/api/')),playlist=await (await leased(child)).text(),segment=playlist.split('\n').find(line=>line.startsWith('/api/'));assert.deepEqual(new Uint8Array(await (await leased(segment)).arrayBuffer()),new Uint8Array([71,0,1,2]));assert.equal(calls.length,before);
 const bad=new URL(info.url);bad.searchParams.set('asset','../../originals/secret');assert.equal((await leased(bad.toString())).status,400);
});

test('playback leases revalidate session, ancestor deletion and foreign manifest destinations',async()=>{
 const {parent,id}=await videoFixture(),info=await readyVideo(id);
 streamHook=request=>new URL(request.url).hostname==='videodelivery.net'?new Response('#EXTM3U\nhttps://untrusted.example.invalid/video.ts\n'):undefined;
 assert.equal((await leased(info.url)).status,502);streamHook=undefined;
 sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',photographer);const before=streamCalls.length;assert.equal((await leased(info.url)).status,403);assert.equal(streamCalls.length,before);
 sql.prepare('UPDATE payroll_users SET section_access=NULL WHERE id=?').run(photographer);
 await api({action:'deleteFolder',id:parent},token);assert.equal((await leased(info.url)).status,403);
});

test('shared video playback never initiates paid processing and revocation withdraws its existing HLS lease',async()=>{
 const {parent,id}=await videoFixture(),shared=await (await shareCommand({action:'create',id:crypto.randomUUID(),folderId:parent,days:30})).json(),capability=shared.link.url.split('/').at(-1);
 const pending=await publicRead(capability,{id,playback:'1'});assert.equal((await pending.json()).ready,false);assert.equal(streamCalls.length,0);
 await readyVideo(id);const response=await publicRead(capability,{id,playback:'1'}),info=await response.json();assert.equal(info.ready,true);assert.equal((await leased(info.url)).status,200);
 assert.equal((await shareCommand({action:'revoke',id:shared.link.id,folderId:parent})).status,200);assert.equal((await leased(info.url)).status,410);
});

test('uncertain Stream copies reconcile by creator without issuing a duplicate copy',async()=>{
 const {id}=await videoFixture();let copied=false;
 streamHook=async request=>{if(!new URL(request.url).pathname.endsWith('/copy'))return;copied=true;throw new Error('Lost response after an ambiguous copy');};
 assert.equal((await (await playbackInfo(id)).json()).ready,false);assert.equal(copied,true);streamHook=undefined;
 const before=streamCalls.filter(x=>x.url.pathname.endsWith('/copy')).length;await playbackInfo(id);assert.equal(streamCalls.filter(x=>x.url.pathname.endsWith('/copy')).length,before);assert.equal((await globalThis.__r2Fixture.DB.prepare('SELECT stream_status FROM jac_media_presentations WHERE file_id=?').bind(id).first()).stream_status,'uncertain');
});

test('scheduled Stream preparation processes existing videos once and cleans the derivative after deletion',async()=>{
 const {id}=await videoFixture(),key='originals/'+id.slice(3),original=objects.get(key).bytes.slice();
 await m.processMediaPresentations();
 let row=sql.prepare('SELECT * FROM jac_media_presentations WHERE file_id=?').get(id);
 assert.ok(row?.stream_uid);assert.equal(row.stream_status,'processing');
 await m.processMediaPresentations();
 row=sql.prepare('SELECT * FROM jac_media_presentations WHERE file_id=?').get(id);assert.equal(row.stream_status,'ready');
 await m.processMediaPresentations();assert.equal(streamCalls.filter(call=>call.url.pathname.endsWith('/copy')).length,1);
 assert.deepEqual(objects.get(key).bytes,original);
 const revision=sql.prepare('SELECT modified_at FROM jac_media_r2_entries WHERE id=?').get(id).modified_at;
 assert.equal((await api({action:'deleteFile',id,revision},token)).status,200);
 await m.processMediaPresentations();
 assert.equal(sql.prepare('SELECT 1 FROM jac_media_presentations WHERE file_id=?').get(id),undefined);
 assert.equal(streamVideos.has(row.stream_uid),false);
});

test('owner playback diagnostics inspect delivery without exposing credentials or starting a copy',async()=>{
 const {id}=await videoFixture();
 assert.equal((await m.playback.GET(req('/api/media/playback?diagnostics=1',undefined,photoToken,'GET'))).status,403);
 assert.equal(streamCalls.length,0);
 await readyVideo(id);const copies=streamCalls.filter(call=>call.url.pathname.endsWith('/copy')).length;
 let response=await m.playback.GET(req('/api/media/playback?diagnostics=1',undefined,token,'GET')),data=await response.json();
 assert.equal(response.status,200);assert.equal(data.api.ok,true);assert.equal(data.videos,1);assert.equal(data.master.ok,true);assert.equal(data.variant.ok,true);assert.equal(data.fragment.ok,true);
 assert.equal(streamCalls.filter(call=>call.url.pathname.endsWith('/copy')).length,copies);
 assert.ok(!JSON.stringify(data).includes('fixture.stream.signature'));assert.ok(!JSON.stringify(data).includes('cloudflarestorage'));assert.ok(!JSON.stringify(data).includes('fixture-stream-only'));
 streamHook=request=>new URL(request.url).hostname==='api.cloudflare.com'?Response.json({success:false,errors:[{code:10000,message:'private upstream value must not be returned'}]},{status:403}):undefined;
 response=await m.playback.GET(req('/api/media/playback?diagnostics=1',undefined,token,'GET'));data=await response.json();
 assert.equal(data.api.status,403);assert.equal(data.api.code,10000);assert.ok(!JSON.stringify(data).includes('private upstream value'));
});

test('signed HLS preserves the provider host, video path and query credentials for initialization and media fragments',async()=>{
 const {id}=await videoFixture(),info=await readyVideo(id),uid=[...streamVideos.keys()].at(-1),delivery='https://customer-fixture.cloudflarestream.com/'+uid;
 streamHook=request=>{
  const url=new URL(request.url);if(url.hostname==='api.cloudflare.com')return;
  if(url.pathname.endsWith('/manifest/video.m3u8'))return new Response('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1800000\n'+delivery+'/manifest/low.m3u8?token=manifest-secret&sig=manifest-proof\n');
  assert.equal(url.hostname,'customer-fixture.cloudflarestream.com');assert.ok(url.pathname.startsWith('/'+uid+'/'));
  if(url.pathname.endsWith('.m3u8')){assert.equal(url.searchParams.get('token'),'manifest-secret');assert.equal(url.searchParams.get('sig'),'manifest-proof');return new Response('#EXTM3U\n#EXT-X-MAP:URI="'+delivery+'/video/init.mp4?token=segment-secret&sig=init-proof"\n#EXTINF:4,\n'+delivery+'/video/segment.m4s?token=segment-secret&sig=media-proof\n#EXT-X-ENDLIST\n');}
  assert.equal(url.searchParams.get('token'),'segment-secret');assert.equal(url.searchParams.get('sig'),url.pathname.endsWith('init.mp4')?'init-proof':'media-proof');
  return new Response(new Uint8Array([1,2,3,4]),{headers:{'Content-Type':'video/mp4'}});
 };
 const master=await (await leased(info.url)).text(),child=master.split('\n').find(line=>line.startsWith('/api/'));
 assert.ok(!master.includes('manifest-secret'));assert.ok(!master.includes(uid));
 const playlist=await (await leased(child)).text(),initialization=playlist.match(/URI="([^"]+)"/)[1],fragment=playlist.split('\n').find(line=>line.startsWith('/api/'));
 assert.ok(!playlist.includes('segment-secret'));assert.ok(!playlist.includes('init-proof'));assert.ok(!playlist.includes('customer-fixture'));
 assert.deepEqual(new Uint8Array(await (await leased(initialization)).arrayBuffer()),new Uint8Array([1,2,3,4]));
 assert.deepEqual(new Uint8Array(await (await leased(fragment)).arrayBuffer()),new Uint8Array([1,2,3,4]));
 const altered=new URL(fragment,origin),asset=altered.searchParams.get('asset');altered.searchParams.set('asset',asset.slice(0,3)+(asset[3]==='A'?'B':'A')+asset.slice(4));assert.equal((await leased(altered.href)).status,403);
 const other=await (await playbackInfo(id)).json(),rebound=new URL(fragment,origin);rebound.searchParams.set('lease',new URL(other.url).searchParams.get('lease'));assert.equal((await leased(rebound.href)).status,403);
});

test('stable gallery cursors do not skip or repeat older files after an earlier insertion or deletion',async()=>{
 await activate();const parent=await folder(),ids=[];
 for(let i=0;i<205;i++){const id='r2_'+crypto.randomUUID();ids.push(id);sql.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,?,?,?,?,?,?)').run(id,parent,'Image '+String(i).padStart(3,'0'),'image/jpeg',1,'originals/'+id,'fixture','fixture','2026-10-19T00:00:00Z','2026-10-19T00:00:00Z');}
 const first=await (await m.gallery.GET(req('/api/media?folder='+parent,undefined,photoToken,'GET'))).json();assert.equal(first.items.length,100);assert(first.nextPageToken.startsWith('k1.'));
 sql.prepare('DELETE FROM jac_media_r2_entries WHERE id=?').run(first.items[0].id);
 const inserted='r2_'+crypto.randomUUID();sql.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,?,?,?,?,?,?)').run(inserted,parent,'Newest','image/jpeg',1,'originals/'+inserted,'fixture','fixture','2026-10-20T00:00:00Z','2026-10-20T00:00:00Z');
 const second=await (await m.gallery.GET(req('/api/media?folder='+parent+'&pageToken='+encodeURIComponent(first.nextPageToken),undefined,photoToken,'GET'))).json();assert.equal(second.items.length,100);assert(!second.items.some(item=>first.items.some(old=>old.id===item.id)));assert.equal(second.items[0].name,'Image 100');
 const third=await (await m.gallery.GET(req('/api/media?folder='+parent+'&pageToken='+encodeURIComponent(second.nextPageToken),undefined,photoToken,'GET'))).json();assert.equal(third.items.length,5);assert.equal(new Set([...first.items,...second.items,...third.items].map(item=>item.id)).size,205);
 const other=await folder();assert.equal((await m.gallery.GET(req('/api/media?folder='+other+'&pageToken='+encodeURIComponent(first.nextPageToken),undefined,photoToken,'GET'))).status,409);
});

test('concurrent private HLS readers share one provider signing request without bypassing their live access checks',async()=>{
 const {id}=await videoFixture(),info=await readyVideo(id);const responses=await Promise.all(Array.from({length:8},()=>leased(info.url)));for(const response of responses){assert.equal(response.status,200);await response.text();}assert.equal(streamCalls.filter(call=>call.url.pathname.endsWith('/token')).length,1);
});

test('a reserved preview registers its background lifetime and stays private if its viewer leaves',async()=>{
 const {id}=await photoPreviewFixture();let release,begun;const entered=new Promise(resolve=>begun=resolve),output=new Promise(resolve=>release=resolve);
 globalThis.__r2Fixture.IMAGES={input:()=>({transform:()=>({output:()=>{begun();return output;}})})};
 const abort=new AbortController(),request=req('/api/media/file?id='+id+'&preview=1',undefined,photoToken,'GET');
 const response=m.files.GET(new Request(request,{signal:abort.signal}));await entered;assert.equal(globalThis.__r2Background.length,1);abort.abort();release({response:()=>new Response(sizedJPEG(2400),{headers:{'content-type':'image/jpeg'}})});
 await globalThis.__r2Background[0];assert.equal((await response).status,200);assert.equal(sql.prepare('SELECT preview_key,claim FROM jac_media_presentations WHERE file_id=?').get(id).claim,'');assert(objects.has('previews/'+id.slice(3)+'.jpg'));
});
test('a stuck image transform times out, releases its reservation, and cannot publish a late result',async t=>{
 const {id}=await photoPreviewFixture();let release,begun;const entered=new Promise(resolve=>begun=resolve),output=new Promise(resolve=>release=resolve);
 globalThis.__r2Fixture.IMAGES={input:()=>({transform:()=>({output:()=>{begun();return output;}})})};t.mock.timers.enable({apis:['setTimeout']});
 try{const first=photoPreview(id);await entered;t.mock.timers.tick(20000);const response=await first;assert.equal(response.status,503);const body=await response.json();assert.equal(body.code,'preview_timeout');assert.equal(response.headers.get('Retry-After'),'60');assert(!JSON.stringify(body).includes('Error:'));
  assert.equal(sql.prepare('SELECT claim FROM jac_media_presentations WHERE file_id=?').get(id).claim,'');release({response:()=>new Response(sizedJPEG(2400))});await new Promise(resolve=>setImmediate(resolve));assert(!objects.has('previews/'+id.slice(3)+'.jpg'));assert(objects.has('originals/'+id.slice(3)));
 }finally{t.mock.timers.reset();}
});
test('a cooling-down failed preview returns a readable error without downloading another original',async()=>{
 const {id}=await photoPreviewFixture();previewImages(()=>{throw Error('upstream private failure');});await photoPreview(id);const before=calls.length;
 const response=await photoPreview(id),body=await response.json();assert.equal(response.status,503);assert.equal(body.code,'preview_unavailable');assert.equal(response.headers.get('Retry-After'),'60');assert(body.error.includes('vista previa'));assert(!JSON.stringify(body).includes('upstream private failure'));assert.equal(calls.length,before);
});

test('concurrent preview readers receive a bounded preparing state while the reserved worker continues',async t=>{
 const {id}=await photoPreviewFixture();let release,begun,locked;const entered=new Promise(resolve=>begun=resolve),output=new Promise(resolve=>release=resolve),secondLock=new Promise(resolve=>locked=resolve);
 globalThis.__r2Fixture.IMAGES={input:()=>({transform:()=>({output:()=>{begun();return output;}})})};t.mock.timers.enable({apis:['setTimeout']});
 let first;
 try{first=photoPreview(id);await entered;beforeQuery=q=>{if(q.text.startsWith('UPDATE jac_media_presentations SET claim=?,claim_at=? WHERE file_id='))locked();};const second=photoPreview(id);await secondLock;await new Promise(resolve=>setImmediate(resolve));
  for(let i=0;i<8;i++){t.mock.timers.tick(750);await new Promise(resolve=>setImmediate(resolve));}
  const response=await second;assert.equal(response.status,503);assert.equal((await response.json()).code,'preview_preparing');assert.equal(response.headers.get('Retry-After'),'1');assert.equal(globalThis.__r2Background.length,1);
 }finally{beforeQuery=undefined;release({response:()=>new Response(sizedJPEG(2400))});if(first)assert.equal((await first).status,200);t.mock.timers.reset();}
});
