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
   const out=b.kind==='web'?await webPushRequest(b.subscription,keys!,b.payload):await applePushRequest(b.token,b.environment,b.credentials,b.id);
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
  const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),apple={kind:'apple',token:'ab'.repeat(32),environment:'sandbox',id:'33333333-3333-4333-8333-333333333333',credentials:{teamId:'TESTTEAM01',keyId:'TESTKEY001',privateKey:pair.privateKey.export({type:'pkcs8',format:'pem'})}};
  assert.equal((await run(apple)).status,200);const apns=calls.at(-1),jwt=apns.headers.get('authorization').slice(7).split('.');assert.ok(verify('sha256',Buffer.from(jwt.slice(0,2).join('.')),{key:pair.publicKey,dsaEncoding:'ieee-p1363'},Buffer.from(jwt[2],'base64url')));assert.equal(apns.headers.get('apns-topic'),'co.jacmusic.nomina');assert.equal(JSON.parse(apns.body).noticeId,apple.id);
  await run({...apple,id:'55555555-5555-4555-8555-555555555555'});assert.equal(calls.at(-1).headers.get('authorization'),apns.headers.get('authorization'),'APNs reutiliza el token; no genera actualizaciones excesivas por cada destinatario.');
  const rotated=generateKeyPairSync('ec',{namedCurve:'prime256v1'});await run({...apple,credentials:{...apple.credentials,privateKey:rotated.privateKey.export({type:'pkcs8',format:'pem'})}});assert.notEqual(calls.at(-1).headers.get('authorization'),apns.headers.get('authorization'),'Rotar la clave invalida el token en memoria.');
  redirect=true;for(const b of [input,apple]){const before=calls.length;assert.equal((await run(b)).status,307);assert.equal(calls.length,before+1);}
  const rawSlack='{"type":"url_verification"}',timestamp=String(Math.floor(Date.now()/1000)),secret='b'.repeat(32),signature='v0='+createHmac('sha256',secret).update('v0:'+timestamp+':'+rawSlack).digest('hex');
  assert.equal((await run({kind:'slack',raw:rawSlack,timestamp,signature,secret})).valid,true);assert.equal((await run({kind:'slack',raw:rawSlack+' ',timestamp,signature,secret})).valid,false);
 } finally {await mf.dispose();}
});
