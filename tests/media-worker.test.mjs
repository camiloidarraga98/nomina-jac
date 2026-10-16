import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {readFile,readdir} from 'node:fs/promises';

// Workerd executes the real media API and D1 guards. All Google traffic terminates
// in outboundService; no credentials, photos, videos or accounts are real.
const root='1yH4pNYQxArfynzho-IPBtx5w4AWbQ-C5',folderID='fixture_worker_folder',fileID='fixture_worker_file',folderMime='application/vnd.google-apps.folder',chunkSize=1024*1024;
const scope='https://www.googleapis.com/auth/drive',base='https://media-worker.example.invalid';
const ownerID='11111111-1111-4111-8111-111111111111',photoID='22222222-2222-4222-8222-222222222222',readerID='33333333-3333-4333-8333-333333333333';
const tokens={owner:Buffer.alloc(32,1).toString('base64url'),photo:Buffer.alloc(32,2).toString('base64url'),reader:Buffer.alloc(32,3).toString('base64url')};
const tokenHash=s=>createHash('sha256').update(s).digest('hex');
const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
 import * as media from './app/api/media/route';
 import * as upload from './app/api/media/upload/route';
 import * as file from './app/api/media/file/route';
 import {ensureMediaConfig,mediaStoredGuard,storeMediaConnection} from './lib/media-drive';
 export default {async fetch(req:Request){
  globalThis.__mfMediaHeaders=new Headers(req.headers);globalThis.__mfMediaHeaders.set("host","media-worker.example.invalid");
  const path=new URL(req.url).pathname;
  if(path==='/init'){const config=await ensureMediaConfig();await storeMediaConnection({clientId:'fixture.apps.googleusercontent.com',clientSecret:'fixture-secret',refreshToken:'fixture-refresh',scopes:['${scope}']},config.version,mediaStoredGuard('${tokenHash(tokens.owner)}','${ownerID}','connect'));return Response.json({ok:true});}
  if(path==='/api/media/upload')return req.method==='PUT'?upload.PUT(req):upload.POST(req);
  if(path==='/api/media/file')return file.GET(req);
  return req.method==='GET'?media.GET(req):media.POST(req);
 }};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*'],plugins:[{name:'mock-request-headers',setup(b){b.onResolve({filter:/^next\/headers$/},()=>({path:'headers',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const headers=async()=>globalThis.__mfMediaHeaders;',loader:'js'}));}}]});
