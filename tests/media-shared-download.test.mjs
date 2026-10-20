import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {unzipSync} from 'fflate';
import {crc32} from 'node:zlib';

const actor='22222222-2222-4222-8222-222222222222',session=Buffer.alloc(32,2).toString('base64url'),base='https://download.example.invalid';
const folder='r2_11111111-1111-4111-8111-111111111111',child='r2_33333333-3333-4333-8333-333333333333',outside='r2_55555555-5555-4555-8555-555555555555';
const buildResult=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
 import * as management from './app/api/media/shares/route';import * as download from './app/api/media/shared/download/route';
 import {encryptMail} from './lib/payroll-mail-core';import {mailKey} from './lib/payroll-mail';import {database} from './db/raw';
 export default {async fetch(req:Request){globalThis.__downloadHeaders=new Headers(req.headers);globalThis.__downloadHeaders.set('host','download.example.invalid');const path=new URL(req.url).pathname;
 if(path==='/fixture-init'){await database().prepare("INSERT INTO jac_media_r2_connection(id,credentials,enabled,version,updated_at) VALUES('jac',?,1,1,'fixture')").bind(await encryptMail({accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64)},mailKey())).run();return new Response('fixture');}
 return path==='/api/media/shares'?management.POST(req):download.POST(req);}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*'],plugins:[{name:'download-headers',setup(b){b.onResolve({filter:/^next\/headers$/},()=>({path:'headers',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const headers=async()=>globalThis.__downloadHeaders;',loader:'js'}));}}]});

