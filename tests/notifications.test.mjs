import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {build} from 'esbuild';
import {mkdtemp,readFile,readdir,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHmac,createECDH,hkdfSync,createDecipheriv,createPublicKey,verify} from 'node:crypto';

// D1 and R2 in memory. Every outbound request is simulated; no Slack files,
// real accounts, production pushes, payroll changes or emails are involved.
const sql=new DatabaseSync(':memory:');for(const f of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+f,'utf8'));
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() n').get().n)}};return {results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async run(){return this.execute();}async all(){return this.execute();}async first(){return sql.prepare(this.text).get(...this.args)||null;}
}
const bucket=new Map();let writes=0,waiting=[];
globalThis.__noticesEnv={DB:{prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const out=qs.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},BUCKET:{put:async(k,v)=>{if(bucket.has(k))return null;bucket.set(k,new Uint8Array(v));writes++;return {key:k};},get:async k=>bucket.has(k)?{body:new Response(bucket.get(k)).body}:null},PAYROLL_AUTH_KEY:'notices-independent-authentication-key-tests-only',PAYROLL_MAIL_KEY:Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url')};
globalThis.__noticesHeaders=new Headers();globalThis.__noticesWait=p=>waiting.push(p);
const bundle=await build({stdin:{contents:"export * as api from './app/api/notices/route';export * as slack from './app/api/notices/slack/route';export * as pdf from './app/api/notices/pdf/route';export * as auth from './app/api/auth/route';export * from './lib/notifications';export * from './lib/notifications-core';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'test'}));b.onLoad({filter:/.*/,namespace:'test'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__noticesEnv;export const waitUntil=globalThis.__noticesWait;':'export const headers=async()=>globalThis.__noticesHeaders;',loader:'js'}));}}]});
const dir=await mkdtemp(resolve('work/notices-tests-')),file=dir+'/bundle.mjs';await writeFile(file,bundle.outputFiles[0].contents);const m=await import(pathToFileURL(file).href);await rm(dir,{recursive:true});
const owner=await m.bootstrapOwner('notice-owner','1'),ownerToken=await m.makeSession(owner),luisa=sql.prepare('SELECT id FROM payroll_users WHERE email=?').get('info@jacmusic.co').id,paula=sql.prepare('SELECT id FROM payroll_users WHERE email=?').get('contabilidad@jacmusic.co').id;
for(const id of [luisa,paula])sql.prepare('UPDATE payroll_users SET password_hash=?,permissions=? WHERE id=?').run(m.hashPassword('1',globalThis.__noticesEnv.PAYROLL_AUTH_KEY),'[]',id);
let luisaToken=await m.makeSession(luisa),paulaToken=await m.makeSession(paula),calls=[],hook;
const pdfBytes=new TextEncoder().encode('%PDF-1.4\n% Simulated itinerary PDF only\n%%EOF');
const slackSecret='a'.repeat(32),slackToken='xoxb-simulated-not-a-real-bot-token';
let fileMeta={id:'FTESTPDF001',mimetype:'application/pdf',name:'Itinerario_simulado.pdf',size:pdfBytes.length,url_private_download:'https://files.slack.com/simulated.pdf',channels:[m.ITINERARY_CHANNEL]};
globalThis.fetch=async(input,options={})=>{
 const url=new URL(String(input));calls.push({url,options});if(hook){const reply=await hook(url,options);if(reply)return reply;}
 if(url.origin==='https://slack.com'&&url.pathname==='/api/auth.test')return Response.json({ok:true,team_id:m.ITINERARY_TEAM});
 if(url.origin==='https://slack.com'&&url.pathname==='/api/conversations.info')return Response.json({ok:true,channel:{id:m.ITINERARY_CHANNEL,is_member:true,is_archived:false}});
 if(url.origin==='https://slack.com'&&url.pathname==='/api/files.info')return Response.json({ok:true,file:{...fileMeta,id:url.searchParams.get('file')}});
 if(url.origin==='https://files.slack.com')return new Response(pdfBytes,{headers:{'Content-Type':'application/pdf'}});
 if(['https://api.sandbox.push.apple.com','https://api.push.apple.com','https://fcm.googleapis.com'].includes(url.origin))return new Response(null,{status:200});
 throw new Error('This test blocks all external network traffic.');
};
const base='https://notices.example.invalid';
async function settle(){while(waiting.length){const jobs=waiting;waiting=[];await Promise.all(jobs);}}
async function api(token,body,query=''){
 const cookie=token?'__Host-jac_session='+token:'';globalThis.__noticesHeaders=new Headers({cookie,host:'notices.example.invalid'});
 const req=new Request(base+'/api/notices'+query,body?{method:'POST',headers:{cookie,origin:base,'Content-Type':'application/json'},body:JSON.stringify(body)}:{headers:{cookie}});
 const r=await m.api[body?'POST':'GET'](req),result={status:r.status,body:await r.json(),headers:r.headers};await settle();return result;
}
async function configure(kind,extra={}){return api(ownerToken,{action:'configure',kind,version:(await m.noticeConfig()).version,...extra});}
async function slack(body,{timestamp=String(Math.floor(Date.now()/1000)),bad=false}={}){const raw=JSON.stringify(body),signature='v0='+createHmac('sha256',slackSecret).update('v0:'+timestamp+':'+raw).digest('hex');const r=await m.slack.POST(new Request(base+'/api/notices/slack',{method:'POST',headers:{'x-slack-request-timestamp':timestamp,'x-slack-signature':bad?'v0='+('0'.repeat(64)):signature},body:raw}));await settle();return r;}
const event=(id='FTESTPDF001',channel=m.ITINERARY_CHANNEL)=>({type:'event_callback',team_id:m.ITINERARY_TEAM,event_id:'EV'+id,event:{type:'message',channel,text:'This Slack summary must never become itinerary content.',files:[{id,mimetype:'application/pdf'}]}});
const alert=(recipients=[luisa])=>({id:crypto.randomUUID(),title:'Aviso de prueba',body:'Mensaje simulado',recipients});
let applePublic;

test('lectura exige sesión propia; solo Camilo crea alertas/configura, con origen válido',async()=>{
 assert.equal((await api('')).status,401);assert.equal((await api(luisaToken,{action:'alert',alert:alert()})).status,403);assert.equal((await api(paulaToken,{action:'configure',kind:'web',version:0})).status,403);
 globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+ownerToken});const r=await m.api.POST(new Request(base+'/api/notices',{method:'POST',headers:{origin:'https://untrusted.example.invalid'},body:'{}'}));assert.equal(r.status,403);
 const list=await api(luisaToken);assert.equal(list.status,200);assert.deepEqual(list.body.users,[]);assert.match(list.headers.get('cache-control'),/private, no-store/);
});
test('configuración cifra claves y comprueba Slack; CAS protege cambios y no expone secretos',async()=>{
 const web=await configure('web');assert.equal(web.status,200);assert.ok(web.body.settings.webPublicKey);
 const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);applePublic=await crypto.subtle.exportKey('jwk',pair.publicKey);const pkcs8=Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey));const privateKey='-----BEGIN PRIVATE KEY-----\n'+pkcs8.toString('base64')+'\n-----END PRIVATE KEY-----';
 assert.equal((await configure('apple',{teamId:'TESTTEAM01',keyId:'TESTKEY001',privateKey})).status,200);
 assert.equal((await configure('slack',{token:slackToken,signingSecret:slackSecret})).status,200);
 assert.equal((await api(ownerToken,{action:'configure',kind:'web',version:0})).status,409);
 const cipher=(await m.noticeConfig()).credentials;assert.ok(!cipher.includes(slackToken));const feed=await api(ownerToken);const json=JSON.stringify(feed.body);assert.ok(!json.includes(slackToken));assert.ok(!json.includes('PRIVATE KEY'));assert.equal(feed.body.settings.slackConnected,true);
 hook=url=>url.pathname==='/api/auth.test'?Response.json({ok:true,team_id:'T_OTHER_WORKSPACE'}):null;assert.equal((await configure('slack',{token:slackToken,signingSecret:slackSecret})).status,400);hook=null;
});
let iosID=crypto.randomUUID(),webID=crypto.randomUUID(),subscription;
test('dispositivos se asocian al usuario autenticado; suscripciones inválidas y destinos ajenos se rechazan',async()=>{
 const ecdh=createECDH('prime256v1');ecdh.generateKeys();subscription={endpoint:'https://fcm.googleapis.com/fcm/send/simulated-device',keys:{p256dh:ecdh.getPublicKey().toString('base64url'),auth:Buffer.alloc(16,4).toString('base64url')}};
 assert.equal((await api(luisaToken,{action:'register',id:iosID,platform:'ios',token:'ab'.repeat(32),environment:'sandbox'})).status,200);
 assert.equal((await api(paulaToken,{action:'register',id:webID,platform:'web',subscription})).status,200);
 assert.equal((await api(luisaToken,{action:'register',id:crypto.randomUUID(),platform:'web',subscription:{...subscription,endpoint:'http://127.0.0.1/private'}})).status,400);
 assert.equal((await api(luisaToken,{action:'register',id:crypto.randomUUID(),platform:'ios',token:'bad',environment:'sandbox'})).status,400);
 assert.ok(!sql.prepare('SELECT data FROM jac_push_devices WHERE id=?').get(iosID).data.includes('ab'.repeat(32)));
});
let manual;
test('alerta llega solo a seleccionados; reintentos conservan un registro y no duplican push',async()=>{
 manual=alert();calls=[];const r=await api(ownerToken,{action:'alert',alert:manual});assert.equal(r.status,200);const pushes=calls.filter(x=>x.url.hostname.includes('push.apple.com'));assert.equal(pushes.length,1);assert.ok(pushes[0].url.hostname.startsWith('api.sandbox.'));assert.equal(pushes[0].options.redirect,'manual');assert.equal(pushes[0].options.headers['apns-topic'],m.APP_TOPIC);assert.equal(JSON.parse(pushes[0].options.body).noticeId,manual.id);
 const jwt=pushes[0].options.headers.Authorization.split(' ')[1],parts=jwt.split('.');assert.equal(JSON.parse(Buffer.from(parts[1],'base64url')).iss,'TESTTEAM01');assert.ok(verify('sha256',Buffer.from(parts.slice(0,2).join('.')),{key:createPublicKey({key:applePublic,format:'jwk'}),dsaEncoding:'ieee-p1363'},Buffer.from(parts[2],'base64url')));
 assert.ok((await api(luisaToken)).body.notices.some(x=>x.id===manual.id));assert.ok(!(await api(paulaToken)).body.notices.some(x=>x.id===manual.id));assert.equal((await api(paulaToken,undefined,'?item='+manual.id)).status,404);
 await api(ownerToken,{action:'read',id:manual.id});calls=[];assert.equal((await api(ownerToken,{action:'alert',alert:manual})).status,200);assert.equal(calls.filter(x=>x.url.hostname.includes('push.apple.com')).length,0);assert.equal(sql.prepare('SELECT COUNT(*) n FROM jac_notices WHERE id=?').get(manual.id).n,1);
 assert.equal((await api(ownerToken,{action:'alert',alert:{...manual,title:'Different payload'}})).status,409);
 assert.equal((await api(ownerToken,{action:'alert',alert:{...alert(),recipients:[]}})).status,400);
});
test('firma/timestamp/workspace/canal y tipo PDF controlan los eventos de Slack',async()=>{
 assert.equal((await slack(event(),{bad:true})).status,401);assert.equal((await slack(event(),{timestamp:String(Math.floor(Date.now()/1000)-600)})).status,401);
 assert.equal((await slack({...event(),team_id:'T_OTHER'})).status,403);
 await slack(event('FIGNORED001','C_OTHER'));await slack({...event('FIGNORED002'),event:{type:'message',channel:m.ITINERARY_CHANNEL,files:[{id:'FIGNORED002',mimetype:'text/plain'}]}});
 assert.equal(sql.prepare('SELECT COUNT(*) n FROM jac_slack_files').get().n,0);
 const challenge=await slack({type:'url_verification',challenge:'test-challenge'});assert.deepEqual(await challenge.json(),{challenge:'test-challenge'});
});
let imported;
test('PDF se guarda antes del aviso, sin texto Slack; replays no duplican archivo ni notificación',async()=>{
 calls=[];const before=writes;assert.equal((await slack(event())).status,200);imported=sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:FTESTPDF001');assert.ok(imported);assert.equal(imported.body,'');assert.equal(imported.kind,'itinerary');assert.equal(writes,before+1);assert.ok(bucket.has(imported.file_key));
 const delivered=sql.prepare('SELECT COUNT(*) n FROM jac_push_deliveries WHERE notice_id=? AND status=?').get(imported.id,'sent').n;assert.equal(delivered,2);
 calls=[];await slack(event());assert.equal(writes,before+1);assert.equal(calls.filter(x=>x.options.method==='POST').length,0);assert.equal(sql.prepare('SELECT COUNT(*) n FROM jac_notices WHERE source=?').get('slack:FTESTPDF001').n,1);
 assert.ok((await api(luisaToken)).body.notices.some(x=>x.id===imported.id));assert.ok((await api(paulaToken)).body.notices.some(x=>x.id===imported.id));
});
test('PDF necesita autenticación y autorización; se sirve privado sin rutas públicas de R2',async()=>{
 globalThis.__noticesHeaders=new Headers();assert.equal((await m.pdf.GET(new Request(base+'/api/notices/pdf?id='+imported.id))).status,401);
 globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+paulaToken});const result=await m.pdf.GET(new Request(base+'/api/notices/pdf?id='+imported.id));assert.equal(result.status,200);assert.equal(result.headers.get('content-type'),'application/pdf');assert.match(result.headers.get('cache-control'),/no-store/);assert.deepEqual(new Uint8Array(await result.arrayBuffer()),pdfBytes);
 assert.equal((await m.pdf.GET(new Request(base+'/api/notices/pdf?id='+manual.id))).status,404);
});
test('archivo falso/grande, canal distinto o URL externa no publican PDF ni generan push',async()=>{
 for(const [id,changes] of [['FBADPDF001',{mimetype:'text/plain'}],['FBADPDF002',{size:m.MAX_PDF_BYTES+1}],['FBADPDF003',{channels:['C_OTHER']}],['FBADPDF004',{url_private_download:'https://untrusted.example.invalid/file.pdf'}]]){fileMeta={...fileMeta,...changes};const old=writes;await slack(event(id));assert.equal(writes,old);assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get(id).status,'failed');fileMeta={id:'FTESTPDF001',mimetype:'application/pdf',name:'Itinerario_simulado.pdf',size:pdfBytes.length,url_private_download:'https://files.slack.com/simulated.pdf',channels:[m.ITINERARY_CHANNEL]};}
 hook=url=>url.origin==='https://files.slack.com'?new Response('not a pdf'):null;await slack(event('FBADPDF005'));hook=null;assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get('FBADPDF005').status,'failed');
});
test('Web Push se descifra según RFC 8291 y VAPID valida audiencia/firma ES256',async()=>{
 const receiver=createECDH('prime256v1');receiver.generateKeys();const auth=Buffer.alloc(16,7),sub={endpoint:'https://fcm.googleapis.com/fcm/send/test',keys:{p256dh:receiver.getPublicKey().toString('base64url'),auth:auth.toString('base64url')}},keys=await m.createWebKeys(),payload='{"id":"prueba-rfc"}';
 const request=await m.webPushRequest(sub,keys,payload),body=Buffer.from(request.options.body),salt=body.subarray(0,16),len=body[20],sender=body.subarray(21,21+len),cipher=body.subarray(21+len),shared=receiver.computeSecret(sender);
 const ikm=Buffer.from(hkdfSync('sha256',shared,auth,Buffer.concat([Buffer.from('WebPush: info\0'),receiver.getPublicKey(),sender]),32));
 const key=Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: aes128gcm\0'),16)),nonce=Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: nonce\0'),12));
 const decipher=createDecipheriv('aes-128-gcm',key,nonce);decipher.setAuthTag(cipher.subarray(-16));const decoded=Buffer.concat([decipher.update(cipher.subarray(0,-16)),decipher.final()]);assert.equal(decoded.at(-1),2);assert.equal(decoded.subarray(0,-1).toString(),payload);assert.equal(body.readUInt32BE(16),4096);
 const token=request.options.headers.Authorization.match(/t=([^,]+)/)[1],parts=token.split('.');assert.equal(JSON.parse(Buffer.from(parts[1],'base64url')).aud,'https://fcm.googleapis.com');const publicKey={...keys.privateKey};delete publicKey.d;publicKey.key_ops=['verify'];assert.ok(verify('sha256',Buffer.from(parts.slice(0,2).join('.')),{key:createPublicKey({key:publicKey,format:'jwk'}),dsaEncoding:'ieee-p1363'},Buffer.from(parts[2],'base64url')));
 assert.throws(()=>m.validPushEndpoint('https://fcm.googleapis.com@127.0.0.1/private'));assert.throws(()=>m.validPushEndpoint('https://fcm.googleapis.com:444/private'));assert.throws(()=>m.validPushEndpoint('https://untrusted.example.invalid/push'));
});
test('cuentas desactivadas o versión revocada no reciben; un error incierto no se reenvía automáticamente',async()=>{
 sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(luisa);calls=[];await api(ownerToken,{action:'alert',alert:alert([luisa])});assert.equal(calls.filter(x=>x.url.hostname.includes('push.apple.com')).length,0);assert.equal((await api(luisaToken)).status,401);
 luisaToken=await m.makeSession(luisa);await api(luisaToken,{action:'register',id:iosID,platform:'ios',token:'ab'.repeat(32),environment:'sandbox'});
 hook=url=>{if(url.hostname.includes('push.apple.com'))throw new Error('Simulated transport interruption');return null;};const a=alert();await api(ownerToken,{action:'alert',alert:a});hook=null;assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE notice_id=?').get(a.id).status,'uncertain');calls=[];await m.dispatchPush();assert.equal(calls.length,0);
});
test('logout desactiva únicamente el dispositivo ligado a esa sesión; las otras cuentas se conservan',async()=>{
 globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+luisaToken});const r=await m.auth.POST(new Request(base+'/api/auth',{method:'POST',headers:{origin:base,cookie:'__Host-jac_session='+luisaToken},body:JSON.stringify({action:'logout',notificationDeviceId:iosID})}));assert.equal(r.status,200);assert.equal(sql.prepare('SELECT enabled FROM jac_push_devices WHERE id=?').get(iosID).enabled,0);assert.equal(sql.prepare('SELECT enabled FROM jac_push_devices WHERE id=?').get(webID).enabled,1);
});
test('paginación y apertura directa permiten consultar avisos antiguos con el mismo control de acceso',async()=>{
 for(let i=0;i<42;i++){const id=crypto.randomUUID();sql.prepare("INSERT INTO jac_notices (id,kind,title,created_at) VALUES (?,'itinerary',?,?)").run(id,'PDF simulado '+i,new Date(Date.now()+i*1000).toISOString());}
 const first=await api(paulaToken);assert.equal(first.body.notices.length,40);assert.ok(first.body.nextCursor);const next=await api(paulaToken,undefined,'?cursor='+encodeURIComponent(first.body.nextCursor));assert.ok(next.body.notices.length);assert.ok(!next.body.notices.some(x=>first.body.notices.some(y=>y.id===x.id)));assert.equal((await api(paulaToken,undefined,'?item='+imported.id)).status,200);
 assert.equal(sql.prepare('SELECT COUNT(*) n FROM payroll_mail_jobs').get().n,0);assert.equal(sql.prepare('SELECT COUNT(*) n FROM payroll_periods').get().n,0);
});

test('un mensaje con varios PDF importa todos antes de preparar sus avisos, sin copiar otros adjuntos',async()=>{
 const ids=['FMULTIPDF01','FMULTIPDF02','FMULTIPDF03'],before=writes;
 const body=event(ids[0]);body.event.files=[...ids.map(id=>({id,mimetype:'application/pdf'})),{id:'FIGNORED999',mimetype:'image/png'}];
 assert.equal((await slack(body)).status,200);assert.equal(writes,before+ids.length);
 for(const id of ids){const row=sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:'+id);assert.ok(row);assert.equal(row.body,'');assert.ok(bucket.has(row.file_key));assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get(id).status,'ready');}
 assert.equal(sql.prepare('SELECT COUNT(*) n FROM jac_slack_files WHERE id=?').get('FIGNORED999').n,0);
});
