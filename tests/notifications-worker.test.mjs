import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {createECDH,createHmac,generateKeyPairSync,createPublicKey,verify,hkdfSync,createDecipheriv} from 'node:crypto';

test('Workerd cifra Web Push interoperable y firma APNs/Slack sin seguir redirecciones',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {webPushRequest,applePushRequest,createWebKeys,verifySlack} from './lib/notifications-core';
  export default {async fetch(req:Request){const b=await req.json();
   if(b.kind==='slack')return Response.json({valid:await verifySlack(b.raw,b.timestamp,b.signature,b.secret)});
   const keys=b.kind==='web'?await createWebKeys():undefined;
   const out=b.kind==='web'?await webPushRequest(b.subscription,keys!,b.payload):await applePushRequest(b.token,b.environment,b.credentials,b.id,b.content);
   const response=await fetch(out.url,out.options);return Response.json({status:response.status,publicKey:keys?.publicKey??''});
  }};
 `},bundle:true,platform:'browser',format:'esm',write:false});
 let calls=[],redirect=false;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',script:output.outputFiles[0].text,outboundService:async request=>{
  assert.ok(['https://fcm.googleapis.com/fcm/send/fixture','https://api.sandbox.push.apple.com/3/device/'+('ab'.repeat(32))].includes(request.url),'Ninguna petición puede salir al proveedor real ni a una redirección.');
  calls.push({url:request.url,headers:request.headers,body:Buffer.from(await request.arrayBuffer())});
  return new Response(null,{status:redirect?307:200,headers:redirect?{location:'https://untrusted.example.invalid/collect'}:{}});
 }});
 const run=async b=>{const response=await mf.dispatchFetch('https://local.example.invalid/push',{method:'POST',body:JSON.stringify(b)});assert.equal(response.status,200);return response.json();};
 try {
  const receiver=createECDH('prime256v1');receiver.generateKeys();const auth=Buffer.alloc(16,3),payload=JSON.stringify({id:'fixture-notice'});
  const input={kind:'web',subscription:{endpoint:'https://fcm.googleapis.com/fcm/send/fixture',keys:{p256dh:receiver.getPublicKey().toString('base64url'),auth:auth.toString('base64url')}},payload};
  const result=await run(input);assert.equal(result.status,200);const push=calls.at(-1),bytes=push.body,salt=bytes.subarray(0,16),sender=bytes.subarray(21,21+bytes[20]),cipher=bytes.subarray(21+bytes[20]);
  const ikm=Buffer.from(hkdfSync('sha256',receiver.computeSecret(sender),auth,Buffer.concat([Buffer.from('WebPush: info\0'),receiver.getPublicKey(),sender]),32));
  const decipher=createDecipheriv('aes-128-gcm',Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: aes128gcm\0'),16)),Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: nonce\0'),12)));
  decipher.setAuthTag(cipher.subarray(-16));const clear=Buffer.concat([decipher.update(cipher.subarray(0,-16)),decipher.final()]);assert.equal(clear.subarray(0,-1).toString(),payload);assert.equal(clear.at(-1),2);
  const vapid=push.headers.get('authorization').match(/t=([^,]+)/)[1].split('.'),raw=Buffer.from(result.publicKey,'base64url');
  assert.ok(verify('sha256',Buffer.from(vapid.slice(0,2).join('.')),{key:createPublicKey({key:{kty:'EC',crv:'P-256',x:raw.subarray(1,33).toString('base64url'),y:raw.subarray(33).toString('base64url')},format:'jwk'}),dsaEncoding:'ieee-p1363'},Buffer.from(vapid[2],'base64url')));
  const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),apple={kind:'apple',token:'ab'.repeat(32),environment:'sandbox',id:'33333333-3333-4333-8333-333333333333',content:{title:'Aviso de prueba',body:'Descripción completa con tildes 🎵'},credentials:{teamId:'TESTTEAM01',keyId:'TESTKEY001',privateKey:pair.privateKey.export({type:'pkcs8',format:'pem'})}};
  assert.equal((await run(apple)).status,200);const apns=calls.at(-1),jwt=apns.headers.get('authorization').slice(7).split('.');assert.ok(verify('sha256',Buffer.from(jwt.slice(0,2).join('.')),{key:pair.publicKey,dsaEncoding:'ieee-p1363'},Buffer.from(jwt[2],'base64url')));assert.equal(apns.headers.get('apns-topic'),'co.jacmusic.nomina');assert.equal(JSON.parse(apns.body).noticeId,apple.id);assert.deepEqual(JSON.parse(apns.body).aps.alert,apple.content);
  await run({...apple,id:'55555555-5555-4555-8555-555555555555'});assert.equal(calls.at(-1).headers.get('authorization'),apns.headers.get('authorization'),'APNs reutiliza el token; no genera actualizaciones excesivas por cada destinatario.');
  const rotated=generateKeyPairSync('ec',{namedCurve:'prime256v1'});await run({...apple,credentials:{...apple.credentials,privateKey:rotated.privateKey.export({type:'pkcs8',format:'pem'})}});assert.notEqual(calls.at(-1).headers.get('authorization'),apns.headers.get('authorization'),'Rotar la clave invalida el token en memoria.');
  redirect=true;for(const b of [input,apple]){const before=calls.length;assert.equal((await run(b)).status,307);assert.equal(calls.length,before+1);}
  const rawSlack='{"type":"url_verification"}',timestamp=String(Math.floor(Date.now()/1000)),secret='b'.repeat(32),signature='v0='+createHmac('sha256',secret).update('v0:'+timestamp+':'+rawSlack).digest('hex');
  assert.equal((await run({kind:'slack',raw:rawSlack,timestamp,signature,secret})).valid,true);assert.equal((await run({kind:'slack',raw:rawSlack+' ',timestamp,signature,secret})).valid,false);
 } finally {await mf.dispose();}
});

test('Workerd/D1 elimina alertas de forma atómica, conserva itinerarios y bloquea reintentos',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {env} from 'cloudflare:workers';
  import {deleteManualNotice,saveManualNotice} from './lib/notifications';
  const owner={id:'11111111-1111-4111-8111-111111111111',email:'camilo@mac2you.co',username:'fixture',displayName:'Fixture',fullName:null,isOwner:true,permissions:[]};
  export default {async fetch(req:Request){const b=await req.json();try{
   if(b.action==='create')return Response.json({id:await saveManualNotice(owner,b.alert,async()=>true)});
   await deleteManualNotice({...owner,isOwner:b.owner!==false},b.id,b.confirmation,async()=>b.validSession!==false);return Response.json({ok:true});
  }catch(e){return Response.json({error:e.message},{status:e.status||502});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 let outbound=0;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-notices-delete'},bindings:{PAYROLL_MAIL_KEY:Buffer.alloc(32,7).toString('base64url')},outboundService:async()=>{outbound++;throw new Error('No external traffic in deletion tests');}});
 const {readFile,readdir}=await import('node:fs/promises');
 try{
  const db=await mf.getD1Database('DB');for(const name of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(x=>x.trim()).filter(Boolean))await db.prepare(statement).run();
  const user='11111111-1111-4111-8111-111111111111';await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,'fixture','user@example.invalid','Fixture','fixture','[]','fixture','fixture')").bind(user).run();
  const input={id:crypto.randomUUID(),title:'Alerta ficticia',body:'Sin notificaciones reales',recipients:[user]};
  const run=async body=>mf.dispatchFetch('https://local.example.invalid/notices',{method:'POST',body:JSON.stringify(body)});
  assert.equal((await run({action:'create',alert:input})).status,200);
  const remove={action:'deleteAlert',id:input.id,confirmation:input.id};assert.equal((await run({...remove,owner:false})).status,403);assert.equal((await run({...remove,validSession:false})).status,403);assert.equal((await run({...remove,confirmation:'bad'})).status,400);
  const itinerary=crypto.randomUUID();await db.prepare("INSERT INTO jac_notices(id,kind,title,created_at) VALUES (?,'itinerary','PDF ficticio','fixture')").bind(itinerary).run();assert.equal((await run({action:'deleteAlert',id:itinerary,confirmation:itinerary})).status,400);
  await db.prepare("CREATE TRIGGER fixture_abort_delete BEFORE DELETE ON jac_notice_recipients BEGIN SELECT RAISE(ABORT,'fixture rollback'); END").run();assert.equal((await run(remove)).status,502);assert.ok(await db.prepare('SELECT id FROM jac_notices WHERE id=?').bind(input.id).first());assert.equal(await db.prepare('SELECT id FROM jac_deleted_alerts WHERE id=?').bind(input.id).first(),null);await db.prepare('DROP TRIGGER fixture_abort_delete').run();
  assert.equal((await run(remove)).status,200);assert.equal((await run(remove)).status,200);assert.equal((await run({action:'create',alert:input})).status,410);
  assert.equal(await db.prepare('SELECT id FROM jac_notices WHERE id=?').bind(input.id).first(),null);assert.equal(await db.prepare('SELECT id FROM jac_notice_recipients WHERE notice_id=?').bind(input.id).first(),null);assert.ok(await db.prepare('SELECT id FROM jac_notices WHERE id=?').bind(itinerary).first());assert.equal(outbound,0);
 }finally{await mf.dispose();}
});

test('Workerd/D1/R2 borra un itinerario privado, revierte fallos y bloquea su reimportación',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {deleteItinerary,queueSlackFiles} from './lib/notifications';
  const owner={id:'11111111-1111-4111-8111-111111111111',email:'camilo@mac2you.co',username:'fixture',displayName:'Fixture',fullName:null,isOwner:true,permissions:[]};
  export default {async fetch(req:Request){const b=await req.json();try{
   if(b.action==='queue'){await queueSlackFiles([b.file]);return Response.json({ok:true});}
   await deleteItinerary({...owner,isOwner:b.owner!==false},b.id,b.confirmation,async()=>b.validSession!==false);return Response.json({ok:true});
  }catch(e){return Response.json({error:e.message},{status:e.status||502});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 let outbound=0;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-itinerary-delete'},r2Buckets:['BUCKET'],outboundService:async()=>{outbound++;throw new Error('No external traffic');}});
 const {readFile,readdir}=await import('node:fs/promises');
 try{
  const db=await mf.getD1Database('DB'),bucket=await mf.getR2Bucket('BUCKET');for(const name of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(x=>x.trim()).filter(Boolean))await db.prepare(statement).run();
  const id=crypto.randomUUID(),keep=crypto.randomUUID(),key='itineraries/FFIXTURE01.pdf',file='FFIXTURE01';
  await bucket.put(key,'%PDF-1.4 fixture only');await bucket.put('itineraries/keep.pdf','%PDF-1.4 keep');
  await db.prepare("INSERT INTO jac_notices(id,kind,title,file_key,source,created_at) VALUES (?,'itinerary','PDF ficticio',?,'slack:FFIXTURE01','fixture')").bind(id,key).run();
  await db.prepare("INSERT INTO jac_notices(id,kind,title,file_key,created_at) VALUES (?,'itinerary','Otro PDF','itineraries/keep.pdf','fixture')").bind(keep).run();
  await db.prepare("INSERT INTO jac_notice_recipients(id,notice_id,user_id) VALUES ('fixture',?,'fixture')").bind(id).run();
  await db.prepare("INSERT INTO jac_push_deliveries(id,notice_id,device_id,updated_at) VALUES ('fixture',?,'fixture','fixture')").bind(id).run();
  await db.prepare("INSERT INTO jac_slack_files(id,status,created_at) VALUES (?,'ready','fixture')").bind(file).run();
  const run=async body=>mf.dispatchFetch('https://local.example.invalid/notices',{method:'POST',body:JSON.stringify(body)}),remove={id,confirmation:id};
  assert.equal((await run({...remove,owner:false})).status,403);assert.equal((await run({...remove,validSession:false})).status,403);assert.equal((await run({...remove,confirmation:'bad'})).status,400);
  await db.prepare("CREATE TRIGGER fixture_itinerary_rollback BEFORE DELETE ON jac_notice_recipients BEGIN SELECT RAISE(ABORT,'fixture rollback'); END").run();assert.equal((await run(remove)).status,502);assert.ok(await bucket.get(key));assert.ok(await db.prepare('SELECT id FROM jac_notices WHERE id=?').bind(id).first());assert.equal(await db.prepare('SELECT id FROM jac_deleted_itineraries WHERE id=?').bind(id).first(),null);await db.prepare('DROP TRIGGER fixture_itinerary_rollback').run();
  assert.equal((await run(remove)).status,200);assert.equal((await run(remove)).status,200);
  assert.equal(await bucket.get(key),null);assert.ok(await bucket.get('itineraries/keep.pdf'));for(const table of ['jac_notices','jac_notice_recipients','jac_push_deliveries'])assert.equal(await db.prepare('SELECT id FROM '+table+' WHERE '+(table==='jac_notices'?'id':'notice_id')+'=?').bind(id).first(),null);
  const marker=await db.prepare('SELECT * FROM jac_deleted_itineraries WHERE id=?').bind(id).first();assert.equal(marker.source,'slack:'+file);assert.equal(marker.file_deleted,1);
  assert.equal((await run({action:'queue',file})).status,200);assert.equal((await db.prepare('SELECT status FROM jac_slack_files WHERE id=?').bind(file).first()).status,'deleted');assert.equal(outbound,0);
 }finally{await mf.dispose();}
});
