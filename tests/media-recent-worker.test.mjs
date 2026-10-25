import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';

test('Workerd/D1 recent photos enforce ready uploads, ancestry, global order and the active private session without provider reads',async()=>{
 const user='11111111-1111-4111-8111-111111111111',session='a'.repeat(64),secret={accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64)};
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {env} from 'cloudflare:workers';
  import {r2RecentPhotos} from './lib/media-r2-gallery';
  import {mediaStoredGuard} from './lib/media-drive';
  import {encryptMail} from './lib/payroll-mail-core';
  export default {async fetch(req:Request){const b=await req.json();try{
   if(b.action==='setup'){
    const credentials=await encryptMail(b.secret,env.PAYROLL_MAIL_KEY);
    await env.DB.prepare("INSERT INTO jac_media_r2_connection(id,credentials,enabled,version,updated_at) VALUES('jac',?,1,3,'fixture')").bind(credentials).run();
   }
   return Response.json(await r2RecentPhotos(mediaStoredGuard('${session}','${user}')));
  }catch(error){return Response.json({error:error.message},{status:error.status||503});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 let outbound=0;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'recent-photos-fixture'},bindings:{PAYROLL_MAIL_KEY:Buffer.alloc(32,42).toString('base64url')},outboundService:async()=>{outbound++;throw Error('All provider requests, originals and thumbnails are blocked.');}});
 try{
  const db=await mf.getD1Database('DB');
  for(const name of(await readdir('drizzle')).filter(name=>name.endsWith('.sql')).sort())for(const statement of(await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(value=>value.trim()).filter(Boolean))await db.prepare(statement).run();
  await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,section_access,created_at,updated_at) VALUES (?,'fixture','photo@example.invalid','Fixture','fixture','[]','[\"media\"]','fixture','fixture')").bind(user).run();
  await db.prepare("INSERT INTO payroll_sessions(id,user_id,user_version,expires_at) VALUES (?,?,1,'2090-01-01T00:00:00.000Z')").bind(session,user).run();
  const run=body=>mf.dispatchFetch('https://recent.example.invalid/',{method:'POST',body:JSON.stringify(body)});
  const empty=await run({action:'setup',secret});assert.equal(empty.status,200);assert.deepEqual((await empty.json()).items,[]);
  const folders=['r2_'+crypto.randomUUID(),'r2_'+crypto.randomUUID()],expected=[];
  for(const folder of folders)await db.prepare("INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,actor_id,payload_hash,created_at,modified_at) VALUES (?,'jac_r2_root','Carpeta ficticia','application/vnd.google-apps.folder',?,'fixture','fixture','fixture')").bind(folder,user).run();
  for(let i=0;i<12;i++){
   const request=crypto.randomUUID(),id='r2_'+request,parent=folders[i%2],stamp='2026-10-25T00:00:'+String(i).padStart(2,'0')+'.000Z',mime=i===11?'video/mp4':'image/jpeg',status=i===10?'pending':'ready';
   await db.prepare("INSERT INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,drive_id,name,mime_type,size,offset,status,connection_version,created_at,expires_at) VALUES (?,?,?,'fixture','r2-upload',?,'Ficticio.jpg',?,100,100,?,3,?,'2090-01-01T00:00:00.000Z')").bind(request,user,parent,id,mime,status,stamp).run();
   await db.prepare("INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,thumbnail_key,actor_id,payload_hash,created_at,modified_at) VALUES (?,?,'Ficticio.jpg',?,100,?,? ,?,'fixture',?,?)").bind(id,parent,mime,'originals/'+request,'thumbnails/'+request+'.jpg',user,stamp,stamp).run();
   if(mime==='image/jpeg'&&status==='ready')expected.unshift({id,parentId:parent});
  }
  const recent=await run({});assert.equal(recent.status,200);const data=await recent.json();assert.equal(data.items.length,8);assert.equal(data.collectionID,'jac-r2-new-20261016');assert.deepEqual(data.items.map(({id,parentId})=>({id,parentId})),expected.slice(0,8));
  assert.equal(JSON.stringify(data).includes('originals/'),false);assert.equal(JSON.stringify(data).includes(secret.secretAccessKey),false);
  await db.prepare("INSERT INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,name,mime_type,status,connection_version,created_at,expires_at) VALUES (?,?,?,'fixture','r2-delete-folder','Ficticio','','pending',3,'fixture','fixture')").bind('r2-delete:'+folders[1],user,folders[1]).run();
  const hidden=await(await run({})).json();assert.ok(hidden.items.every(item=>item.parentId===folders[0]));assert.equal(hidden.items.length,5);
  await db.prepare("UPDATE payroll_users SET section_access='[\"calendar\"]' WHERE id=?").bind(user).run();assert.equal((await run({})).status,403);
  await db.prepare("UPDATE payroll_users SET section_access='[\"media\"]' WHERE id=?").bind(user).run();await db.prepare("UPDATE jac_media_r2_connection SET enabled=0 WHERE id='jac'").run();assert.equal((await run({})).status,409);
  assert.equal(outbound,0);
 }finally{await mf.dispose();}
});
