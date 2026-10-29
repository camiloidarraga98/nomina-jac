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

test('Workerd publica adjuntos privados de alertas e itinerarios y limpia R2 sin servicios reales',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {publishManualNotice,noticeItem,noticeAttachment,deleteManualNotice,deleteItinerary} from './lib/notifications';
  const owner={id:'11111111-1111-4111-8111-111111111111',email:'camilo@mac2you.co',username:'fixture',displayName:'Fixture',fullName:null,isOwner:true,permissions:[]};
  export default {async fetch(req:Request){const b=await req.json();try{
   const actor=b.reader?{...owner,id:'22222222-2222-4222-8222-222222222222',email:'reader@example.invalid',isOwner:false}:owner;
   if(b.action==='create')return Response.json({id:await publishManualNotice(actor,b.input,async()=>b.valid!==false)});
   if(b.action==='item')return Response.json(await noticeItem(actor,b.id));
   if(b.action==='file'){const f=await noticeAttachment(actor,b.id,b.file);return new Response(f.object.body,{headers:{'Content-Type':f.mimeType}});}
   await (b.kind==='alert'?deleteManualNotice:deleteItinerary)(actor,b.id,b.id,async()=>true);return Response.json({ok:true});
  }catch(e){return Response.json({error:e.message},{status:e.status||502});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-manual-uploads'},r2Buckets:['BUCKET'],outboundService:async()=>{throw Error('No external requests');}});
 const {readFile,readdir}=await import('node:fs/promises');
 try{
  const db=await mf.getD1Database('DB'),bucket=await mf.getR2Bucket('BUCKET');for(const name of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(x=>x.trim()).filter(Boolean))await db.prepare(statement).run();
  const owner='11111111-1111-4111-8111-111111111111',reader='22222222-2222-4222-8222-222222222222';for(const [id,name] of [[owner,'owner'],[reader,'reader']])await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,'fixture','[]','fixture','fixture')").bind(id,name,name+'@example.invalid',name).run();
  const run=body=>mf.dispatchFetch('https://fixture.example.invalid/notices',{method:'POST',body:JSON.stringify(body)});
  for(const kind of ['alert','itinerary']){
   const input={id:crypto.randomUUID(),kind,title:'Prueba local',body:'Contenido ficticio',recipients:kind==='alert'?[owner]:[],files:[{filename:'Prueba.pdf',data:Buffer.from('%PDF-1.4 local fixture').toString('base64')},{filename:'Foto.png',data:Buffer.from([137,80,78,71,13,10,26,10,0]).toString('base64')}]};
   assert.equal((await run({action:'create',input,reader:true})).status,403);assert.equal((await run({action:'create',input,valid:false})).status,403);
   assert.equal((await run({action:'create',input})).status,200);assert.equal((await run({action:'create',input})).status,200);const item=await (await run({action:'item',id:input.id})).json();assert.equal(item.attachments.length,2);
   assert.equal((await run({action:'file',id:input.id,file:item.attachments[0].id,reader:true})).status,kind==='alert'?404:200);
   const keys=(await db.prepare("SELECT file_key FROM jac_notice_attachments WHERE notice_id=? AND state='ready'").bind(input.id).all()).results.map(x=>x.file_key);assert.equal(keys.length,2);for(const key of keys)assert.ok(await bucket.get(key));
   await db.prepare("CREATE TRIGGER fixture_upload_delete BEFORE DELETE ON jac_notice_recipients BEGIN SELECT RAISE(ABORT,'rollback'); END").run();assert.equal((await run({action:'delete',id:input.id,kind})).status,502);for(const key of keys)assert.ok(await bucket.get(key));await db.prepare('DROP TRIGGER fixture_upload_delete').run();
   assert.equal((await run({action:'delete',id:input.id,kind})).status,200);assert.equal((await run({action:'delete',id:input.id,kind})).status,200);assert.equal((await run({action:'create',input})).status,410);for(const key of keys)assert.equal(await bucket.get(key),null);
  }
 }finally{await mf.dispose();}
});

test('Workerd/D1/R2: pases por destinatario, historial y permisos privados, sin salidas reales',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {publishManualNotice,boardingFeed,noticeItem,noticeAttachment,markNoticeRead,configureBoardingChannels} from './lib/notifications';
  const owner={id:'11111111-1111-4111-8111-111111111111',email:'camilo@mac2you.co',username:'fixture',displayName:'Fixture',fullName:null,isOwner:true,permissions:[]};
  export default {async fetch(req:Request){const b=await req.json(),actor=b.reader?{...owner,id:'22222222-2222-4222-8222-222222222222',email:'fixture@example.invalid',isOwner:false}:owner;try{
   if(b.action==='create')return Response.json({id:await publishManualNotice(actor,b.input,async()=>true)});
   if(b.action==='feed')return Response.json(await boardingFeed(actor,b.history));
   if(b.action==='item')return Response.json(await noticeItem(actor,b.id));
   if(b.action==='file'){const f=await noticeAttachment(actor,b.id,b.file);return new Response(f.object.body);}
   if(b.action==='read'){await markNoticeRead(actor,b.id);return Response.json({ok:true});}
  }catch(e){return Response.json({error:e.message},{status:e.status||502});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 let outbound=0;const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-private-passes'},r2Buckets:['BUCKET'],outboundService:async()=>{outbound++;throw Error('No external traffic');}});
 const {readFile,readdir}=await import('node:fs/promises');try{const db=await mf.getD1Database('DB');for(const name of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(x=>x.trim()).filter(Boolean))await db.prepare(statement).run();
 const owner='11111111-1111-4111-8111-111111111111',reader='22222222-2222-4222-8222-222222222222';for(const [id,name] of [[owner,'owner'],[reader,'reader']])await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,'fixture','[]','fixture','fixture')").bind(id,name,name+'@example.invalid',name).run();
 const run=b=>mf.dispatchFetch('https://fixture.example.invalid/passes',{method:'POST',body:JSON.stringify(b)}),input={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase privado ficticio',body:'',travelDate:'2090-10-10',recipients:[reader],files:[{filename:'Foto.png',data:Buffer.from([137,80,78,71,13,10,26,10,0]).toString('base64')}]};
 assert.equal((await run({action:'create',input})).status,200);assert.equal((await run({action:'create',input})).status,200);const item=await (await run({action:'item',id:input.id,reader:true})).json();assert.equal(item.travelDate,input.travelDate);assert.equal(item.attachments.length,1);
 for(const action of ['item','read','file'])assert.equal((await run({action,id:input.id,file:item.attachments[0].id})).status,404,'Camilo no hereda acceso al pase ajeno');assert.equal((await run({action:'file',id:input.id,file:item.attachments[0].id,reader:true})).status,200);
 assert.equal((await (await run({action:'feed',reader:true})).json()).notices.length,1);assert.equal((await (await run({action:'feed'})).json()).notices.length,0);assert.equal((await (await run({action:'feed',reader:true,history:true})).json()).notices.length,0);assert.equal(outbound,0);
 }finally{await mf.dispose();}
});

test('Workerd/D1/R2 confirma revisiones y revisa gastos atómicamente sin servicios externos',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {submitExpense,reviewExpense,expenseFeed} from './lib/travel-expenses';
  import {publishManualNotice,updateItinerary,confirmNotice,noticeItem} from './lib/notifications';
  const owner={id:'11111111-1111-4111-8111-111111111111',email:'fixture@example.invalid',username:'fixture',displayName:'Fixture',fullName:null,isOwner:true,permissions:[]};
  export default {async fetch(req:Request){const b=await req.json();try{
   if(b.action==='expense')return Response.json({id:await submitExpense(owner,b.input,async()=>true)});
   if(b.action==='review'){await reviewExpense(owner,b.input,async()=>true);return Response.json(await expenseFeed(owner));}
   if(b.action==='publish')return Response.json({id:await publishManualNotice(owner,b.input,async()=>true)});
   if(b.action==='update')return Response.json({id:await updateItinerary(owner,b.input,async()=>true)});
   if(b.action==='confirm')return Response.json(await confirmNotice(owner,b.id,b.revision,async()=>true));
   return Response.json(await noticeItem(owner,b.id));
  }catch(e){return Response.json({error:e.message},{status:e.status||502});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-travel-workflows'},r2Buckets:['BUCKET'],outboundService:async()=>{throw new Error('All external requests blocked');}});
 const {readFile,readdir}=await import('node:fs/promises');
 try{
  const db=await mf.getD1Database('DB');for(const f of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+f,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
  const user='11111111-1111-4111-8111-111111111111';await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,'fixture','fixture@example.invalid','Fixture','fixture','[]','fixture','fixture')").bind(user).run();
  const employee={id:'fixture-employee',name:'Persona ficticia',document:'',role:'',category:'musicos',active:true,showRate:0,kmRate:0,fixedService:0,withholding:0,ica:0,salary:0,transport:0,pension:false,health:false,cycle:'quincenal',monthlyHalf:1,nonSalary:0,contributionBase:0,incomeTax:0,solidarity:0},state={employees:[employee],concepts:[],settings:{company:'Fixture',nit:'',hourDivisor:210,hourFactors:[0,0,0,0,0,0,0]},periods:[]};
  await db.prepare("INSERT INTO payroll_state(id,data,version,updated_at,updated_by) VALUES ('jac',?,1,'fixture','fixture')").bind(JSON.stringify(state)).run();
  const period={id:'fixture-period',start:'2026-10-01',end:'2026-10-15',status:'abierta',shows:[],movements:[],routes:[],hours:[],excludedEmployees:[]};await db.prepare('INSERT INTO payroll_periods(id,data,start) VALUES (?,?,?)').bind(period.id,JSON.stringify(period),period.start).run();
  const run=body=>mf.dispatchFetch('https://fixture.example.invalid/travel',{method:'POST',body:JSON.stringify(body)}),files=[{filename:'Ficticio.pdf',data:Buffer.from('%PDF-1.4 fixture').toString('base64')}],id=crypto.randomUUID();
  assert.equal((await run({action:'expense',input:{id,concept:'Gasto ficticio',amount:50000,expenseDate:'2026-10-08',note:'',files}})).status,200);
  const review={id,version:1,decision:'approve',reason:'',employeeId:employee.id,periodId:period.id};
  await db.prepare("CREATE TRIGGER expense_abort BEFORE UPDATE ON jac_travel_expenses BEGIN SELECT RAISE(ABORT,'fixture rollback'); END").run();assert.equal((await run({action:'review',input:review})).status,502);
  assert.equal((await db.prepare("SELECT version FROM payroll_state WHERE id='jac'").first()).version,1);assert.deepEqual(JSON.parse((await db.prepare('SELECT data FROM payroll_periods WHERE id=?').bind(period.id).first()).data).movements,[]);await db.prepare('DROP TRIGGER expense_abort').run();
  const responses=await Promise.all([run({action:'review',input:review}),run({action:'review',input:review})]);assert.ok(responses.some(r=>r.status===200));assert.equal((await run({action:'review',input:review})).status,200);assert.equal(JSON.parse((await db.prepare('SELECT data FROM payroll_periods WHERE id=?').bind(period.id).first()).data).movements.length,1);
  const notice=crypto.randomUUID();assert.equal((await run({action:'publish',input:{id:notice,kind:'itinerary',title:'Itinerario ficticio',body:'',recipients:[],files}})).status,200);assert.equal((await run({action:'confirm',id:notice,revision:1})).status,200);
  const update={id:notice,requestId:crypto.randomUUID(),revision:1,title:'Itinerario actualizado',body:'',summary:'Cambió la hora de salida',files};assert.equal((await run({action:'update',input:update})).status,200);assert.equal((await run({action:'update',input:update})).status,200);assert.equal((await run({action:'confirm',id:notice,revision:1})).status,409);const current=await (await run({id:notice})).json();assert.equal(current.revision,2);assert.equal(current.confirmed,false);assert.equal(current.attachments.length,1);
 }finally{await mf.dispose();}
});

test('Workerd: secciones de avisos independientes, híbridos de fotografía y revocación actual en D1',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {env} from 'cloudflare:workers';
  import {publishManualNotice,noticeFeed,boardingFeed,noticeItem,noticeAttachment,confirmNotice} from './lib/notifications';
  const owner={id:'11111111-1111-4111-8111-111111111111',email:'fixture@example.invalid',username:'fixture',displayName:'Fixture',fullName:null,isOwner:true,permissions:[]};
  export default {async fetch(req:Request){const b=await req.json(),actor=b.actor?{...owner,id:b.actor,isOwner:false,mediaOnly:true,itinerariesOnly:true,sections:b.sections}:owner;try{
   if(b.action==='publish')return Response.json({id:await publishManualNotice(owner,b.input,async()=>true)});
   if(b.action==='feed')return Response.json(await noticeFeed(actor));
   if(b.action==='boarding')return Response.json(await boardingFeed(actor));
   if(b.action==='item')return Response.json(await noticeItem(actor,b.id));
   if(b.action==='file'){const f=await noticeAttachment(actor,b.id,b.file);return new Response(f.object.body);}
   if(b.action==='confirm')return Response.json(await confirmNotice(actor,b.id,1,async()=>{if(b.revoke)await env.DB.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').bind('["media"]',actor.id).run();return true;}));
  }catch(e){return Response.json({error:e.message},{status:e.status||502});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 let outbound=0;const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-notice-sections'},r2Buckets:['BUCKET'],outboundService:async()=>{outbound++;throw Error('No external traffic');}});
 const {readFile,readdir}=await import('node:fs/promises');
 try{
  const db=await mf.getD1Database('DB');for(const name of(await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())for(const statement of(await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(x=>x.trim()).filter(Boolean))await db.prepare(statement).run();
  const owner='11111111-1111-4111-8111-111111111111',alerts='22222222-2222-4222-8222-222222222222',travel='33333333-3333-4333-8333-333333333333',boarding='44444444-4444-4444-8444-444444444444';
  for(const [id,sections] of [[owner,null],[alerts,['media','alerts']],[travel,['media','itineraries']],[boarding,['media','boarding']]])await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,itineraries_only,section_access,created_at,updated_at) VALUES (?,?,?,?,'fixture','[]',?,?,?,'fixture','fixture')").bind(id,id,id+'@example.invalid','Fixture',id===owner?0:1,id===owner?0:1,sections?JSON.stringify(sections):null).run();
  const run=body=>mf.dispatchFetch('https://sections.example.invalid/notices',{method:'POST',body:JSON.stringify(body)}),files=[{filename:'Ficticio.pdf',data:Buffer.from('%PDF-1.4 fixture').toString('base64')}],alert={id:crypto.randomUUID(),kind:'alert',title:'Aviso ficticio',body:'Sin envíos reales',recipients:[alerts],files},itinerary={...alert,id:crypto.randomUUID(),kind:'itinerary',recipients:[]},pass={...alert,id:crypto.randomUUID(),kind:'boarding_pass',travelDate:'2090-10-10',recipients:[boarding]};
  for(const input of [alert,itinerary,pass])assert.equal((await run({action:'publish',input})).status,200);
  const a={actor:alerts,sections:['media','alerts']},t={actor:travel,sections:['media','itineraries']},b={actor:boarding,sections:['media','boarding']};
  assert.deepEqual((await(await run({action:'feed',...a})).json()).notices.map(n=>n.id),[alert.id]);
  assert.deepEqual((await(await run({action:'feed',...t})).json()).notices.map(n=>n.id),[itinerary.id]);
  assert.equal((await run({action:'boarding',...a})).status,403);assert.deepEqual((await(await run({action:'boarding',...b})).json()).notices.map(n=>n.id),[pass.id]);
  assert.equal((await run({action:'item',id:pass.id})).status,404);
  const item=await(await run({action:'item',id:alert.id,...a})).json();assert.equal((await run({action:'file',id:alert.id,file:item.attachments[0].id,...a})).status,200);
  assert.equal((await run({action:'confirm',id:alert.id,...a,revoke:true})).status,409);
  assert.equal((await run({action:'file',id:alert.id,file:item.attachments[0].id,...a})).status,404,'El objeto AccessUser previo no supera la revocación en D1');
  assert.equal((await db.prepare('SELECT confirmed_revision FROM jac_notice_recipients WHERE notice_id=? AND user_id=?').bind(alert.id,alerts).first()).confirmed_revision,0);assert.equal(outbound,0);
 }finally{await mf.dispose();}
});

test('Workerd/D1/R2 conserva la descripción del pase con su archivo y destinatario originales',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {env} from 'cloudflare:workers';
  import {queueSlackFiles,importSlackFiles,noticeItem} from './lib/notifications';
  import {encryptMail} from './lib/payroll-mail-core';
  const person={id:'77777777-7777-4777-8777-777777777777',email:'jhonalexcastano@gmail.com',username:'fixture',displayName:'Fixture',fullName:null,isOwner:false,permissions:[],sections:['boarding']};
  export default {async fetch(req:Request){const b=await req.json();try{
   if(b.action==='init'){
    const credentials=await encryptMail({slack:{token:'xoxb-fixture-only',signingSecret:'fixture-only'}},env.PAYROLL_MAIL_KEY);
    await env.DB.prepare("INSERT INTO jac_notice_settings(id,credentials) VALUES ('jac',?)").bind(credentials).run();return Response.json({ok:true});
   }
   if(b.action==='queue'){
    await queueSlackFiles([b.file],'C0C8FAPHTCG',b.text);
    return Response.json(await env.DB.prepare('SELECT boarding_message,status FROM jac_slack_files WHERE id=?').bind(b.file).first());
   }
   if(b.action==='import'){
    await importSlackFiles();
    return Response.json(await env.DB.prepare("SELECT id,body FROM jac_notices WHERE source=?").bind('slack:'+b.file).first());
   }
   return Response.json(await noticeItem(b.owner?{...person,id:'11111111-1111-4111-8111-111111111111',isOwner:true,sections:undefined}:person,b.id));
  }catch(e){return Response.json({error:e.message},{status:e.status||502});}}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*']});
 const bytes='%PDF-1.4\n% Synthetic private boarding pass only\n%%EOF',file='FBDWORKER01',channel='C0C8FAPHTCG';
 let outbound=0;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'fixture-boarding-description'},r2Buckets:['BUCKET'],bindings:{PAYROLL_MAIL_KEY:Buffer.alloc(32,7).toString('base64url')},outboundService:async request=>{
  outbound++;assert.equal(request.headers.get('authorization'),'Bearer xoxb-fixture-only');
  if(request.url==='https://slack.com/api/files.info?file='+file)return Response.json({ok:true,file:{id:file,name:'Jhon Alex 10 de octubre 2090 Bogota-Pereira.pdf',mimetype:'application/pdf',size:bytes.length,url_private_download:'https://files.slack.com/fixture-private.pdf',channels:[channel]}});
  if(request.url==='https://files.slack.com/fixture-private.pdf')return new Response(bytes,{headers:{'content-type':'application/pdf'}});
  throw Error('Every external service, history lookup and real push is blocked.');
 }});
 const {readFile,readdir}=await import('node:fs/promises');
 try{
  const db=await mf.getD1Database('DB');
  for(const name of(await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())for(const statement of(await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(x=>x.trim()).filter(Boolean))await db.prepare(statement).run();
  const person='77777777-7777-4777-8777-777777777777',owner='11111111-1111-4111-8111-111111111111';
  for(const [id,email,sections] of [[person,'jhonalexcastano@gmail.com','["boarding"]'],[owner,'owner@example.invalid',null]])await db.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,section_access,created_at,updated_at) VALUES (?,?,?,'Fixture','fixture','[]',?,'fixture','fixture')").bind(id,id,email,sections).run();
  await db.prepare("INSERT INTO jac_boarding_channels(id,user_id,created_at) VALUES (?,?,'fixture')").bind(channel,person).run();
  const run=body=>mf.dispatchFetch('https://boarding.example.invalid/message',{method:'POST',body:JSON.stringify(body)});
  assert.equal((await run({action:'init'})).status,200);
  const text='*Silla:* Sin asignar\nHora de salida: 00:30 (hora Colombia, UTC−5)\nHora en sala: 23:20 (hora Colombia, UTC−5)\nAerolínea: LATAM',canonical='Silla: Sin asignar\nHora de salida: 00:30\nHora en sala: 23:20\nAerolínea: LATAM';
  const queued=await(await run({action:'queue',file,text})).json();assert.equal(queued.boarding_message,canonical);assert.equal(queued.status,'pending');assert.equal(outbound,0,'El snapshot se guarda antes de consultar o descargar el PDF.');
  const replay=await(await run({action:'queue',file,text:'Silla: 22C\nHora de salida: 21:10'})).json();assert.equal(replay.boarding_message,canonical);
  const imported=await(await run({action:'import',file})).json();assert.ok(imported.id);assert.equal(imported.body,canonical);assert.equal(outbound,2);
  const item=await(await run({id:imported.id})).json();assert.deepEqual(item.boardingDetails,{seat:'',departureTime:'00:30',boardingTime:'23:20',airline:'LATAM'});assert.equal(item.attachments.length,1);
  assert.equal((await run({id:imported.id,owner:true})).status,404);
  await run({action:'import',file});assert.equal((await db.prepare('SELECT count(*) n FROM jac_notices WHERE source=?').bind('slack:'+file).first()).n,1);assert.equal(outbound,2);
  await db.prepare("UPDATE payroll_users SET section_access='[\"media\"]' WHERE id=?").bind(person).run();assert.equal((await run({id:imported.id})).status,404,'La descripción queda retirada con el mismo permiso del pase.');
 }finally{await mf.dispose();}
});
