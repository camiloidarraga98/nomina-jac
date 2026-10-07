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
 async run(){return this.execute();}async all(){return this.execute();}async first(){if(beforeFirst)await beforeFirst(this);return sql.prepare(this.text).get(...this.args)||null;}
}
const bucket=new Map();let writes=0,waiting=[],beforeFirst,beforePut,beforeDelete;
globalThis.__noticesEnv={DB:{prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const out=qs.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},BUCKET:{put:async(k,v)=>{if(beforePut)await beforePut(k);if(bucket.has(k))return null;bucket.set(k,new Uint8Array(v));writes++;return {key:k};},delete:async k=>{const after=await beforeDelete?.(k);bucket.delete(k);if(after)await after();},get:async k=>bucket.has(k)?{body:new Response(bucket.get(k)).body}:null},PAYROLL_AUTH_KEY:'notices-independent-authentication-key-tests-only',PAYROLL_MAIL_KEY:Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url')};
globalThis.__noticesHeaders=new Headers();globalThis.__noticesWait=p=>waiting.push(p);
const bundle=await build({stdin:{contents:"export * as api from './app/api/notices/route';export * as slack from './app/api/notices/slack/route';export * as pdf from './app/api/notices/pdf/route';export * as publish from './app/api/notices/publish/route';export * as attachment from './app/api/notices/file/route';export * as auth from './app/api/auth/route';export * from './lib/notifications';export * from './lib/notifications-core';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'test'}));b.onLoad({filter:/.*/,namespace:'test'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__noticesEnv;export const waitUntil=globalThis.__noticesWait;':'export const headers=async()=>globalThis.__noticesHeaders;',loader:'js'}));}}]});
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
let iosID=crypto.randomUUID(),webID=crypto.randomUUID(),subscription,webReceiver;
test('dispositivos se asocian al usuario autenticado; suscripciones inválidas y destinos ajenos se rechazan',async()=>{
 const ecdh=createECDH('prime256v1');ecdh.generateKeys();webReceiver=ecdh;subscription={endpoint:'https://fcm.googleapis.com/fcm/send/simulated-device',keys:{p256dh:ecdh.getPublicKey().toString('base64url'),auth:Buffer.alloc(16,4).toString('base64url')}};
 assert.equal((await api(luisaToken,{action:'register',id:iosID,platform:'ios',token:'ab'.repeat(32),environment:'sandbox'})).status,200);
 assert.equal((await api(paulaToken,{action:'register',id:webID,platform:'web',subscription})).status,200);
 assert.equal((await api(luisaToken,{action:'register',id:crypto.randomUUID(),platform:'web',subscription:{...subscription,endpoint:'http://127.0.0.1/private'}})).status,400);
 assert.equal((await api(luisaToken,{action:'register',id:crypto.randomUUID(),platform:'ios',token:'bad',environment:'sandbox'})).status,400);
 assert.ok(!sql.prepare('SELECT data FROM jac_push_devices WHERE id=?').get(iosID).data.includes('ab'.repeat(32)));
});
let manual;
test('alerta llega solo a seleccionados; reintentos conservan un registro y no duplican push',async()=>{
 manual=alert();calls=[];const r=await api(ownerToken,{action:'alert',alert:manual});assert.equal(r.status,200);const pushes=calls.filter(x=>x.url.hostname.includes('push.apple.com'));assert.equal(pushes.length,1);assert.ok(pushes[0].url.hostname.startsWith('api.sandbox.'));assert.equal(pushes[0].options.redirect,'manual');assert.equal(pushes[0].options.headers['apns-topic'],m.APP_TOPIC);assert.equal(JSON.parse(pushes[0].options.body).noticeId,manual.id);assert.deepEqual(JSON.parse(pushes[0].options.body).aps.alert,{title:manual.title,body:manual.body});
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
 const delivered=sql.prepare('SELECT COUNT(*) n FROM jac_push_deliveries WHERE notice_id=? AND status=?').get(imported.id,'sent').n;assert.equal(delivered,2);assert.deepEqual(JSON.parse(calls.find(x=>x.url.hostname==='api.sandbox.push.apple.com').options.body).aps.alert,{title:'JAC',body:'Ya llegó tu itinerario para el día de hoy'});
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


test('eliminar alertas exige propietario, confirmación, origen y sesión vigente; conserva itinerarios',async()=>{
 const input=alert([paula]);const actor=await m.authenticatedSession(ownerToken);await m.saveManualNotice(actor,input,async()=>true);
 const remove={action:'deleteAlert',id:input.id,confirmation:input.id};
 assert.equal((await api('',remove)).status,401);assert.equal((await api(paulaToken,remove)).status,403);
 assert.equal((await api(ownerToken,{...remove,confirmation:crypto.randomUUID()})).status,400);
 assert.equal((await api(ownerToken,{...remove,id:'bad',confirmation:'bad'})).status,400);
 globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+ownerToken});
 assert.equal((await m.api.POST(new Request(base+'/api/notices',{method:'POST',headers:{origin:'https://untrusted.example.invalid'},body:JSON.stringify(remove)}))).status,403);
 await assert.rejects(()=>m.deleteManualNotice(actor,input.id,input.id,async()=>false),e=>e.status===403);
 assert.equal((await api(ownerToken,{action:'deleteAlert',id:imported.id,confirmation:imported.id})).status,400);
 const unknown=crypto.randomUUID();assert.equal((await api(ownerToken,{action:'deleteAlert',id:unknown,confirmation:unknown})).status,404);
 assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(input.id));assert.ok(bucket.has(imported.file_key));
 await m.deleteManualNotice(actor,input.id,input.id,async()=>true);
});
test('borrado atómico retira contenido, destinatarios y push; reintentos no restauran ni reenvían',async()=>{
 calls=[];const actor=await m.authenticatedSession(ownerToken),input=alert([paula]);await m.saveManualNotice(actor,input,async()=>true);
 const keep=alert([paula]);await m.saveManualNotice(actor,keep,async()=>true);
 assert.ok(sql.prepare('SELECT id FROM jac_push_deliveries WHERE notice_id=?').get(input.id));
 const remove={action:'deleteAlert',id:input.id,confirmation:input.id};assert.equal((await api(ownerToken,remove)).status,200);assert.equal((await api(ownerToken,remove)).status,200);
 for(const table of ['jac_notices','jac_notice_recipients','jac_push_deliveries'])assert.equal(sql.prepare('SELECT count(*) n FROM '+table+' WHERE '+(table==='jac_notices'?'id':'notice_id')+'=?').get(input.id).n,0);
 assert.deepEqual(Object.keys(sql.prepare('SELECT * FROM jac_deleted_alerts WHERE id=?').get(input.id)).sort(),['deleted_at','id']);
 assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(keep.id));assert.ok(sql.prepare('SELECT id FROM jac_push_deliveries WHERE notice_id=?').get(keep.id));
 assert.equal((await api(ownerToken,{action:'alert',alert:input})).status,410);assert.equal((await api(ownerToken,{action:'alert',alert:{...input,title:'Reintento cambiado'}})).status,410);
 await m.deleteManualNotice(actor,keep.id,keep.id,async()=>true);await m.dispatchPush();assert.equal(calls.length,0);
 assert.equal((await api(ownerToken,undefined,'?item='+input.id)).status,404);assert.equal((await api(paulaToken,undefined,'?item='+input.id)).status,404);
 assert.ok(!(await api(paulaToken)).body.notices.some(x=>x.id===input.id));assert.ok(!(await api(ownerToken)).body.notices.some(x=>x.id===input.id));
});
test('un fallo en el lote revierte el borrado completo y conserva la alerta',async()=>{
 const actor=await m.authenticatedSession(ownerToken),input=alert([paula]);await m.saveManualNotice(actor,input,async()=>true);
 sql.exec("CREATE TRIGGER fixture_delete_failure BEFORE DELETE ON jac_notice_recipients WHEN OLD.notice_id='"+input.id+"' BEGIN SELECT RAISE(ABORT,'simulated failure'); END;");
 try{assert.equal((await api(ownerToken,{action:'deleteAlert',id:input.id,confirmation:input.id})).status,502);
 assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(input.id));assert.ok(sql.prepare('SELECT id FROM jac_push_deliveries WHERE notice_id=?').get(input.id));assert.ok(sql.prepare('SELECT id FROM jac_notice_recipients WHERE notice_id=?').get(input.id));assert.equal(sql.prepare('SELECT id FROM jac_deleted_alerts WHERE id=?').get(input.id),undefined);
 }finally{sql.exec('DROP TRIGGER fixture_delete_failure');}
 await m.deleteManualNotice(actor,input.id,input.id,async()=>true);
});
test('borrar durante el cifrado cancela el envío ya seleccionado; no resucita una creación concurrente',async()=>{
 const actor=await m.authenticatedSession(ownerToken),input=alert([paula]);await m.saveManualNotice(actor,input,async()=>true);calls=[];let checks=0;
 beforeFirst=async query=>{if(query.text.includes("p.status='sending'")&&query.args[0]===input.id&&++checks===2)await m.deleteManualNotice(actor,input.id,input.id,async()=>true);};
 try{await m.dispatchPush();}finally{beforeFirst=undefined;}
 assert.equal(checks,2);assert.equal(calls.length,0);assert.equal(sql.prepare('SELECT id FROM jac_push_deliveries WHERE notice_id=?').get(input.id),undefined);
 const racing=alert([paula]);await assert.rejects(()=>m.saveManualNotice(actor,racing,async()=>{sql.prepare('INSERT INTO jac_deleted_alerts (id,deleted_at) VALUES (?,?)').run(racing.id,new Date().toISOString());return true;}),e=>e.status===410);
 assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(racing.id),undefined);assert.equal(sql.prepare('SELECT id FROM jac_notice_recipients WHERE notice_id=?').get(racing.id),undefined);
});

