import assert from 'node:assert/strict';
import test,{beforeEach} from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {build} from 'esbuild';

// Isolated D1 and simulated Google. This suite cannot reach any real service.
const sql=new DatabaseSync(':memory:');
for(const f of (await readdir('drizzle')).filter(f=>f.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+f,'utf8'));
let beforeQuery;
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};return {results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async run(){if(beforeQuery)await beforeQuery(this);return this.execute();}async all(){return this.execute();}async first(){if(beforeQuery)await beforeQuery(this);return sql.prepare(this.text).get(...this.args)||null;}
}
const db={prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const out=qs.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}};
globalThis.__mediaDriveEnv={DB:db,PAYROLL_AUTH_KEY:'media-drive-separate-fixture-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,6).toString('base64url')};
globalThis.__mediaDriveHeaders=new Headers();
const code="export * from './lib/media-core';export * from './lib/media-drive';export * from './lib/media-oauth';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export {encryptMail,decryptMail} from './lib/payroll-mail-core';export {saveMailCredentials} from './lib/payroll-mail';export * as api from './app/api/media/route';export * as fileApi from './app/api/media/file/route';export * as uploadApi from './app/api/media/upload/route';";
const bundle=await build({stdin:{contents:code,resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'fixture-platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__mediaDriveEnv;export const waitUntil=()=>{};':'export const headers=async()=>globalThis.__mediaDriveHeaders;',loader:'js'}));}}]});
const testDir=await mkdtemp(resolve('work/media-drive-tests-')),testModule=testDir+'/fixture.mjs';await writeFile(testModule,bundle.outputFiles[0].contents);const m=await import(pathToFileURL(testModule).href);await rm(testDir,{recursive:true});
const ownerID=await m.bootstrapOwner('media-owner-fixture','fixture'),photoID=crypto.randomUUID(),readerID=crypto.randomUUID(),stamp=new Date().toISOString();
sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)').run(photoID,'photo-fixture','photo@example.invalid','Fotógrafo ficticio','fixture','[]',1,stamp,stamp);
sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run(readerID,'reader-fixture','reader@example.invalid','Lector ficticio','fixture','[]',stamp,stamp);
const base='https://media.example.invalid',folderID='folder_inside_fixture',imageID='image_inside_fixture',outsideID='folder_outside_fixture';
let ownerToken,photoToken,readerToken,files,sessions,calls,hook,sequence,account;
const folder=(id,name,parents=[])=>({id,name,mimeType:m.MEDIA_FOLDER_MIME,parents,capabilities:{canAddChildren:true},trashed:false});
beforeEach(async()=>{
 beforeQuery=undefined;hook=undefined;calls=[];sequence=0;account={email:'jacmusicestudios@gmail.com',email_verified:true};files=new Map([[m.MEDIA_ROOT_ID,folder(m.MEDIA_ROOT_ID,'Raíz ficticia')],[folderID,folder(folderID,'2026-10-16 · Show ficticio',[m.MEDIA_ROOT_ID])],[outsideID,folder(outsideID,'Ajena')],[imageID,{id:imageID,name:'Foto ficticia.jpg',mimeType:'image/jpeg',parents:[folderID],size:'12',thumbnailLink:'https://lh3.googleusercontent.com/fixture-preview',capabilities:{canDownload:true},trashed:false}]]);sessions=new Map();
 sql.prepare('DELETE FROM jac_media_operations').run();sql.prepare('DELETE FROM payroll_oauth').run();sql.prepare('UPDATE payroll_users SET active=1,media_only=1 WHERE id=?').run(photoID);
 ownerToken=await m.makeSession(ownerID);photoToken=await m.makeSession(photoID);readerToken=await m.makeSession(readerID);
 await m.saveMailCredentials('media-fixture.apps.googleusercontent.com','fixture-client-secret');await m.ensureMediaConfig();
 const cipher=await m.encryptMail({clientId:'media-fixture.apps.googleusercontent.com',clientSecret:'fixture-client-secret',refreshToken:'fixture-drive-refresh',scopes:[m.MEDIA_SCOPE]},globalThis.__mediaDriveEnv.PAYROLL_MAIL_KEY);
 sql.prepare("UPDATE jac_media_connection SET credentials=?,email='jacmusicestudios@gmail.com',version=version+1 WHERE id='jac'").run(cipher);
});
function req(token=photoToken,path='/api/media',extra={}){const cookie='__Host-jac_session='+token;globalThis.__mediaDriveHeaders=new Headers({host:'media.example.invalid',cookie});return new Request(base+path,{headers:{origin:base,cookie,...extra}});}
async function guard(token=photoToken,mode='upload'){return m.mediaGuard(req(token),await m.authenticatedSession(token),mode);}
const empty308=offset=>new Response(null,{status:308,headers:offset?{Range:'bytes=0-'+(offset-1)}:{}});
globalThis.fetch=async(input,options={})=>{
 const url=new URL(String(input)),headers=new Headers(options.headers),entry={url,headers,options,method:options.method||'GET'};calls.push(entry);
 assert.ok(['https://oauth2.googleapis.com','https://openidconnect.googleapis.com','https://www.googleapis.com','https://lh3.googleusercontent.com'].includes(url.origin),'Unexpected traffic blocked');
 const next=async()=>{
  if(url.origin==='https://oauth2.googleapis.com')return Response.json({access_token:'fixture-access',refresh_token:'fixture-refresh',scope:'openid email '+m.MEDIA_SCOPE});
  if(url.origin==='https://openidconnect.googleapis.com')return Response.json(account);
  if(url.origin==='https://lh3.googleusercontent.com'){assert.equal(headers.get('authorization'),'Bearer fixture-access');return new Response(new Uint8Array([255,216,255,1]),{headers:{'content-type':'image/jpeg'}});}
  assert.equal(options.redirect,'manual');assert.equal(headers.get('authorization'),'Bearer fixture-access');
  if(url.pathname.endsWith('/generateIds'))return Response.json({ids:['reserved_fixture_'+(++sequence)]});
  if(url.pathname==='/upload/drive/v3/files'&&entry.method==='POST'){
   const metadata=JSON.parse(options.body),id='fixture_session_'+sessions.size; sessions.set(id,{metadata,offset:0,size:Number(headers.get('X-Upload-Content-Length'))});
   return new Response(null,{status:200,headers:{Location:'https://www.googleapis.com/upload/drive/v3/files?upload_id='+id}});
  }
  if(url.pathname==='/upload/drive/v3/files'&&entry.method==='PUT'){
   const session=sessions.get(url.searchParams.get('upload_id'));if(!session)return new Response(null,{status:404});const range=headers.get('Content-Range');
   if(range.startsWith('bytes */'))return session.offset===session.size?Response.json(files.get(session.metadata.id)):empty308(session.offset);
   const match=range.match(/^bytes (\d+)-(\d+)\/(\d+)$/);assert.ok(match);const [,start,end,total]=match.map(Number);assert.equal(total,session.size);assert.equal(options.body.byteLength,end-start+1);
   if(start!==session.offset)return new Response(null,{status:400});session.offset=end+1;
   if(session.offset<session.size)return empty308(session.offset);
   const final={...session.metadata,size:String(session.size),trashed:false,capabilities:{canDownload:true}};files.set(final.id,final);return Response.json(final,{status:201});
  }
  if(url.pathname==='/drive/v3/files'&&entry.method==='POST'){const body=JSON.parse(options.body),f={...body,trashed:false,capabilities:{canAddChildren:true}};files.set(body.id,f);return Response.json(f);}
  if(url.pathname==='/drive/v3/files'&&entry.method==='GET'){const parent=url.searchParams.get('q')?.match(/^'([^']+)' in parents/)?.[1];return Response.json({files:[...files.values()].filter(f=>f.parents?.includes(parent))});}
  const id=url.pathname.match(/^\/drive\/v3\/files\/([A-Za-z0-9_-]+)$/)?.[1],f=files.get(id);if(!f)return new Response(null,{status:404});
  if(url.searchParams.get('alt')==='media'){
   const range=headers.get('range');if(range){const match=range.match(/^bytes=(\d+)-(\d+)$/);if(match&&Number(match[1])<=Number(match[2])&&Number(match[2])<Number(f.size)){const start=Number(match[1]),end=Number(match[2]);return new Response(new Uint8Array(end-start+1),{status:206,headers:{'Content-Type':f.mimeType,'Content-Range':`bytes ${start}-${end}/${f.size}`,'Content-Length':String(end-start+1)}});}return new Response(null,{status:416,headers:{'Content-Range':'bytes */'+f.size}});}
   return new Response(new Uint8Array(Number(f.size)),{headers:{'Content-Type':f.mimeType}});
  }
  return Response.json(f);
 };
 return hook?hook(entry,next):next();
};
const input=(overrides={})=>({id:crypto.randomUUID(),parentId:folderID,filename:'foto-ficticia.png',mimeType:'image/png',size:m.MEDIA_CHUNK_SIZE+13,...overrides});
const chunk=()=>{const bytes=new Uint8Array(m.MEDIA_CHUNK_SIZE);bytes.set([137,80,78,71,13,10,26,10]);return bytes;};
const fails=status=>e=>e instanceof m.MediaFailure&&e.status===status;

