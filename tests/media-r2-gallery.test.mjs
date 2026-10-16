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
const bundled=await build({stdin:{contents:"export * from './lib/media-r2';export * from './lib/media-r2-gallery';export * from './lib/media-r2-s3';export * from './lib/media-upload-client';export * from './lib/media-drive';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export {decryptMail} from './lib/payroll-mail-core';export * as api from './app/api/media/storage/route';export * as gallery from './app/api/media/route';export * as files from './app/api/media/file/route';export * as uploads from './app/api/media/upload/route';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'r2-fixtures',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__r2Fixture;':'export const headers=async()=>globalThis.__r2Headers;',loader:'js'}));}}]});
const dir=await mkdtemp(resolve('work/r2-fixture-')),file=dir+'/fixture.mjs';await writeFile(file,bundled.outputFiles[0].contents);const m=await import(pathToFileURL(file).href);await rm(dir,{recursive:true});
const ownerID=await m.bootstrapOwner('independent-new-gallery-owner','fixture'),photographer=crypto.randomUUID(),stamp=new Date().toISOString();
sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)').run(photographer,'new-photo','photo@example.invalid','Fotógrafo ficticio','fixture','[]',1,stamp,stamp);
const input={accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64),version:0},origin='https://r2.example.invalid',host=input.accountId+'.r2.cloudflarestorage.com';
const jpeg=new Uint8Array([255,216,255,192,0,11,8,0,16,0,16,1,1,17,0,255,217]);
let token,photoToken,calls,objects,multiparts,hook,loseComplete;
beforeEach(async()=>{
 beforeQuery=undefined;hook=undefined;loseComplete=false;calls=[];objects=new Map();multiparts=new Map();sql.exec('DELETE FROM jac_media_r2_entries;DELETE FROM jac_media_operations;DELETE FROM jac_media_r2_connection;UPDATE payroll_users SET active=1');token=await m.makeSession(ownerID);photoToken=await m.makeSession(photographer);
 sql.prepare("INSERT OR REPLACE INTO jac_media_connection(id,credentials,email,version,updated_at) VALUES('jac','previous-photo-drive','jacmusicestudios@gmail.com',7,?)").run(stamp);
 globalThis.fetch=async(request,options={})=>{
  const r=request instanceof Request?request:new Request(request,options),url=new URL(r.url);assert.equal(url.hostname,host,'No Google, Drive, redirect or other network destination is allowed');assert.ok(url.pathname.startsWith('/jac-fotografia'));assert.equal(r.headers.has('cookie'),false);assert.equal(r.headers.has('origin'),false);
  const direct=url.searchParams.has('X-Amz-Signature');if(direct){assert.equal(r.method,'PUT');assert.equal(r.headers.has('authorization'),false);assert.equal(r.headers.has('content-range'),false);assert.equal(options.credentials,'omit');assert.equal(options.referrerPolicy,'no-referrer');}else{assert.equal(r.redirect,'manual');assert.match(r.headers.get('authorization'),/^AWS4-HMAC-SHA256 Credential=/);}
  calls.push({url,method:r.method,direct});if(hook){const response=await hook(r);if(response)return response;}
  const key=url.pathname.slice('/jac-fotografia/'.length),uploadId=url.searchParams.get('uploadId');
  if(url.pathname==='/jac-fotografia'&&r.method==='HEAD')return new Response(null);
  if(r.method==='POST'&&url.searchParams.has('uploads')){const id='fixture-'+crypto.randomUUID();multiparts.set(id,{key,mime:r.headers.get('content-type'),request:r.headers.get('x-amz-meta-jac-request'),parts:new Map()});return new Response('<InitiateMultipartUploadResult><UploadId>'+id+'</UploadId></InitiateMultipartUploadResult>');}
  const upload=multiparts.get(uploadId);
  if(direct){assert.ok(upload);const bytes=new Uint8Array(await r.arrayBuffer());upload.parts.set(Number(url.searchParams.get('partNumber')),bytes);return new Response(null,{headers:{ETag:'"'+'a'.repeat(32)+'"'}});}
  if(uploadId&&r.method==='GET'){if(!upload)return new Response(null,{status:404});return new Response('<ListPartsResult><IsTruncated>false</IsTruncated>'+[...upload.parts].sort(([a],[b])=>a-b).map(([n,b])=>'<Part><PartNumber>'+n+'</PartNumber><Size>'+b.length+'</Size><ETag>"'+'a'.repeat(32)+'"</ETag></Part>').join('')+'</ListPartsResult>');}
  if(uploadId&&r.method==='POST'){assert.ok(upload);const bytes=new Uint8Array([...upload.parts.values()].reduce((n,b)=>n+b.length,0));let p=0;for(const b of upload.parts.values()){bytes.set(b,p);p+=b.length;}objects.set(key,{bytes,mime:upload.mime,request:upload.request});multiparts.delete(uploadId);if(loseComplete){loseComplete=false;throw new Error('simulated lost completion response');}return new Response('<CompleteMultipartUploadResult><Key>'+key+'</Key></CompleteMultipartUploadResult>');}
  if(uploadId&&r.method==='DELETE'){multiparts.delete(uploadId);return new Response(null,{status:204});}
  if(r.method==='PUT'){objects.set(key,{bytes:new Uint8Array(await r.arrayBuffer()),mime:r.headers.get('content-type')});return new Response(null);}
  const object=objects.get(key);if(!object)return new Response(null,{status:404});const headers={'content-type':object.mime,'content-length':String(object.bytes.length),...(object.request?{'x-amz-meta-jac-request':object.request}:{})};if(r.method==='HEAD')return new Response(null,{headers});
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
async function start(bytes=jpeg,parentId=m.R2_ROOT,id=crypto.randomUUID(),mimeType='image/jpeg'){const data={action:'start',transport:'direct',id,parentId,filename:mimeType==='image/png'?'Foto.png':'Foto.jpg',mimeType,size:bytes.length};const r=await command(data);assert.equal(r.status,200);return {data,plan:await r.json(),bytes};}
async function send(upload){const p=upload.plan,bytes=upload.bytes.slice(p.offset,Math.min(p.offset+p.chunkSize,upload.bytes.length));await m.sendMediaDirectChunk(p.uploadURL,upload.data.mimeType,new Blob([bytes]),p.offset,upload.bytes.length,new AbortController().signal);const r=await command({action:'status',transport:'direct',id:p.id});return r;}

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