function decodeRegisteredWeb(call){
 const bytes=Buffer.from(call.options.body),salt=bytes.subarray(0,16),sender=bytes.subarray(21,21+bytes[20]),cipher=bytes.subarray(21+bytes[20]);
 const ikm=Buffer.from(hkdfSync('sha256',webReceiver.computeSecret(sender),Buffer.from(subscription.keys.auth,'base64url'),Buffer.concat([Buffer.from('WebPush: info\0'),webReceiver.getPublicKey(),sender]),32));
 const decipher=createDecipheriv('aes-128-gcm',Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: aes128gcm\0'),16)),Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: nonce\0'),12)));
 decipher.setAuthTag(cipher.subarray(-16));const clear=Buffer.concat([decipher.update(cipher.subarray(0,-16)),decipher.final()]);return JSON.parse(clear.subarray(0,-1));
}
test('envío web cifra el título y mensaje de la alerta solo para sus destinatarios',async()=>{
 calls=[];const input={...alert([paula]),title:'Cambio de hora',body:'Llegar a las 8:00. Información ficticia.'};await api(ownerToken,{action:'alert',alert:input});
 const push=calls.find(x=>x.url.hostname==='fcm.googleapis.com');assert.ok(push);assert.deepEqual(decodeRegisteredWeb(push),{id:input.id,title:input.title,body:input.body});
 assert.equal(calls.filter(x=>x.url.hostname.includes('push.apple.com')).length,0);
});
test('mensajes Unicode largos caben en push sin modificar el contenido guardado',async()=>{
 const body='🎵'.repeat(1000),content=m.noticePushContent({kind:'alert',title:'Aviso largo',body});assert.ok(Buffer.byteLength(JSON.stringify(content))<=2800);assert.ok(content.body.endsWith('…'));assert.ok(!content.body.includes('\ufffd'));
 const short={kind:'alert',title:'Información',body:'Texto completo con tildes y emojis 🎵'};assert.deepEqual(m.noticePushContent(short),{title:short.title,body:short.body});
 calls=[];const input={...alert([paula]),body};await api(ownerToken,{action:'alert',alert:input});assert.equal(sql.prepare('SELECT body FROM jac_notices WHERE id=?').get(input.id).body,body);const delivered=decodeRegisteredWeb(calls.find(x=>x.url.hostname==='fcm.googleapis.com'));assert.equal(delivered.title,input.title);assert.ok(delivered.body.endsWith('…'));assert.ok(body.startsWith(delivered.body.slice(0,-1)));assert.ok(Buffer.byteLength(JSON.stringify(delivered))<3000);
});
async function fixtureItinerary(file='FDELETEPDF01'){
 await slack(event(file));return sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:'+file);
}
test('borrado de itinerario exige propietario, confirmación, origen y sesión vigente',async()=>{
 const item=await fixtureItinerary(),remove={action:'deleteItinerary',id:item.id,confirmation:item.id},actor=await m.authenticatedSession(ownerToken);
 assert.equal((await api('',remove)).status,401);assert.equal((await api(paulaToken,remove)).status,403);assert.equal((await api(ownerToken,{...remove,confirmation:'bad'})).status,400);
 await assert.rejects(()=>m.deleteItinerary(actor,item.id,item.id,async()=>false),e=>e.status===403);
 globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+ownerToken});assert.equal((await m.api.POST(new Request(base+'/api/notices',{method:'POST',headers:{origin:'https://untrusted.example.invalid'},body:JSON.stringify(remove)}))).status,403);
 assert.equal((await api(ownerToken,{action:'deleteItinerary',id:manual.id,confirmation:manual.id})).status,400);
 const unknown=crypto.randomUUID();assert.equal((await api(ownerToken,{...remove,id:unknown,confirmation:unknown})).status,404);
 assert.ok(bucket.has(item.file_key));assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(item.id));
});
test('borrar retira PDF, acceso, destinatarios y entregas, sin restaurar por replay de Slack',async()=>{
 const item=sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:FDELETEPDF01'),remove={action:'deleteItinerary',id:item.id,confirmation:item.id};
 calls=[];assert.equal((await api(ownerToken,remove)).status,200);assert.equal((await api(ownerToken,remove)).status,200);
 assert.equal(bucket.has(item.file_key),false);for(const table of ['jac_notices','jac_notice_recipients','jac_push_deliveries'])assert.equal(sql.prepare('SELECT count(*) n FROM '+table+' WHERE '+(table==='jac_notices'?'id':'notice_id')+'=?').get(item.id).n,0);
 assert.equal((await api(paulaToken,undefined,'?item='+item.id)).status,404);globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+paulaToken});assert.equal((await m.pdf.GET(new Request(base+'/api/notices/pdf?id='+item.id))).status,404);
 sql.prepare("UPDATE jac_slack_files SET status='ignored' WHERE status='failed'").run();const before=writes;await slack(event('FDELETEPDF01'));sql.prepare("UPDATE jac_slack_files SET status='pending' WHERE id='FDELETEPDF01'").run();await m.importSlackFiles();await m.retryImports();await m.importSlackFiles();
 assert.equal(writes,before);assert.equal(calls.length,0);assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE source=?').get(item.source),undefined);assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get('FDELETEPDF01').status,'deleted');
 assert.ok(bucket.has(imported.file_key));assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(manual.id));
});
test('fallo D1 revierte el borrado y fallo R2 mantiene el PDF inaccesible hasta reintentar limpieza',async()=>{
 const item=await fixtureItinerary('FDELETEPDF02'),remove={action:'deleteItinerary',id:item.id,confirmation:item.id};
 sql.exec("CREATE TRIGGER fixture_itinerary_rollback BEFORE DELETE ON jac_notice_recipients WHEN OLD.notice_id='"+item.id+"' BEGIN SELECT RAISE(ABORT,'fixture rollback'); END;");
 try{assert.equal((await api(ownerToken,remove)).status,502);assert.ok(bucket.has(item.file_key));assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(item.id));assert.equal(sql.prepare('SELECT id FROM jac_deleted_itineraries WHERE id=?').get(item.id),undefined);}finally{sql.exec('DROP TRIGGER fixture_itinerary_rollback');}
 beforeDelete=async()=>{throw new Error('simulated R2 outage');};try{assert.equal((await api(ownerToken,remove)).status,200);assert.ok(bucket.has(item.file_key));assert.equal(sql.prepare('SELECT file_deleted FROM jac_deleted_itineraries WHERE id=?').get(item.id).file_deleted,0);assert.equal((await api(paulaToken,undefined,'?item='+item.id)).status,404);}finally{beforeDelete=undefined;}
 await m.purgeDeletedItineraries();assert.equal(bucket.has(item.file_key),false);assert.equal(sql.prepare('SELECT file_deleted FROM jac_deleted_itineraries WHERE id=?').get(item.id).file_deleted,1);
});
test('una importación concurrente no restaura el itinerario borrado ni su PDF',async()=>{
 const item=await fixtureItinerary('FDELETEPDF03'),actor=await m.authenticatedSession(ownerToken);let deleted=false;
 // Simulate an older import lease that saw no notice before the first importer saved it.
 beforeFirst=async q=>{if(!deleted&&q.text==='SELECT id FROM jac_notices WHERE source=?'&&q.args[0]===item.source){deleted=true;await m.deleteItinerary(actor,item.id,item.id,async()=>true);}};
 sql.prepare("UPDATE jac_slack_files SET status='pending' WHERE id='FDELETEPDF03'").run();calls=[];
 try{await m.importSlackFiles();}finally{beforeFirst=undefined;}
 assert.equal(deleted,true);assert.equal(bucket.has(item.file_key),false);assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE source=?').get(item.source),undefined);assert.equal(calls.filter(x=>x.options.method==='POST').length,0);
});
test('borrar un itinerario durante el cifrado cancela su entrega pendiente',async()=>{
 const item=await fixtureItinerary('FDELETEPDF04'),actor=await m.authenticatedSession(ownerToken);sql.prepare("UPDATE jac_push_deliveries SET status='pending' WHERE notice_id=?").run(item.id);calls=[];let checks=0;
 beforeFirst=async q=>{if(q.text.includes("p.status='sending'")&&q.args[0]===item.id&&++checks===2)await m.deleteItinerary(actor,item.id,item.id,async()=>true);};
 try{await m.dispatchPush();}finally{beforeFirst=undefined;}
 assert.equal(checks,2);assert.equal(calls.length,0);assert.equal(bucket.has(item.file_key),false);
});

