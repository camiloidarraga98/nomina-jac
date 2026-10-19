import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';

const base='https://shared-worker.example.invalid',actor='22222222-2222-4222-8222-222222222222',session=Buffer.alloc(32,2).toString('base64url');
const folder='r2_11111111-1111-4111-8111-111111111111',child='r2_33333333-3333-4333-8333-333333333333',photo='r2_44444444-4444-4444-8444-444444444444',outside='r2_55555555-5555-4555-8555-555555555555';
const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
 import * as shares from './app/api/media/shares/route';import * as shared from './app/api/media/shared/route';
 import {encryptMail} from './lib/payroll-mail-core';import {mailKey} from './lib/payroll-mail';import {database} from './db/raw';
 export default {async fetch(req:Request){globalThis.__shareHeaders=new Headers(req.headers);globalThis.__shareHeaders.set('host','shared-worker.example.invalid');const path=new URL(req.url).pathname;
 if(path==='/fixture-init'){await database().prepare("INSERT INTO jac_media_r2_connection(id,credentials,enabled,version,updated_at) VALUES('jac',?,1,1,'fixture')").bind(await encryptMail({accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64)},mailKey())).run();return new Response('fixture only');}
 if(path==='/api/media/shares')return req.method==='GET'?shares.GET(req):shares.POST(req);return shared.GET(req);}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*'],plugins:[{name:'share-request-headers',setup(b){b.onResolve({filter:/^next\/headers$/},()=>({path:'headers',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const headers=async()=>globalThis.__shareHeaders;',loader:'js'}));}}]});

test('Workerd initializes only the authorized additive store and serves a revocable subtree without a session',async()=>{
 let db,calls=0,revokeDuringRead=false;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-shared-folder'},bindings:{PAYROLL_AUTH_KEY:'fixture-independent-shared-folder-auth-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')},outboundService:async request=>{
  const url=new URL(request.url);assert.equal(url.origin,'https://'+'1'.repeat(32)+'.r2.cloudflarestorage.com');assert.equal(url.pathname,'/jac-fotografia/originals/'+photo.slice(3));assert.equal(request.method,'GET');assert.equal(request.headers.has('cookie'),false);assert.match(request.headers.get('authorization'),/^AWS4-HMAC-SHA256/);calls++;
  if(revokeDuringRead)await db.prepare("UPDATE jac_media_folder_shares SET revoked_at='fixture-revoked'").run();
  const bytes=new Uint8Array([255,216,255,192,0,11,8,0,16,0,16,1,1,17,0,255,217]);
  return new Response(bytes,{headers:{'content-type':'image/jpeg','content-length':String(bytes.length)}});
 }});
 try{
  db=await mf.getD1Database('DB');
  for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')&&!n.startsWith('0027')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
  await db.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,owner,permissions,media_only,created_at,updated_at) VALUES (?,?,?,?,?,0,?,1,?,?)').bind(actor,'share-fixture','photo@example.invalid','Fotógrafo ficticio','fixture','[]','fixture','fixture').run();
  await db.prepare("INSERT INTO payroll_sessions(id,user_id,user_version,expires_at,persistent) VALUES (?,?,1,'',1)").bind(createHash('sha256').update(session).digest('hex'),actor).run();
  await mf.dispatchFetch(base+'/fixture-init');
  for(const [id,parent,mime] of [[folder,'jac_r2_root','application/vnd.google-apps.folder'],[child,folder,'application/vnd.google-apps.folder'],[photo,child,'image/jpeg'],[outside,'jac_r2_root','image/jpeg']])await db.prepare("INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,thumbnail_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,17,?,'',?,'fixture','fixture','fixture')").bind(id,parent,id,mime,'originals/'+id.slice(3),actor).run();
  const call=(path,body,authenticated=false)=>mf.dispatchFetch(base+path,{method:body?'POST':'GET',headers:{origin:base,...(authenticated?{cookie:'__Host-jac_session='+session}:{}),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
  const table=()=>db.prepare("SELECT name FROM sqlite_master WHERE name='jac_media_folder_shares'").first();
  const input={action:'create',id:crypto.randomUUID(),folderId:folder,days:7};
  assert.equal((await call('/api/media/shares',input)).status,401);assert.equal(await table(),null);
  assert.equal((await call('/api/media/shared?token='+'a'.repeat(43))).status,410);assert.equal(await table(),null);
  const created=await call('/api/media/shares',input,true);assert.equal(created.status,200,await created.clone().text());assert.ok(await table());
  const {link}=await created.json(),token=link.url.split('/').at(-1),prefix='/api/media/shared?token='+token;
  const feed=await call(prefix),value=await feed.json();assert.equal(feed.status,200);assert.deepEqual(value.breadcrumbs.map(x=>x.id),[folder]);assert.equal(value.root,undefined);assert.equal(value.canUpload,undefined);
  assert.equal((await call(prefix+'&folder='+child)).status,200);assert.equal((await call(prefix+'&id='+outside)).status,410);assert.equal(calls,0);
  const file=await call(prefix+'&id='+photo);assert.equal(file.status,200);assert.equal((await file.arrayBuffer()).byteLength,17);assert.match(file.headers.get('cache-control'),/no-store/);assert.equal(calls,1);
  revokeDuringRead=true;assert.equal((await call(prefix+'&id='+photo)).status,403);assert.equal((await call(prefix)).status,410);
  // The checked SQL file remains safe for the normal migration runner later.
  for(const statement of (await readFile('drizzle/0027_media_folder_shares.sql','utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
  assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM jac_media_folder_shares').first()).n,1);
 }finally{await mf.dispose();}
});