async function fixture(){
 const state={offset:0,size:chunkSize+13,metadata:null,calls:[],redirect:false,revoke:null};
 const metadata=id=>id===root?{id,name:'Raíz ficticia',mimeType:folderMime,parents:[],capabilities:{canAddChildren:true}}:id===folderID?{id,name:'2026-10-16 · Show ficticio',mimeType:folderMime,parents:[root],capabilities:{canAddChildren:true}}:id===fileID&&state.offset===state.size?{...state.metadata,size:String(state.size),capabilities:{canDownload:true}}:null;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-media-worker'},bindings:{PAYROLL_AUTH_KEY:'fixture-workerd-independent-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')},outboundService:async req=>{
  const url=new URL(req.url);assert.ok(['https://oauth2.googleapis.com','https://www.googleapis.com'].includes(url.origin),'The worker must never reach an external destination or redirect');
  const entry={url:req.url,method:req.method,authorization:req.headers.get('authorization'),range:req.headers.get('content-range'),bytes:new Uint8Array(await req.arrayBuffer())};state.calls.push(entry);
  if(url.origin==='https://oauth2.googleapis.com'){assert.equal(req.method,'POST');return Response.json({access_token:'fixture-worker-access'});}
  assert.equal(req.headers.get('authorization'),'Bearer fixture-worker-access');
  if(url.pathname==='/drive/v3/files/generateIds')return Response.json({ids:[fileID]});
  if(url.pathname==='/upload/drive/v3/files'&&req.method==='POST'){state.metadata=JSON.parse(new TextDecoder().decode(entry.bytes));state.size=Number(req.headers.get('x-upload-content-length'));return new Response(null,{headers:{Location:'https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture-worker-session'}});}
  if(url.pathname==='/upload/drive/v3/files'&&req.method==='PUT'){
   if(entry.range.startsWith('bytes */'))return state.offset===state.size?Response.json(metadata(fileID)):new Response(null,{status:308,headers:state.offset?{Range:'bytes=0-'+(state.offset-1)}:{}});
   const match=entry.range.match(/^bytes (\d+)-(\d+)\/(\d+)$/);assert.ok(match);const start=Number(match[1]),end=Number(match[2]);assert.equal(start,state.offset);assert.equal(Number(match[3]),state.size);assert.equal(entry.bytes.length,end-start+1);state.offset=end+1;if(state.revoke)await state.revoke();
   return state.offset===state.size?Response.json(metadata(fileID),{status:201}):new Response(null,{status:308,headers:{Range:'bytes=0-'+(state.offset-1)}});
  }
  const id=url.pathname.split('/').at(-1),value=metadata(id);if(!value)return new Response(null,{status:404});
  if(url.searchParams.get('alt')==='media'){
   if(state.redirect)return new Response(null,{status:307,headers:{Location:'https://untrusted.example.invalid/collect'}});
   const range=req.headers.get('range');assert.equal(range,'bytes=2-5');return new Response(new Uint8Array([1,2,3,4]),{status:206,headers:{'content-type':'image/png','content-range':'bytes 2-5/'+state.size,'content-length':'4'}});
  }
  return Response.json(value);
 }});
 const db=await mf.getD1Database('DB');for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
 for(const [role,id] of [['owner',ownerID],['photo',photoID],['reader',readerID]]){
  await db.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,owner,permissions,media_only,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)').bind(id,role+'-fixture',role==='owner'?'camilo@mac2you.co':role+'@example.invalid',role+' ficticio','fixture',Number(role==='owner'),'[]',Number(role==='photo'),'fixture','fixture').run();
  await db.prepare('INSERT INTO payroll_sessions(id,user_id,user_version,expires_at,persistent) VALUES (?,?,1,?,1)').bind(tokenHash(tokens[role]),id,'').run();
 }
 const call=(path,{role='photo',method='GET',body,headers={}}={})=>mf.dispatchFetch(base+path,{method,headers:{origin:base,cookie:'__Host-jac_session='+tokens[role],...headers},...(body!==undefined?{body}: {})});
 assert.equal((await call('/init',{role:'owner',method:'POST'})).status,200);
 return {mf,db,state,call};
}
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
test('Workerd blocks readers, administrator uploads, wrong origin, redirects and revoked photo sessions',async()=>{
 const {mf,db,state,call}=await fixture();try{
  const record={action:'start',id:crypto.randomUUID(),parentId:folderID,filename:'foto-ficticia.png',mimeType:'image/png',size:13},before=state.calls.length;
  assert.equal((await call('/api/media',{role:'reader'})).status,403);assert.equal((await call('/api/media/upload',{role:'owner',method:'POST',body:JSON.stringify(record)})).status,403);assert.equal((await call('/api/media/upload',{method:'POST',headers:{origin:'https://untrusted.example.invalid'},body:JSON.stringify(record)})).status,403);assert.equal(state.calls.length,before);
  assert.equal((await call('/api/media/upload',{method:'POST',body:JSON.stringify(record)})).status,200);const bytes=new Uint8Array(13);bytes.set([137,80,78,71,13,10,26,10]);state.revoke=async()=>{await db.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').bind(photoID).run();};
  const revoked=await call('/api/media/upload?id='+record.id+'&offset=0',{method:'PUT',body:bytes});assert.equal(revoked.status,403);assert.equal((await db.prepare('SELECT status FROM jac_media_operations WHERE id=?').bind(record.id).first()).status,'pending');
  state.redirect=true;const count=state.calls.length,response=await call('/api/media/file?id='+fileID,{role:'owner',headers:{range:'bytes=2-5'}});assert.equal(response.status,502);assert.ok(state.calls.slice(count).every(c=>!c.url.includes('untrusted')));
 }finally{await mf.dispose();}
});