test('Google permission revocation remains 403 so native caches cannot treat it as an outage',async()=>{
 const g=await guard(ownerToken,'read');
 for(const status of [401,403]){hook=async(entry,next)=>entry.url.pathname.includes('/drive/v3/files/')?Response.json({error:{errors:[{reason:'insufficientFilePermissions'}]}},{status}):next();await assert.rejects(()=>m.mediaFile(g,imageID,false,null),fails(403));}
 hook=async(entry,next)=>entry.url.origin==='https://oauth2.googleapis.com'?Response.json({error:'invalid_grant'},{status:400}):next();await assert.rejects(()=>m.mediaContext(g),fails(403));
 hook=async(entry,next)=>entry.url.pathname.includes('/drive/v3/files/')?Response.json({error:{errors:[{reason:'userRateLimitExceeded'}]}},{status:403}):next();await assert.rejects(()=>m.mediaFile(g,imageID,false,null),fails(503));
});

test('folder creation recovers a lost Google response without duplicating its reserved ID',async()=>{
 const g=await guard(),record={id:crypto.randomUUID(),parentId:folderID,name:'Show ficticio',date:'2026-10-16'};let lost=true;
 hook=async(entry,next)=>{const response=await next();if(lost&&entry.url.pathname==='/drive/v3/files'&&entry.method==='POST'){lost=false;throw new Error('Simulated lost response after Google commit');}return response;};
 await assert.rejects(()=>m.createMediaFolder(g,record),fails(502));assert.equal([...files.values()].filter(f=>f.name==='2026-10-16 · Show ficticio').length,2,'Existing parent and one newly created folder');
 const recovered=await m.createMediaFolder(g,record),again=await m.createMediaFolder(g,record);assert.deepEqual(again,recovered);assert.equal(calls.filter(c=>c.url.pathname==='/drive/v3/files'&&c.method==='POST').length,1);
 assert.equal(sql.prepare('SELECT status FROM jac_media_operations WHERE id=?').get(record.id).status,'ready');
 await assert.rejects(()=>m.createMediaFolder(g,{...record,name:'Otro nombre'}),fails(409));
});
test('uploads accept two chunks, reconcile response loss, and never expose the resumable URL or credentials',async()=>{
 const g=await guard(),record=input(),start=await m.startMediaUpload(g,record);assert.equal(start.offset,0);assert.equal(start.chunkSize,m.MEDIA_CHUNK_SIZE);assert.ok(!JSON.stringify(start).includes('upload_id'));
 let lost=true;hook=async(entry,next)=>{const response=await next();if(lost&&entry.method==='PUT'&&!entry.headers.get('Content-Range').startsWith('bytes */')){lost=false;throw new Error('Lost chunk response');}return response;};
 await assert.rejects(()=>m.appendMediaUpload(g,record.id,0,chunk()),fails(502));assert.equal(sql.prepare('SELECT offset FROM jac_media_operations WHERE id=?').get(record.id).offset,0);
 const resumed=await m.mediaUploadStatus(g,record.id);assert.equal(resumed.offset,m.MEDIA_CHUNK_SIZE);assert.equal(resumed.complete,false);
 await assert.rejects(()=>m.appendMediaUpload(g,record.id,0,chunk()),fails(409));
 const done=await m.appendMediaUpload(g,record.id,resumed.offset,new Uint8Array(13));assert.equal(done.complete,true);assert.equal(done.offset,record.size);assert.deepEqual(await m.mediaUploadStatus(g,record.id),done);assert.deepEqual(await m.startMediaUpload(g,record),done);
 assert.equal([...files.values()].filter(f=>f.name===record.filename).length,1);const row=sql.prepare('SELECT * FROM jac_media_operations WHERE id=?').get(record.id);assert.ok(!row.session_payload.includes('upload_id'));assert.ok(!row.session_payload.includes('fixture-access'));assert.equal(calls.filter(c=>c.method==='POST'&&c.url.pathname==='/upload/drive/v3/files').length,1);
});
test('a stale upload cannot acquire the lock after another request advances its offset',async()=>{
 const g=await guard(),record=input();await m.startMediaUpload(g,record);let changed=false;const before=calls.length;
 beforeQuery=async q=>{if(!changed&&q.text.startsWith('UPDATE jac_media_operations SET claim=')){changed=true;sql.prepare('UPDATE jac_media_operations SET offset=? WHERE id=?').run(m.MEDIA_CHUNK_SIZE,record.id);[...sessions.values()][0].offset=m.MEDIA_CHUNK_SIZE;}};
 await assert.rejects(()=>m.appendMediaUpload(g,record.id,0,chunk()),fails(409));beforeQuery=undefined;
 assert.equal(sql.prepare('SELECT offset FROM jac_media_operations WHERE id=?').get(record.id).offset,m.MEDIA_CHUNK_SIZE);assert.equal(calls.slice(before).filter(c=>c.url.pathname.startsWith('/upload/')&&c.method==='PUT').length,0);
});
test('a lost final response is recovered even when Google closes its resumable session',async()=>{
 const g=await guard(),record=input({size:13});await m.startMediaUpload(g,record);const bytes=new Uint8Array(13);bytes.set([137,80,78,71,13,10,26,10]);let lost=true;
 hook=async(entry,next)=>{const r=await next();if(lost&&entry.method==='PUT'&&!entry.headers.get('Content-Range').startsWith('bytes */')){lost=false;sessions.clear();throw new Error('Lost final response; session already closed by Google');}return r;};
 await assert.rejects(()=>m.appendMediaUpload(g,record.id,0,bytes),fails(502));assert.equal(sql.prepare('SELECT status FROM jac_media_operations WHERE id=?').get(record.id).status,'pending');
 const recovered=await m.mediaUploadStatus(g,record.id);assert.equal(recovered.complete,true);assert.equal(recovered.offset,13);assert.equal([...files.values()].filter(f=>f.name===record.filename).length,1);
});
test('upload validates signatures, bounds, ownership, and Google progress without committing invalid chunks',async()=>{
 const g=await guard(),record=input();await m.startMediaUpload(g,record);const before=calls.length;
 for(const [offset,bytes,status] of [[0,new Uint8Array(m.MEDIA_CHUNK_SIZE),400],[1,chunk(),409],[0,new Uint8Array(13),409],[0,new Uint8Array(m.MEDIA_CHUNK_SIZE+1),409]])await assert.rejects(()=>m.appendMediaUpload(g,record.id,offset,bytes),fails(status));
 assert.equal(calls.slice(before).filter(c=>c.url.pathname.startsWith('/upload/')&&c.method==='PUT').length,0);
 hook=async(entry,next)=>entry.method==='PUT'?new Response(null,{status:308,headers:{Range:'bytes=0-99999999999999'}}):next();await assert.rejects(()=>m.mediaUploadStatus(g,record.id),fails(502));assert.equal(sql.prepare('SELECT offset FROM jac_media_operations WHERE id=?').get(record.id).offset,0);
 assert.throws(()=>m.mediaGuard(req(ownerToken),{id:ownerID,email:m.OWNER_EMAIL,isOwner:true,permissions:[]},'upload'),fails(403));
 assert.throws(()=>m.mediaGuard(req(readerToken),{id:readerID,isOwner:false,permissions:[]},'read'),fails(403));
});
test('parent traversal rejects external roots, shortcuts, cycles and files moved outside JAC',async()=>{
 const g=await guard();await assert.rejects(()=>m.createMediaFolder(g,{id:crypto.randomUUID(),parentId:outsideID,name:'Fuera',date:'2026-10-16'}),fails(403));
 files.set('shortcut_fixture',{...folder('shortcut_fixture','Acceso directo',[m.MEDIA_ROOT_ID]),shortcutDetails:{targetId:outsideID}});await assert.rejects(async()=>m.mediaFeed(g,await m.authenticatedSession(photoToken),'shortcut_fixture'),fails(404));
 files.set('cycle_a_fixture',folder('cycle_a_fixture','A',['cycle_b_fixture']));files.set('cycle_b_fixture',folder('cycle_b_fixture','B',['cycle_a_fixture']));await assert.rejects(()=>m.createMediaFolder(g,{id:crypto.randomUUID(),parentId:'cycle_a_fixture',name:'Ciclo',date:'2026-10-16'}),fails(403));
 files.get(imageID).parents=[outsideID];await assert.rejects(()=>m.mediaFile(g,imageID,false,null),fails(403));assert.equal(calls.filter(c=>c.url.searchParams.get('alt')==='media').length,0);
});
test('downloads revalidate membership after fetching and preserve valid partial content',async()=>{
 const g=await guard(ownerToken,'read');const response=await m.mediaFile(g,imageID,false,'bytes=2-5');assert.equal(response.status,206);assert.equal(response.headers.get('content-range'),'bytes 2-5/12');assert.equal((await response.arrayBuffer()).byteLength,4);
 assert.throws(()=>m.mediaRange('bytes=0-1,4-5'),fails(416));assert.throws(()=>m.mediaRange('bytes=1-2\r\nHost: bad'),fails(416));
 assert.throws(()=>m.mediaRange('bytes=5-2'),fails(416));assert.throws(()=>m.mediaRange('bytes=-0'),fails(416));assert.throws(()=>m.mediaRange('bytes=9007199254740992-'),fails(416));await assert.rejects(()=>m.mediaFile(g,imageID,false,'bytes=99-100'),fails(416));
 hook=async(entry,next)=>{const r=await next();if(entry.url.searchParams.get('alt')==='media')files.get(imageID).parents=[outsideID];return r;};await assert.rejects(()=>m.mediaFile(g,imageID,false,null),fails(403));
});
test('Google redirects and unsafe thumbnail URLs are rejected without forwarding credentials',async()=>{
 const g=await guard(ownerToken,'read');hook=async(entry,next)=>entry.url.searchParams.get('alt')==='media'?new Response(null,{status:307,headers:{Location:'https://untrusted.example.invalid/file'}}):next();await assert.rejects(()=>m.mediaFile(g,imageID,false,null),fails(502));
 hook=undefined;files.get(imageID).thumbnailLink='https://googleusercontent.com.untrusted.example.invalid/preview';await assert.rejects(()=>m.mediaFile(g,imageID,true,null),fails(502));assert.ok(calls.every(c=>!c.url.hostname.includes('untrusted')));
 files.get(imageID).thumbnailLink='https://lh3.googleusercontent.com/fixture-preview';const thumbnail=await m.mediaFile(g,imageID,true,null);assert.equal(thumbnail.status,200);assert.equal(calls.find(c=>c.url.hostname==='lh3.googleusercontent.com').headers.get('authorization'),'Bearer fixture-access');
 hook=async(entry,next)=>entry.url.hostname==='lh3.googleusercontent.com'?new Response(null,{status:302,headers:{Location:'https://untrusted.example.invalid/preview'}}):next();await assert.rejects(()=>m.mediaFile(g,imageID,true,null),fails(502));assert.ok(calls.every(c=>!c.url.hostname.includes('untrusted')));
});
test('resumable locations outside the Google upload endpoint never get stored or followed',async()=>{
 const g=await guard(),record=input();hook=async(entry,next)=>entry.url.pathname==='/upload/drive/v3/files'&&entry.method==='POST'?new Response(null,{headers:{Location:'https://untrusted.example.invalid/upload?upload_id=fixture'}}):next();
 await assert.rejects(()=>m.startMediaUpload(g,record),fails(502));assert.equal(sql.prepare('SELECT session_payload FROM jac_media_operations WHERE id=?').get(record.id).session_payload,'');assert.ok(calls.every(c=>!c.url.hostname.includes('untrusted')));
});
test('session revocation during Google prevents folder commits and content delivery',async()=>{
 const g=await guard();let revoked=false;hook=async(entry,next)=>{const r=await next();if(!revoked&&entry.url.pathname==='/drive/v3/files/generateIds'){revoked=true;sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(photoID);}return r;};
 await assert.rejects(()=>m.createMediaFolder(g,{id:crypto.randomUUID(),parentId:folderID,name:'Revocado',date:'2026-10-16'}),fails(403));assert.equal(calls.filter(c=>c.url.pathname==='/drive/v3/files'&&c.method==='POST').length,0);
 const readGuard=await guard(ownerToken,'read');hook=async(entry,next)=>{const r=await next();if(entry.url.searchParams.get('alt')==='media')sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(ownerToken));return r;};await assert.rejects(()=>m.mediaFile(readGuard,imageID,false,null),fails(403));
});
async function beginOauth(){const request=req(ownerToken),owner=await m.authenticatedSession(ownerToken),start=await m.startMediaOauth(request,owner),url=new URL(start.url),browserCookie=start.cookie.split(';')[0];return {start,url,callback:()=>new Request('https://jhonalexcastano.com/api/payroll/gmail/callback?state='+url.searchParams.get('state')+'&code=fixture-code',{headers:{cookie:'__Host-jac_session='+ownerToken+'; '+browserCookie}})};}
test('OAuth uses PKCE and dedicated account, binds browser/session, consumes once, and preserves other Google connections',async()=>{
 const oldGmail=sql.prepare("SELECT * FROM payroll_gmail WHERE id='jac'").get(),begun=await beginOauth();assert.equal(begun.url.searchParams.get('login_hint'),'jacmusicestudios@gmail.com');assert.equal(begun.url.searchParams.get('code_challenge_method'),'S256');assert.ok(begun.url.searchParams.get('scope').includes(m.MEDIA_SCOPE));
 account={email:'wrong@example.invalid',email_verified:true};const bad=await m.finishMediaOauth(begun.callback());assert.match(bad.url,/drive=error(?:&|$)/);assert.deepEqual(sql.prepare("SELECT * FROM payroll_gmail WHERE id='jac'").get(),oldGmail);assert.equal(await m.finishMediaOauth(begun.callback()),null);
 account={email:'jacmusicestudios@gmail.com',email_verified:true};const good=await beginOauth(),revision=(await m.mediaConfig()).version,result=await m.finishMediaOauth(good.callback());assert.match(result.url,/drive=connected$/);assert.equal((await m.mediaConfig()).version,revision+1);assert.equal(await m.finishMediaOauth(good.callback()),null);assert.deepEqual(sql.prepare("SELECT * FROM payroll_gmail WHERE id='jac'").get(),oldGmail);
 const secret=await m.decryptMail((await m.mediaConfig()).credentials,globalThis.__mediaDriveEnv.PAYROLL_MAIL_KEY);assert.equal(secret.refreshToken,'fixture-refresh');assert.ok(!JSON.stringify(result).includes('fixture-refresh'));
});
test('OAuth rejects missing browser proof, incomplete scope, concurrent replay and revoked sessions',async()=>{
 let begun=await beginOauth(),before=calls.length,revision=(await m.mediaConfig()).version;
 const forged=new Request(begun.callback().url,{headers:{cookie:'__Host-jac_session='+ownerToken}});assert.match((await m.finishMediaOauth(forged)).url,/drive=error(?:&|$)/);assert.equal(calls.length,before);assert.equal((await m.mediaConfig()).version,revision);
 const valid=await m.finishMediaOauth(begun.callback());assert.match(valid.url,/drive=connected$/);
 begun=await beginOauth();revision=(await m.mediaConfig()).version;hook=async(entry,next)=>entry.url.origin==='https://oauth2.googleapis.com'?Response.json({access_token:'fixture-access',refresh_token:'fixture-refresh',scope:'openid email'}):next();assert.match((await m.finishMediaOauth(begun.callback())).url,/drive=error(?:&|$)/);assert.equal((await m.mediaConfig()).version,revision);
 hook=undefined;begun=await beginOauth();before=calls.filter(c=>c.url.origin==='https://oauth2.googleapis.com').length;const concurrent=await Promise.all([m.finishMediaOauth(begun.callback()),m.finishMediaOauth(begun.callback())]);assert.equal(concurrent.filter(v=>v?.url.endsWith('drive=connected')).length,1);assert.equal(calls.filter(c=>c.url.origin==='https://oauth2.googleapis.com').length,before+1);
 begun=await beginOauth();before=calls.length;sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(ownerToken));assert.match((await m.finishMediaOauth(begun.callback())).url,/drive=error(?:&|$)/);assert.equal(calls.length,before);
});
test('OAuth diagnostics distinguish each authorization failure with only allowlisted reasons',async()=>{
 const expected=['browser_guard_missing','browser_guard_mismatch','web_session_missing','web_session_changed','authorization_used','expired','session_revoked','google_denied','missing_code','configuration_changed','google_token','google_account','folder_access','connection_storage'];
 const oldLog=console.error,logs=[],tag='untrusted-provider-body-cookie-or-secret';console.error=(...args)=>logs.push(args);
 try{
  for(const reason of expected){
   const begun=await beginOauth();let callback=begun.callback(),cleanup=async()=>{};
   const cookie=callback.headers.get('cookie'),browser=cookie.split(';').map(v=>v.trim()).find(v=>v.startsWith('__Host-jac_media_oauth='));
   assert.match(begun.start.cookie,/Path=\/; HttpOnly; Secure; SameSite=Lax; Max-Age=600$/,'The protected browser cookie keeps its ten-minute lifetime');
   if(reason==='browser_guard_missing')callback=new Request(callback.url,{headers:{cookie:'__Host-jac_session='+ownerToken}});
   if(reason==='browser_guard_mismatch')callback=new Request(callback.url,{headers:{cookie:'__Host-jac_session='+ownerToken+'; __Host-jac_media_oauth='+'x'.repeat(43)}});
   if(reason==='web_session_missing')callback=new Request(callback.url,{headers:{cookie:browser}});
   if(reason==='web_session_changed')callback=new Request(callback.url,{headers:{cookie:'__Host-jac_session='+await m.makeSession(ownerID)+'; '+browser}});
   if(reason==='authorization_used')beforeQuery=async q=>{if(q.text.startsWith('DELETE FROM payroll_oauth WHERE id=? AND payload=?'))sql.prepare('DELETE FROM payroll_oauth WHERE id=?').run(q.args[0]);};
   if(reason==='expired')sql.prepare('UPDATE payroll_oauth SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z','jac-media:'+begun.url.searchParams.get('state'));
   if(reason==='session_revoked'){sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(ownerID);cleanup=async()=>sql.prepare('UPDATE payroll_users SET active=1 WHERE id=?').run(ownerID);}
   if(reason==='google_denied'){const url=new URL(callback.url);url.searchParams.set('error','access_denied');url.searchParams.set('error_description',tag);callback=new Request(url,{headers:callback.headers});}
   if(reason==='missing_code'){const url=new URL(callback.url);url.searchParams.delete('code');callback=new Request(url,{headers:callback.headers});}
   if(reason==='configuration_changed')sql.prepare("UPDATE jac_media_connection SET version=version+1 WHERE id='jac'").run();
   if(reason==='google_token')hook=async(entry,next)=>entry.url.origin==='https://oauth2.googleapis.com'?Response.json({access_token:tag,scope:'openid email'}):next();
   if(reason==='google_account'){account={email:tag+'@example.invalid',email_verified:true};cleanup=async()=>{account={email:'jacmusicestudios@gmail.com',email_verified:true};};}
   if(reason==='folder_access'){files.get(m.MEDIA_ROOT_ID).capabilities.canAddChildren=false;cleanup=async()=>{files.get(m.MEDIA_ROOT_ID).capabilities.canAddChildren=true;};}
   if(reason==='connection_storage'){sql.exec("CREATE TRIGGER media_fixture_deny_storage BEFORE UPDATE ON jac_media_connection BEGIN SELECT RAISE(ABORT,'"+tag+"'); END");cleanup=async()=>sql.exec('DROP TRIGGER media_fixture_deny_storage');}
   const result=await m.finishMediaOauth(callback),url=new URL(result.url);
   assert.equal(url.searchParams.get('drive'),'error');assert.equal(url.searchParams.get('reason'),reason);assert.deepEqual([...url.searchParams.keys()].sort(),['drive','reason']);assert.ok(!JSON.stringify(result).includes(tag));
   assert.deepEqual(logs.at(-1),['Media Drive authorization failed',{reason}]);assert.deepEqual(Object.keys(logs.at(-1)[1]),['reason']);
   await cleanup();beforeQuery=undefined;hook=undefined;
  }
  assert.equal(logs.length,expected.length);assert.ok(!JSON.stringify(logs).includes(tag));
 }finally{console.error=oldLog;beforeQuery=undefined;hook=undefined;sql.prepare('UPDATE payroll_users SET active=1 WHERE id=?').run(ownerID);sql.exec('DROP TRIGGER IF EXISTS media_fixture_deny_storage');}
});