test('una limpieza antigua no marca como retirado un PDF recién subido por una importación tardía',async()=>{
 const item=await fixtureItinerary('FDELETEPDF05'),actor=await m.authenticatedSession(ownerToken);await m.deleteItinerary(actor,item.id,item.id,async()=>true);
 sql.prepare('UPDATE jac_deleted_itineraries SET file_deleted=0 WHERE id=?').run(item.id);bucket.set(item.file_key,pdfBytes);
 beforeDelete=async()=>async()=>{bucket.set(item.file_key,pdfBytes);sql.prepare('UPDATE jac_deleted_itineraries SET file_deleted=0,cleanup_version=cleanup_version+1 WHERE id=?').run(item.id);};
 try{await m.purgeDeletedItineraries(item.id);}finally{beforeDelete=undefined;}
 assert.ok(bucket.has(item.file_key));assert.equal(sql.prepare('SELECT file_deleted FROM jac_deleted_itineraries WHERE id=?').get(item.id).file_deleted,0);
 await m.purgeDeletedItineraries(item.id);assert.equal(bucket.has(item.file_key),false);
});

async function manualAPI(token,payload,{origin=base}={}){
 const cookie=token?'__Host-jac_session='+token:'';globalThis.__noticesHeaders=new Headers({cookie,host:'notices.example.invalid'});
 const r=await m.publish.POST(new Request(base+'/api/notices/publish',{method:'POST',headers:{cookie,origin,'Content-Type':'application/json'},body:JSON.stringify(payload)}));return {status:r.status,body:await r.json()};
}
const manualInput=(kind='alert',files=[])=>({id:crypto.randomUUID(),kind,title:'Contenido ficticio',body:'Adjuntos privados de prueba',recipients:kind==='alert'?[paula]:[],files});
const upload=(filename='Prueba.pdf',data=pdfBytes)=>({filename,data:Buffer.from(data).toString('base64')});
async function readAttachment(token,id,file){const cookie='__Host-jac_session='+token;globalThis.__noticesHeaders=new Headers({cookie,host:'notices.example.invalid'});return m.attachment.GET(new Request(base+'/api/notices/file?id='+id+'&file='+file,{headers:{cookie}}));}
test('Publicación manual: origen/sesión, destinatarios y archivos privados para ambas secciones',async()=>{
 luisaToken=await m.makeSession(luisa);const actor=await m.authenticatedSession(ownerToken),p=manualInput('alert',[upload(),upload('Foto.png',Uint8Array.from([137,80,78,71,13,10,26,10,0]))]);
 assert.equal((await manualAPI('',p)).status,401);assert.equal((await manualAPI(paulaToken,p)).status,403);assert.equal((await manualAPI(ownerToken,p,{origin:'https://untrusted.example.invalid'})).status,403);
 assert.equal((await manualAPI(ownerToken,p)).status,200);assert.equal((await manualAPI(ownerToken,p)).status,200);
 const item=await m.noticeItem(actor,p.id);assert.equal(item.attachments.length,2);assert.equal(sql.prepare('SELECT count(*) n FROM jac_notice_attachments WHERE notice_id=? AND state=?').get(p.id,'ready').n,2);
 assert.equal((await readAttachment(luisaToken,p.id,item.attachments[0].id)).status,404);
 for(const file of item.attachments){const response=await readAttachment(paulaToken,p.id,file.id);assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),file.mimeType);assert.equal(response.headers.get('x-content-type-options'),'nosniff');assert.ok(response.headers.get('cache-control').includes('no-store'));}
 assert.equal((await manualAPI(ownerToken,{...p,title:'Otro contenido'})).status,409);
 const itinerary=manualInput('itinerary',[upload()]);assert.equal((await manualAPI(ownerToken,itinerary)).status,200);const shared=await m.noticeItem(await m.authenticatedSession(luisaToken),itinerary.id);assert.equal(shared.kind,'itinerary');assert.equal(shared.attachments.length,1);
 await m.deleteManualNotice(actor,p.id,p.id,async()=>true);assert.equal((await readAttachment(paulaToken,p.id,item.attachments[0].id)).status,404);assert.equal((await manualAPI(ownerToken,p)).status,410);
 await m.deleteItinerary(actor,itinerary.id,itinerary.id,async()=>true);assert.equal((await manualAPI(ownerToken,itinerary)).status,410);
});
test('Valida firmas de archivo, cantidad, tamaño y no publica archivos rechazados',async()=>{
 const before=bucket.size;for(const files of [[upload('script.pdf',new TextEncoder().encode('<script>fake</script>'))],Array.from({length:6},()=>upload()),[upload('big.pdf',Buffer.concat([Buffer.from('%PDF-'),Buffer.alloc(10*1024*1024)]))],[{filename:'bad.pdf',data:'a==='}]]){
  const p=manualInput('alert',files),r=await manualAPI(ownerToken,p);assert.ok([400,413].includes(r.status),JSON.stringify(r));assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(p.id),undefined);
 }assert.equal(bucket.size,before);
});
test('Reintentos simultáneos conservan un único juego de adjuntos y no añaden destinatarios',async()=>{
 const actor=await m.authenticatedSession(ownerToken),p=manualInput('alert',[upload()]);await Promise.all([m.publishManualNotice(actor,p,async()=>true),m.publishManualNotice(actor,p,async()=>true)]);
 const ready=sql.prepare("SELECT * FROM jac_notice_attachments WHERE notice_id=? AND state='ready'").all(p.id);assert.equal(ready.length,1);assert.equal(bucket.has(ready[0].file_key),true);
 const deleted=sql.prepare("SELECT * FROM jac_notice_attachments WHERE state='deleted' AND cleaned=0").all();assert.equal(deleted.length,0);
 const recipients=sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=?').all(p.id).map(x=>x.user_id);assert.deepEqual(recipients,[paula]);await m.deleteManualNotice(actor,p.id,p.id,async()=>true);
});
test('Cambio de sesión durante R2 no publica; un fallo parcial conserva limpieza pendiente',async()=>{
 const actor=await m.authenticatedSession(ownerToken),p=manualInput('alert',[upload()]);let valid=true;beforePut=async()=>{valid=false;};
 try{await assert.rejects(()=>m.publishManualNotice(actor,p,async()=>valid),e=>e.status===403);}finally{beforePut=undefined;}
 assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(p.id),undefined);
 let count=0;const failing=manualInput('alert',[upload(),upload('Otro.pdf')]);beforePut=async()=>{if(++count===2)throw Error('fixture R2 failure');};beforeDelete=async()=>{throw Error('fixture cleanup failure');};
 try{await assert.rejects(()=>m.publishManualNotice(actor,failing,async()=>true));}finally{beforePut=undefined;beforeDelete=undefined;}
 assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(failing.id),undefined);assert.ok(sql.prepare("SELECT id FROM jac_notice_attachments WHERE state='deleted' AND cleaned=0").get());await m.purgeNoticeAttachments();assert.equal(sql.prepare("SELECT id FROM jac_notice_attachments WHERE state='deleted' AND cleaned=0").get(),undefined);
});
test('Un borrado mientras se sube el adjunto bloquea la publicación y limpia la copia tardía',async()=>{
 const actor=await m.authenticatedSession(ownerToken),p=manualInput('itinerary',[upload()]);beforePut=async()=>{sql.prepare('INSERT INTO jac_deleted_itineraries(id,source,deleted_at) VALUES (?,?,?)').run(p.id,'manual:'+p.id,new Date().toISOString());};
 try{await assert.rejects(()=>m.publishManualNotice(actor,p,async()=>true),e=>e.status===410);}finally{beforePut=undefined;}
 assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(p.id),undefined);assert.equal(sql.prepare("SELECT id FROM jac_notice_attachments WHERE state='deleted' AND cleaned=0").get(),undefined);
});
