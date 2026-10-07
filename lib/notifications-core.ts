export const ITINERARY_TEAM='T0C5NQZE8HL';
export const ITINERARY_CHANNEL='C0C6V85SRL6';
export const APP_TOPIC='co.jacmusic.nomina';
export const MAX_PDF_BYTES=10*1024*1024;
export class NoticeFailure extends Error {constructor(message:string,public status=400){super(message);}}
export type Notice={id:string;kind:'itinerary'|'alert';title:string;body:string;filename:string;size:number;createdAt:string;read:boolean};
export type WebSubscription={endpoint:string;keys:{p256dh:string;auth:string}};
export type PushCredentials={apns?:{teamId:string;keyId:string;privateKey:string};slack?:{token:string;signingSecret:string};web?:{publicKey:string;privateKey:JsonWebKey}};
export const base64url=(bytes:Uint8Array)=>btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
export function unbase64(value:string){if(!/^[\w-]+$/.test(value))throw new NoticeFailure('La suscripción no es válida.');return Uint8Array.from(atob(value.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));}
const concat=(...parts:Uint8Array[])=>{const out=new Uint8Array(parts.reduce((n,p)=>n+p.length,0));let i=0;for(const p of parts){out.set(p,i);i+=p.length;}return out;};
const utf8=(s:string)=>new TextEncoder().encode(s);
export function validPushEndpoint(value:string){
 let u:URL;try{u=new URL(value);}catch{throw new NoticeFailure('El navegador devolvió una suscripción no válida.');}
 if(value.length>4096||u.protocol!=='https:'||u.username||u.password||u.port||u.hash||!(u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||u.hostname==='web.push.apple.com'||u.hostname.endsWith('.push.apple.com')||u.hostname.endsWith('.notify.windows.com')))throw new NoticeFailure('Este servicio de notificaciones del navegador no está admitido.');
 return u;
}
export function validateSubscription(value:WebSubscription){validPushEndpoint(value.endpoint);if(unbase64(value.keys.p256dh).length!==65||unbase64(value.keys.auth).length!==16)throw new NoticeFailure('Las claves del navegador no son válidas.');return value;}
export async function createWebKeys(){const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);return {publicKey:base64url(new Uint8Array(await crypto.subtle.exportKey('raw',pair.publicKey))),privateKey:await crypto.subtle.exportKey('jwk',pair.privateKey)};}
export async function appleKey(pem:string){
 const body=pem.replace('-----BEGIN PRIVATE KEY-----','').replace('-----END PRIVATE KEY-----','').replace(/\s/g,'');
 try{return await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(body),c=>c.charCodeAt(0)),{name:'ECDSA',namedCurve:'P-256'},false,['sign']);}catch{throw new NoticeFailure('La clave de Apple debe ser un archivo .p8 válido.');}
}
async function jwt(header:object,claims:object,key:CryptoKey){const value=base64url(utf8(JSON.stringify(header)))+'.'+base64url(utf8(JSON.stringify(claims)));return value+'.'+base64url(new Uint8Array(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,utf8(value))));}
async function hkdf(secret:Uint8Array<ArrayBuffer>,salt:Uint8Array<ArrayBuffer>,info:string|Uint8Array<ArrayBuffer>,size:number){const key=await crypto.subtle.importKey('raw',secret,'HKDF',false,['deriveBits']);return new Uint8Array(await crypto.subtle.deriveBits({name:'HKDF',hash:'SHA-256',salt,info:typeof info==='string'?utf8(info):info},key,size*8));}
export async function webPushRequest(subscription:WebSubscription,credentials:NonNullable<PushCredentials['web']>,payload:string){
 const url=validPushEndpoint(subscription.endpoint),recipient=unbase64(subscription.keys.p256dh),auth=unbase64(subscription.keys.auth);
 if(recipient.length!==65||auth.length!==16||utf8(payload).length>3000)throw new NoticeFailure('No se pudo preparar la notificación.');
 const peer=await crypto.subtle.importKey('raw',recipient,{name:'ECDH',namedCurve:'P-256'},false,[]),pair=await crypto.subtle.generateKey({name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);
 const publicKey=new Uint8Array(await crypto.subtle.exportKey('raw',pair.publicKey)),shared=new Uint8Array(await crypto.subtle.deriveBits({name:'ECDH',public:peer},pair.privateKey,256));
 const ikm=await hkdf(shared,auth,concat(utf8('WebPush: info\0'),recipient,publicKey),32),salt=crypto.getRandomValues(new Uint8Array(16));
 const cek=await hkdf(ikm,salt,'Content-Encoding: aes128gcm\0',16),nonce=await hkdf(ikm,salt,'Content-Encoding: nonce\0',12),aes=await crypto.subtle.importKey('raw',cek,'AES-GCM',false,['encrypt']);
 const encrypted=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv:nonce},aes,concat(utf8(payload),new Uint8Array([2]))));
 const header=new Uint8Array(21);header.set(salt);new DataView(header.buffer).setUint32(16,4096);header[20]=publicKey.length;
 const key=await crypto.subtle.importKey('jwk',credentials.privateKey,{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
 const token=await jwt({typ:'JWT',alg:'ES256'},{aud:url.origin,exp:Math.floor(Date.now()/1000)+3600,sub:'mailto:camilo@mac2you.co'},key);
 return {url,options:{method:'POST',headers:{Authorization:'vapid t='+token+', k='+credentials.publicKey,'Content-Encoding':'aes128gcm','Content-Type':'application/octet-stream',TTL:'86400',Urgency:'normal'},body:concat(header,publicKey,encrypted),redirect:'manual',signal:AbortSignal.timeout(8000)} satisfies RequestInit};
}
export async function applePushRequest(token:string,environment:string,credentials:NonNullable<PushCredentials['apns']>,id:string){
 if(!/^[a-f0-9]{64,200}$/.test(token)||!['sandbox','production'].includes(environment))throw new NoticeFailure('El registro del iPhone no es válido.');
 const authorization=await jwt({alg:'ES256',kid:credentials.keyId},{iss:credentials.teamId,iat:Math.floor(Date.now()/1000)},await appleKey(credentials.privateKey));
 const url='https://'+(environment==='sandbox'?'api.sandbox.push.apple.com':'api.push.apple.com')+'/3/device/'+token;
 return {url,options:{method:'POST',headers:{Authorization:'bearer '+authorization,'Content-Type':'application/json','apns-topic':APP_TOPIC,'apns-push-type':'alert','apns-priority':'10','apns-id':id,'apns-collapse-id':id,'apns-expiration':String(Math.floor(Date.now()/1000)+86400)},body:JSON.stringify({aps:{alert:{title:'JAC',body:'Tienes un aviso nuevo. Abre JAC para consultarlo.'},sound:'default'},noticeId:id}),redirect:'manual',signal:AbortSignal.timeout(8000)} satisfies RequestInit};
}
export async function verifySlack(raw:string,timestamp:string,signature:string,secret:string){
 if(!/^\d{10}$/.test(timestamp)||Math.abs(Date.now()/1000-Number(timestamp))>300||!/^v0=[a-f0-9]{64}$/.test(signature))return false;
 const key=await crypto.subtle.importKey('raw',utf8(secret),{name:'HMAC',hash:'SHA-256'},false,['verify']);
 return crypto.subtle.verify('HMAC',key,Uint8Array.from(signature.slice(3).match(/../g)!,x=>parseInt(x,16)),utf8('v0:'+timestamp+':'+raw));
}