test('public ZIP downloads traverse pages/subfolders, filter photos, preserve originals and reject stale/outside selections and revoked links',async()=>{
 const objects=new Map(),calls=[];let db,revokeDuringRead=false;
 const mf=new Miniflare({modules:true,script:buildResult.outputFiles[0].text,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],d1Databases:{DB:'fixture-shared-download'},bindings:{PAYROLL_AUTH_KEY:'fixture-independent-shared-download-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')},outboundService:async request=>{
  const url=new URL(request.url);assert.equal(url.origin,'https://'+'1'.repeat(32)+'.r2.cloudflarestorage.com');assert.equal(request.method,'GET');assert.equal(request.headers.has('cookie'),false);assert.match(request.headers.get('authorization'),/^AWS4-HMAC-SHA256/);
  const key=url.pathname.slice('/jac-fotografia/'.length);assert.ok(objects.has(key));calls.push(key);
  if(revokeDuringRead)await db.prepare("UPDATE jac_media_folder_shares SET revoked_at='fixture-revoked'").run();
  const object=objects.get(key);return new Response(object,{headers:{'Content-Length':String(object.length)}});
 }});
 try{
  db=await mf.getD1Database('DB');for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
  await db.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,owner,permissions,media_only,created_at,updated_at) VALUES (?,?,?,?,?,0,?,1,?,?)').bind(actor,'download-fixture','photo@example.invalid','Fotógrafo ficticio','fixture','[]','fixture','fixture').run();
  await db.prepare("INSERT INTO payroll_sessions(id,user_id,user_version,expires_at,persistent) VALUES (?,?,1,'',1)").bind(createHash('sha256').update(session).digest('hex'),actor).run();await mf.dispatchFetch(base+'/fixture-init');
  const insert=async(id,parent,name,mime,content)=>{const data=new TextEncoder().encode(content||'');const key='originals/'+id.slice(3);if(content)objects.set(key,data);await db.prepare("INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,thumbnail_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,?,?,'',?,'fixture','fixture','revision-1')").bind(id,parent,name,mime,data.length,key,actor).run();};
  await insert(folder,'jac_r2_root','Fiesta','application/vnd.google-apps.folder');await insert(child,folder,'Subcarpeta','application/vnd.google-apps.folder');
  const image='r2_44444444-4444-4444-8444-444444444444',video='r2_66666666-6666-4666-8666-666666666666';
  await insert(image,folder,'Foto.jpg','image/jpeg','original-photo');await insert(video,child,'Video.mp4','video/mp4','original-video');await insert(outside,'jac_r2_root','Privado.jpg','image/jpeg','outside-must-never-leak');
  // More than one feed page, plus colliding legacy names and path characters.
  for(let n=0;n<101;n++)await insert('r2_'+String(n).padStart(8,'0')+'-aaaa-4aaa-8aaa-aaaaaaaaaaaa',child,n<2?'Repetida.jpg':n===2?'../../Ruta.jpg':'Foto-'+n+'.jpg','image/jpeg','bytes-'+n);
  const management=await mf.dispatchFetch(base+'/api/media/shares',{method:'POST',headers:{origin:base,cookie:'__Host-jac_session='+session,'Content-Type':'application/json'},body:JSON.stringify({action:'create',id:crypto.randomUUID(),folderId:folder,days:7})});assert.equal(management.status,200,await management.clone().text());const token=(await management.json()).link.url.split('/').at(-1);
  const download=(mode,selection=[],extra={})=>mf.dispatchFetch(base+'/api/media/shared/download',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token,folder,mode,selection:JSON.stringify(selection),...extra}).toString()});
  const photos=await download('photos');assert.equal(photos.status,200);assert.match(photos.headers.get('content-disposition'),/^attachment/);assert.match(photos.headers.get('cache-control'),/no-store/);assert.equal(photos.headers.get('referrer-policy'),'no-referrer');
  const photoBytes=new Uint8Array(await photos.arrayBuffer()),photoArchive=unzipSync(photoBytes);assert.equal(Object.keys(photoArchive).length,102);assert.equal(new TextDecoder().decode(photoArchive['Foto.jpg']),'original-photo');assert.equal(photoArchive['Subcarpeta/Video.mp4'],undefined);assert.ok(photoArchive['Subcarpeta/Repetida.jpg']);assert.ok(photoArchive['Subcarpeta/Repetida (2).jpg']);assert.ok(Object.keys(photoArchive).every(name=>!name.split('/').includes('..')&&!name.includes('Privado')));
  assert.equal(Number(photos.headers.get('content-length')),photoBytes.length);
  const zipView=new DataView(photoBytes.buffer),zip64End=photoBytes.length-98;assert.equal(zipView.getUint32(zip64End,true),0x06064b50);assert.equal(Number(zipView.getBigUint64(zip64End+24,true)),102);
  let central=Number(zipView.getBigUint64(zip64End+48,true));for(let n=0;n<102;n++){
   assert.equal(zipView.getUint32(central,true),0x02014b50);const length=zipView.getUint16(central+28,true),name=new TextDecoder().decode(photoBytes.slice(central+46,central+46+length)),extra=central+46+length;
   assert.equal(zipView.getUint32(central+16,true),crc32(photoArchive[name]));assert.equal(zipView.getUint16(extra,true),1);assert.equal(Number(zipView.getBigUint64(extra+4,true)),photoArchive[name].length);assert.equal(zipView.getUint32(Number(zipView.getBigUint64(extra+20,true)),true),0x04034b50);central+=74+length;
  }assert.equal(central,zip64End);
  const all=unzipSync(new Uint8Array(await (await download('all')).arrayBuffer()));assert.equal(Object.keys(all).length,103);assert.equal(new TextDecoder().decode(all['Subcarpeta/Video.mp4']),'original-video');
  const selected=unzipSync(new Uint8Array(await (await download('selected',[{id:image,revision:'revision-1'}])).arrayBuffer()));assert.deepEqual(Object.keys(selected),['Foto.jpg']);assert.deepEqual(selected['Foto.jpg'],photoArchive['Foto.jpg']);
  const before=calls.length;assert.equal((await download('selected',[{id:outside,revision:'revision-1'}])).status,409);assert.equal((await download('selected',[{id:image,revision:'old'}])).status,409);assert.equal((await download('selected',[{id:image,revision:'revision-1'},{id:image,revision:'revision-1'}])).status,400);assert.equal((await download('all',[],{folder:outside})).status,410);assert.equal(calls.length,before);
  const response=await download('all'),reader=response.body.getReader();await reader.read();await reader.cancel();const cancelledAt=calls.length;await new Promise(resolve=>setTimeout(resolve,50));const settled=calls.length;assert(settled<=cancelledAt+1,'Only the already buffered bridge read may finish during cancellation');await new Promise(resolve=>setTimeout(resolve,50));assert.equal(calls.length,settled,'Cancellation must stop subsequent originals after the Workerd bridge settles');
  revokeDuringRead=true;const revoked=await download('selected',[{id:image,revision:'revision-1'}]);
  // The local Workerd bridge may terminate an errored stream without forwarding
  // its exception to arrayBuffer(). It must never return an original or ZIP.
  const lateBytes=await revoked.arrayBuffer().then(value=>new Uint8Array(value),()=>null);if(lateBytes){assert.equal(lateBytes.length,0);assert.throws(()=>unzipSync(lateBytes));}assert.equal((await download('all')).status,410);
  assert.ok(!calls.some(key=>key.endsWith(outside.slice(3))));
 }finally{await mf.dispose();}
});
