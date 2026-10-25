import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';

test('Workerd/D1 recovers a durable future-folder event atomically and sends once with private session and folder guards',async()=>{
 const compiled=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {env} from 'cloudflare:workers';
  import {publishMediaFolderNotifications,dispatchMediaFolderPush,processMediaFolderNotifications} from './lib/media-folder-notifications';
  import {registerDevice} from './lib/notifications';
  import {encryptMail} from './lib/payroll-mail-core';
  import {makeSession,authenticatedSession} from './lib/payroll-auth-store';
  export default {async fetch(req:Request){const b=await req.json();try{
   if(b.action==='setup'){
    const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
    const bytes=new Uint8Array(await crypto.subtle.exportKey('pkcs8',pair.privateKey));
    const privateKey='-----BEGIN PRIVATE KEY-----\\n'+btoa(String.fromCharCode(...bytes))+'\\n-----END PRIVATE KEY-----';
    const cipher=await encryptMail({apns:{teamId:'WORKERTEST',keyId:'FIXTUREKEY',privateKey}},env.PAYROLL_MAIL_KEY);
    await env.DB.prepare("INSERT INTO jac_notice_settings(id,credentials) VALUES('jac',?)").bind(cipher).run();
    const token=await makeSession(b.user,true),actor=await authenticatedSession(token);
    await registerDevice(actor,{id:b.device,platform:'ios',token:'ab'.repeat(32),environment:'production'},token,async()=>true);
   }else if(b.action==='publish')await publishMediaFolderNotifications();
   else if(b.action==='dispatch')await dispatchMediaFolderPush();
   else await processMediaFolderNotifications();
   return Response.json({ok:true});
  }catch(error){return Response.json({error:error.message},{status:500});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 const calls=[];
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:compiled.outputFiles[0].text,d1Databases:{DB:'media-folder-push-fixture'},bindings:{PAYROLL_MAIL_KEY:Buffer.alloc(32,61).toString('base64url')},outboundService:async request=>{assert.equal(new URL(request.url).hostname,'api.push.apple.com','All external services are intercepted');calls.push(await request.json());return new Response(null,{status:200});}});
 try{
  const db=await mf.getD1Database('DB'),migrations=(await readdir('drizzle')).filter(name=>name.endsWith('.sql')).sort();
  const apply=async name=>{for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(text=>text.trim()).filter(Boolean))await db.prepare(statement).run();};
  for(const name of migrations.filter(name=>!name.startsWith('0036_')))await apply(name);
  const stamp=new Date(Date.now()-180_000).toISOString(),future=new Date(Date.now()+86_400_000).toISOString(),folder='r2_'+crypto.randomUUID(),old='r2_'+crypto.randomUUID(),user=crypto.randomUUID(),device=crypto.randomUUID(),file=crypto.randomUUID();
  await db.prepare("INSERT INTO jac_media_r2_connection(id,enabled,version,updated_at) VALUES('jac',1,1,?)").bind(stamp).run();
  const insertFolder=id=>db.prepare("INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,actor_id,payload_hash,created_at,modified_at) VALUES(?,'jac_r2_root','Carpeta ficticia','application/vnd.google-apps.folder','fixture','fixture',?,?)").bind(id,stamp,stamp).run();
  await insertFolder(old);await apply('0036_media_folder_notifications.sql');assert.equal((await db.prepare('SELECT count(*) n FROM jac_media_folder_notifications').first()).n,0);
  await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,created_at,updated_at) VALUES(?,?,?,'Fixture','fixture','[]',1,?,?)").bind(user,user,user+'@example.invalid',stamp,stamp).run();
  const run=body=>mf.dispatchFetch('https://media-push.example.invalid/',{method:'POST',body:JSON.stringify(body)});
  assert.equal((await run({action:'setup',user,device})).status,200);await insertFolder(folder);
  assert.equal((await run({action:'process'})).status,200);assert.equal(calls.length,0,'Empty folders never publish');
  await db.prepare("INSERT INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,drive_id,name,mime_type,size,offset,status,connection_version,created_at,expires_at) VALUES(?,'fixture',?,'fixture','r2-upload',?,'Fixture.jpg','image/jpeg',100,100,'ready',1,?,?)").bind(file,folder,'r2_'+file,stamp,future).run();
  await db.prepare("INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,'Fixture.jpg','image/jpeg',100,?,'fixture','fixture',?,?)").bind('r2_'+file,folder,'originals/'+file,stamp,stamp).run();
  await db.prepare("CREATE TRIGGER fixture_media_push_rollback BEFORE INSERT ON jac_media_folder_push_deliveries BEGIN SELECT RAISE(ABORT,'fixture rollback'); END").run();
  assert.equal((await run({action:'publish'})).status,500);assert.equal((await db.prepare('SELECT status FROM jac_media_folder_notifications WHERE folder_id=?').bind(folder).first()).status,'waiting');assert.equal((await db.prepare('SELECT count(*) n FROM jac_media_folder_push_deliveries').first()).n,0);
  await db.prepare('DROP TRIGGER fixture_media_push_rollback').run();
  const publications=await Promise.all([run({action:'publish'}),run({action:'publish'})]);for(const response of publications)assert.equal(response.status,200);
  assert.equal((await db.prepare('SELECT count(*) n FROM jac_media_folder_push_deliveries').first()).n,1);assert.equal((await run({action:'dispatch'})).status,200);assert.equal((await run({action:'process'})).status,200);assert.equal(calls.length,1);assert.equal(calls[0].kind,'media_folder');assert.equal(calls[0].folderId,folder);assert.deepEqual(calls[0].aps.alert,{title:'¡Nuevas fotos disponibles!',body:'Ya está disponible la carpeta «Carpeta ficticia».'});assert.equal((await db.prepare('SELECT count(*) n FROM jac_notices').first()).n,0);
 }finally{await mf.dispose();}
});
