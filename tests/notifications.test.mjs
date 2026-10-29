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
 async run(){return this.execute();}async all(){const result=this.execute();if(afterAll)await afterAll(this,result);return result;}async first(){if(beforeFirst)await beforeFirst(this);return sql.prepare(this.text).get(...this.args)||null;}
}
const bucket=new Map();let writes=0,scheduled=0,waiting=[],beforeFirst,beforePut,beforeDelete,beforeGet,afterAll;
globalThis.__noticesEnv={DB:{prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const out=qs.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},BUCKET:{put:async(k,v)=>{if(beforePut)await beforePut(k);if(bucket.has(k))return null;bucket.set(k,new Uint8Array(v));writes++;return {key:k};},delete:async k=>{const after=await beforeDelete?.(k);bucket.delete(k);if(after)await after();},get:async k=>{if(beforeGet)await beforeGet(k);return bucket.has(k)?{body:new Response(bucket.get(k)).body}:null;}},PAYROLL_AUTH_KEY:'notices-independent-authentication-key-tests-only',PAYROLL_MAIL_KEY:Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url')};
globalThis.__noticesHeaders=new Headers();globalThis.__noticesWait=p=>{scheduled++;waiting.push(p);};
const bundle=await build({stdin:{contents:"export * as api from './app/api/notices/route';export * as recipientApi from './app/api/notices/recipients/route';export * as slack from './app/api/notices/slack/route';export * as pdf from './app/api/notices/pdf/route';export * as publish from './app/api/notices/publish/route';export * as attachment from './app/api/notices/file/route';export * as expensesApi from './app/api/expenses/route';export * as expenseFilesApi from './app/api/expenses/file/route';export * from './lib/travel-expenses';export * from './lib/payroll-store';export * as auth from './app/api/auth/route';export * from './lib/notifications';export * from './lib/notifications-core';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'test'}));b.onLoad({filter:/.*/,namespace:'test'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__noticesEnv;export const waitUntil=globalThis.__noticesWait;':'export const headers=async()=>globalThis.__noticesHeaders;',loader:'js'}));}}]});
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
async function slack(body,{timestamp=String(Math.floor(Date.now()/1000)),bad=false,drain=true}={}){const raw=JSON.stringify(body),signature='v0='+createHmac('sha256',slackSecret).update('v0:'+timestamp+':'+raw).digest('hex');const r=await m.slack.POST(new Request(base+'/api/notices/slack',{method:'POST',headers:{'x-slack-request-timestamp':timestamp,'x-slack-signature':bad?'v0='+('0'.repeat(64)):signature},body:raw}));if(drain)await settle();return r;}
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

// Boarding passes add a stricter boundary than the shared itinerary/admin feed.
test('Pases: fecha civil Colombia, nombres españoles, cambio de año y fechas ambiguas',async()=>{
 const out=await build({stdin:{contents:"export * from './lib/boarding-passes'",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});const b=await import('data:text/javascript;base64,'+Buffer.from(out.outputFiles[0].text).toString('base64'));
 assert.equal(b.boardingToday(new Date('2026-10-08T04:59:59Z')),'2026-10-07');assert.equal(b.boardingToday(new Date('2026-10-08T05:00:00Z')),'2026-10-08');
 assert.equal(b.boardingFilenameDate('Camilo 10 de octubre.pdf',new Date('2026-10-07T15:00:00Z')),'2026-10-10');assert.equal(b.boardingFilenameDate('Jhon Alex 2 de enero.pdf',new Date('2026-12-31T15:00:00Z')),'2027-01-02');assert.equal(b.boardingFilenameDate('Alex 31 de diciembre.pdf',new Date('2027-01-01T15:00:00Z')),'2026-12-31');
 assert.equal(b.boardingFilenameDate('Alex 29 de febrero 2028.png'),'2028-02-29');for(const name of ['Pase.pdf','Camilo 31 de abril 2026.pdf','1 de octubre y 2 de octubre.pdf','Alex 29 de febrero 2026.pdf'])assert.equal(b.boardingFilenameDate(name),null);
});
const boardJhon='77777777-7777-4777-8777-777777777777',boardAlex='88888888-8888-4888-8888-888888888888';
const actor=id=>({id,email:id===owner?'camilo@mac2you.co':id===boardJhon?'jhonalexcastano@gmail.com':'alexzuluagaazp@gmail.com',isOwner:id===owner,permissions:[]});
const boardChannels=[{id:'C0C7QKT2FJQ',userId:owner,version:0},{id:'C0C8FAPHTCG',userId:boardJhon,version:0},{id:'C0C7K0QCMKQ',userId:boardAlex,version:0}];
let privatePass;
test('Pases manuales: un dueño, adjuntos obligatorios, permiso privado incluso frente a Camilo',async()=>{
 for(const [id,email,name] of [[boardJhon,'jhonalexcastano@gmail.com','Jhon ficticio'],[boardAlex,'alexzuluagaazp@gmail.com','Alex ficticio']])sql.prepare('INSERT INTO payroll_users(id,username,email,name,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?)').run(id,id,email,name,'[]','fixture','fixture');
 const input={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase privado',body:'',recipients:[boardJhon],files:[{filename:'Jhon 10 de octubre 2026.pdf',data:Buffer.from(pdfBytes).toString('base64')}]};privatePass=input;
 const run=b=>m.publishManualNotice(actor(owner),b,async()=>true);
 for(const bad of [{...input,recipients:[owner,boardJhon]},{...input,files:[]},{...input,travelDate:'2026-10-11'},{...input,files:[{...input.files[0],filename:'31 de abril 2026.pdf'}]}])await assert.rejects(()=>run(bad));
 assert.equal(await run(input),input.id);assert.equal(await run(input),input.id);await assert.rejects(()=>run({...input,body:'Cambio'}),e=>e.status===409);
 const item=await m.noticeItem(actor(boardJhon),input.id);assert.equal(item.travelDate,'2026-10-10');assert.equal(item.attachments.length,1);
 for(const user of [owner,boardAlex,luisa]){await assert.rejects(()=>m.noticeItem(actor(user),input.id),e=>e.status===404);await assert.rejects(()=>m.markNoticeRead(actor(user),input.id),e=>e.status===404);await assert.rejects(()=>m.noticeAttachment(actor(user),input.id,item.attachments[0].id),e=>e.status===404);assert.ok(!(await m.noticeFeed(actor(user))).notices.some(n=>n.id===input.id));}
 assert.ok(await m.noticeAttachment(actor(boardJhon),input.id,item.attachments[0].id));
 const pending=sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=?').all(input.id);assert.deepEqual(pending.map(x=>x.user_id),[boardJhon]);
});
test('Pases: fechas ordenadas, historial separado y paginación independiente de las alertas',async()=>{
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Bogota',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const create=async(date,i)=>{const id=crypto.randomUUID();await m.publishManualNotice(actor(owner),{id,kind:'boarding_pass',travelDate:date,title:'Pase '+i,body:'',recipients:[owner],files:[{filename:'Foto.png',data:Buffer.from([137,80,78,71,13,10,26,10,0]).toString('base64')}]},async()=>true);return id;};
 const prior=await create('2020-01-01','pasado'),current=await create(today,'hoy');for(let i=0;i<43;i++)await create('2090-01-01',i);
 const first=await m.boardingFeed(actor(owner));assert.equal(first.today,today);assert.equal(first.notices[0].id,current);assert.equal(first.notices.length,40);assert.ok(first.nextCursor);assert.ok(first.notices.every(n=>n.id!==prior));
 const second=await m.boardingFeed(actor(owner),false,first.nextCursor);assert.equal(second.notices.length,4);assert.ok(second.notices.every(n=>!first.notices.some(o=>o.id===n.id)));
 const history=await m.boardingFeed(actor(owner),true);assert.deepEqual(history.notices.map(n=>n.id),[prior]);assert.equal((await m.boardingFeed(actor(boardAlex))).notices.length,0);await assert.rejects(()=>m.boardingFeed(actor(owner),false,'bad'));
});
test('Pases Slack: mapeo CAS, canales exactos, destinatario inmutable, archivos válidos y reintentos sin duplicados',async()=>{
 hook=url=>url.pathname==='/api/conversations.info'?Response.json({ok:true,channel:{id:url.searchParams.get('channel'),is_member:true,is_archived:false}}):null;
 assert.equal((await api(luisaToken,{action:'boardingChannels',input:{channels:boardChannels}})).status,403);
 await assert.rejects(()=>m.configureBoardingChannels({channels:boardChannels.map((c,i)=>i===0?{...c,userId:boardJhon}:c)},async()=>true));
 await m.configureBoardingChannels({channels:boardChannels},async()=>true);assert.equal(sql.prepare('SELECT count(*) n FROM jac_boarding_channels').get().n,3);
 await assert.rejects(()=>m.configureBoardingChannels({channels:boardChannels},async()=>true),e=>e.status===409);assert.ok(sql.prepare('SELECT version FROM jac_boarding_channels').all().every(r=>r.version===1));
 fileMeta={...fileMeta,name:'Camilo 10 de octubre 2026.pdf',channels:['C0C8FAPHTCG']};const id='FBOARDTEST01';
 assert.equal((await slack(event(id,'C0C8FAPHTCG'))).status,200);const row=sql.prepare("SELECT * FROM jac_notices WHERE source=?").get('slack:'+id);assert.equal(row.kind,'boarding_pass');assert.equal(row.travel_date,'2026-10-10');assert.deepEqual(sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=?').all(row.id).map(x=>x.user_id),[boardJhon],'El nombre Camilo no puede redirigir un pase del canal de Jhon.');
 await slack(event(id,'C0C8FAPHTCG'));assert.equal(sql.prepare('SELECT count(*) n FROM jac_notices WHERE source=?').get('slack:'+id).n,1);
 await assert.rejects(()=>m.noticeItem(actor(owner),row.id),e=>e.status===404);
 const bad='FBOARDTEST02';fileMeta={...fileMeta,name:'Sin fecha.pdf'};await slack(event(bad,'C0C8FAPHTCG'));assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get(bad).status,'failed');assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:'+bad),undefined);
 const changed='FBOARDTEST03';fileMeta={...fileMeta,name:'Jhon 11 de octubre.pdf'};await m.queueSlackFiles([changed],'C0C8FAPHTCG');sql.prepare("UPDATE jac_boarding_channels SET version=version+1 WHERE id='C0C8FAPHTCG'").run();await m.importSlackFiles();assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get(changed).status,'failed');assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:'+changed),undefined);
 const alien='FBOARDTEST04';await m.queueSlackFiles([alien],'C_UNKNOWN');assert.equal(sql.prepare('SELECT id FROM jac_slack_files WHERE id=?').get(alien),undefined);hook=null;
});
test('Pases Slack: la descripción firmada queda guardada con su PDF antes de importar y no cambia con replays',async()=>{
 const prior=fileMeta,id='FBDMESSAGE01',channel='C0C8FAPHTCG';
 const text='Persona ficticia · AV9999 · Ruta de prueba\n*Silla:* 12A\nHora de salida: 6:45 PM (hora Colombia, UTC−5)\nHora en sala: 17:30 (hora Colombia, UTC−5)\nAerolínea: Avianca',body='Silla: 12A\nHora de salida: 18:45\nHora en sala: 17:30\nAerolínea: Avianca';
 const expected={seat:'12A',departureTime:'18:45',boardingTime:'17:30',airline:'Avianca'};
 let release;const held=new Promise(resolve=>{release=resolve;});
 fileMeta={...prior,name:'Jhon Alex 10 de octubre 2026 Bogota-Pereira.pdf',channels:[channel]};
 hook=async url=>{if(url.pathname==='/api/files.info'&&url.searchParams.get('file')===id){await held;return Response.json({ok:true,file:{...fileMeta,id}});}return null;};
 try{
  const message=event(id,channel);message.event.text=text;
  assert.equal((await slack(message,{drain:false})).status,200);
  assert.equal(sql.prepare('SELECT boarding_message FROM jac_slack_files WHERE id=?').get(id).boarding_message,body,'La cola debe conservar el texto antes de que termine files.info/descarga.');
  assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:'+id),undefined);
  const replay={...message,event:{...message.event,text:'Silla: 22C\nHora de salida: 21:10'}};
  assert.equal((await slack(replay,{drain:false})).status,200);
  assert.equal(sql.prepare('SELECT boarding_message FROM jac_slack_files WHERE id=?').get(id).boarding_message,body);
  release();await settle();
  const row=sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:'+id),item=await m.noticeItem(actor(boardJhon),row.id);
  assert.equal(row.body,body);assert.deepEqual(item.boardingDetails,expected);assert.equal(item.attachments.length,1);
  await assert.rejects(()=>m.noticeItem(actor(owner),row.id),e=>e.status===404);
  await assert.rejects(()=>m.noticeItem(actor(boardAlex),row.id),e=>e.status===404);
  assert.equal(JSON.stringify(m.noticePushContent(item)).includes('12A'),false,'El push conserva texto genérico sin datos privados del vuelo.');
  await slack({...replay,event:{...replay.event,subtype:'message_changed'}});
  await slack(replay);
  assert.equal(sql.prepare('SELECT count(*) n FROM jac_notices WHERE source=?').get('slack:'+id).n,1);
  assert.deepEqual((await m.noticeItem(actor(boardJhon),row.id)).boardingDetails,expected);
 }finally{release();await settle();hook=null;fileMeta=prior;}
});

test('Pases Slack: solo el texto del mismo mensaje con un archivo describe ese pase',async()=>{
 const prior=fileMeta,channel='C0C8FAPHTCG',text='Silla: 12A\nHora de salida: 18:45\nHora en sala: 17:30\nAerolínea: Avianca';
 fileMeta={...prior,name:'Jhon Alex 10 de octubre 2026 Bogota-Pereira.pdf',channels:[channel]};
 try{
  for(const [id,extra] of [['FBDMULTI001',{id:'FBDMULTI002',mimetype:'application/pdf'}],['FBDMULTI003',{id:'FBDTEXT0001',mimetype:'text/plain'}]]){
   const message=event(id,channel);message.event.text=text;message.event.files.push(extra);await slack(message);
   const row=sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:'+id);
   assert.equal(row.body,'');assert.equal(sql.prepare('SELECT boarding_message FROM jac_slack_files WHERE id=?').get(id).boarding_message,'');
   assert.equal((await m.noticeItem(actor(boardJhon),row.id)).boardingDetails,undefined);
  }
  const before=sql.prepare('SELECT count(*) n FROM jac_slack_files').get().n;
  await slack({type:'event_callback',team_id:m.ITINERARY_TEAM,event:{type:'message',channel,text,thread_ts:'1790000000.000001'}});
  assert.equal(sql.prepare('SELECT count(*) n FROM jac_slack_files').get().n,before,'Un comentario separado nunca se asocia al último pase del canal o hilo.');
  const ownReply=event('FBDREPLY001',channel);ownReply.event={...ownReply.event,text,thread_ts:'1790000000.000001'};await slack(ownReply);
  const reply=sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:FBDREPLY001');
  assert.equal((await m.noticeItem(actor(boardJhon),reply.id)).boardingDetails.seat,'12A','Un reply con su propio archivo y descripción es autosuficiente.');
  const wrong=event('FBDBADSIGN1',channel);wrong.event.text=text;assert.equal((await slack(wrong,{bad:true})).status,401);
  assert.equal(sql.prepare('SELECT id FROM jac_slack_files WHERE id=?').get('FBDBADSIGN1'),undefined);
  fileMeta={...fileMeta,name:'Itinerario_simulado.pdf',channels:[m.ITINERARY_CHANNEL]};
  const itinerary=event('FBDITIN0001');itinerary.event.text=text;await slack(itinerary);
  assert.equal(sql.prepare('SELECT body FROM jac_notices WHERE source=?').get('slack:FBDITIN0001').body,'');
  assert.equal(sql.prepare('SELECT boarding_message FROM jac_slack_files WHERE id=?').get('FBDITIN0001').boarding_message,'');
 }finally{fileMeta=prior;}
});

test('Pases: datos manuales y bloques inválidos preservan originales sin mezclar varios adjuntos',async()=>{
 const text='Silla: Sin asignar\nHora de salida: 00:30\nHora en sala: 23:20\nAerolínea: LATAM';
 const files=[{filename:'Jhon Alex 10 de octubre 2026 Bogota-Pereira.pdf',data:Buffer.from(pdfBytes).toString('base64')}];
 const single={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase ficticio descrito',body:text,recipients:[boardJhon],files};
 await m.publishManualNotice(actor(owner),single,async()=>true);
 assert.deepEqual((await m.noticeItem(actor(boardJhon),single.id)).boardingDetails,{seat:'',departureTime:'00:30',boardingTime:'23:20',airline:'LATAM'});
 const multiple={...single,id:crypto.randomUUID(),files:[...files,{...files[0],filename:'Jhon Alex 10 de octubre 2026 Pereira-Bogota.pdf'}]};
 await m.publishManualNotice(actor(owner),multiple,async()=>true);
 const multipleItem=await m.noticeItem(actor(boardJhon),multiple.id);assert.equal(multipleItem.attachments.length,2);assert.equal(multipleItem.boardingDetails,undefined);
 const prior=fileMeta,id='FBDINVALID1',channel='C0C8FAPHTCG';fileMeta={...prior,name:'Jhon Alex 10 de octubre 2026 Bogota-Pereira.pdf',channels:[channel]};
 try{
  const invalid=event(id,channel);invalid.event.text='Silla: 12A\nHora de salida: 18:45\nSilla: 22C';await slack(invalid);
  const row=sql.prepare('SELECT * FROM jac_notices WHERE source=?').get('slack:'+id),item=await m.noticeItem(actor(boardJhon),row.id);
  assert.equal(row.body,'');assert.equal(item.boardingDetails,undefined);assert.equal(item.attachments.length,1);assert.ok(await m.noticeAttachment(actor(boardJhon),row.id,item.attachments[0].id));
 }finally{fileMeta=prior;}
});

test('Pases: revocar destinatario durante subida impide guardar y limpia archivos tardíos',async()=>{
 const id=crypto.randomUUID();beforePut=async()=>{sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(boardAlex);};
 try{await assert.rejects(()=>m.publishManualNotice(actor(owner),{id,kind:'boarding_pass',title:'Privado',body:'',travelDate:'2026-10-10',recipients:[boardAlex],files:[{filename:'Foto.png',data:Buffer.from([137,80,78,71,13,10,26,10,0]).toString('base64')}]},async()=>true));assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(id),undefined);assert.equal(sql.prepare("SELECT id FROM jac_notice_attachments WHERE state='ready' AND notice_id=?").get(id),undefined);}finally{beforePut=null;sql.prepare('UPDATE payroll_users SET active=1 WHERE id=?').run(boardAlex);}
});

test('Pases: mañana tiene prioridad sin hoy, y el nombre distingue pasajero, origen y destino',async()=>{
 const out=await build({stdin:{contents:"export * from './lib/boarding-passes'",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});const b=await import('data:text/javascript;base64,'+Buffer.from(out.outputFiles[0].text).toString('base64'));
 assert.equal(b.boardingNextDay('2026-12-31'),'2027-01-01');assert.equal(b.boardingNextDay('2028-02-28'),'2028-02-29');
 assert.deepEqual(b.boardingPriorityDays('2026-10-07',false),['2026-10-08','2026-10-07']);assert.deepEqual(b.boardingPriorityDays('2026-10-07',true),['2026-10-07','2026-10-08']);
 assert.deepEqual(b.boardingFilenameDetails('Camilo 16 de octubre Pereira-Bogota.pdf'),{passenger:'Camilo',origin:'Pereira',destination:'Bogota'});
 assert.deepEqual(b.boardingFilenameDetails('Jhon Alex 16 de octubre de 2026 San Andrés – Bogotá.JPG'),{passenger:'Jhon Alex',origin:'San Andrés',destination:'Bogotá'});
 for(const name of ['Camilo 31 de abril Pereira-Bogota.pdf','Pase.pdf','Camilo 16 de octubre Pereira-Bogota-Medellin.pdf','Camilo 16 de octubre <script>-Bogota.pdf'])assert.equal(b.boardingFilenameDetails(name),null);
 assert.equal(b.boardingPassengerKey('Jhon Álex Castaño'),'jhon-alex');assert.equal(b.boardingPassengerKey('Alex Zuluaga'),'alex-zuluaga');assert.equal(b.boardingPassengerKey('Otra persona'),null);
});
test('Pases con ruta: pasajero debe corresponder al canal o destinatario, sin redirigir ni subir copias equivocadas',async()=>{
 const encode=filename=>({filename,data:Buffer.from(pdfBytes).toString('base64')}),input={id:crypto.randomUUID(),kind:'boarding_pass',title:'Ruta privada',body:'',recipients:[boardJhon],files:[encode('Camilo 16 de octubre 2026 Pereira-Bogota.pdf')]};
 const before=writes;await assert.rejects(()=>m.publishManualNotice(actor(owner),input,async()=>true),/pasajero/);assert.equal(writes,before);assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(input.id),undefined);
 await m.publishManualNotice(actor(owner),{...input,files:[encode('Jhon Alex 16 de octubre 2026 Pereira-Bogota.pdf')]},async()=>true);
 const item=await m.noticeItem(actor(boardJhon),input.id);assert.equal(item.travelDate,'2026-10-16');assert.ok(await m.noticeAttachment(actor(boardJhon),input.id,item.attachments[0].id));await assert.rejects(()=>m.noticeAttachment(actor(owner),input.id,item.attachments[0].id),e=>e.status===404);
 fileMeta={...fileMeta,name:'Camilo 16 de octubre 2026 Pereira-Bogota.pdf',channels:['C0C8FAPHTCG']};await m.queueSlackFiles(['FBOARDROUTEBAD'],'C0C8FAPHTCG');const beforeSlack=writes;await m.importSlackFiles();assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get('FBOARDROUTEBAD').status,'failed');assert.equal(writes,beforeSlack);assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:FBOARDROUTEBAD'),undefined);
 fileMeta={...fileMeta,name:'Jhon Alex 16 de octubre 2026 Pereira-Bogota.pdf'};await m.queueSlackFiles(['FBOARDROUTEGOOD'],'C0C8FAPHTCG');await m.importSlackFiles();const saved=sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:FBOARDROUTEGOOD');assert.ok(saved);assert.deepEqual(sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=?').all(saved.id).map(r=>r.user_id),[boardJhon]);
});

test('Borrado de pases: propietario, destinatario privado, confirmación, origen y sesión vigentes',async()=>{
 const input={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase ficticio para borrar',body:'',travelDate:'2026-10-16',recipients:[owner],files:[upload()]};
 await m.publishManualNotice(actor(owner),input,async()=>true);const remove={action:'deleteBoardingPass',id:input.id,confirmation:input.id};
 assert.equal((await api('',remove)).status,401);assert.equal((await api(luisaToken,remove)).status,403);assert.equal((await api(ownerToken,{...remove,confirmation:'bad'})).status,400);
 await assert.rejects(()=>m.deleteBoardingPass(actor(owner),input.id,input.id,async()=>false),e=>e.status===403);
 assert.equal((await api(ownerToken,{...remove,id:privatePass.id,confirmation:privatePass.id})).status,404);assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(privatePass.id));
 assert.equal((await api(ownerToken,{action:'deleteItinerary',id:input.id,confirmation:input.id})).status,400);
 globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+ownerToken});assert.equal((await m.api.POST(new Request(base+'/api/notices',{method:'POST',headers:{origin:'https://untrusted.example.invalid'},body:JSON.stringify(remove)}))).status,403);
 assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(input.id));
});
test('Borrar pase manual retira todos sus archivos y entregas, conserva otros pases y bloquea recreación',async()=>{
 const input={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase con dos adjuntos',body:'',travelDate:'2026-10-16',recipients:[owner],files:[upload('Uno.pdf'),upload('Dos.pdf')]};
 await m.publishManualNotice(actor(owner),input,async()=>true);const item=await m.noticeItem(actor(owner),input.id);assert.equal(item.attachments.length,2);const keys=sql.prepare('SELECT file_key FROM jac_notice_attachments WHERE notice_id=?').all(input.id).map(r=>r.file_key);
 const remove={action:'deleteBoardingPass',id:input.id,confirmation:input.id};calls=[];assert.equal((await api(ownerToken,remove)).status,200);assert.equal((await api(ownerToken,remove)).status,200);
 for(const table of ['jac_notices','jac_notice_recipients','jac_push_deliveries'])assert.equal(sql.prepare('SELECT count(*) n FROM '+table+' WHERE '+(table==='jac_notices'?'id':'notice_id')+'=?').get(input.id).n,0);
 for(const file of item.attachments)await assert.rejects(()=>m.noticeAttachment(actor(owner),item.id,file.id),e=>e.status===404);
 assert.ok(keys.every(k=>!bucket.has(k)));assert.ok(!(await m.boardingFeed(actor(owner))).notices.some(n=>n.id===item.id));await assert.rejects(()=>m.publishManualNotice(actor(owner),input,async()=>true),e=>e.status===410);
 assert.ok(await m.noticeItem(actor(boardJhon),privatePass.id));assert.equal(calls.length,0);
});
test('Borrado de pase revierte al fallar D1 y conserva limpieza pendiente si R2 falla',async()=>{
 const input={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase para fallos simulados',body:'',travelDate:'2020-01-01',recipients:[owner],files:[upload()]};await m.publishManualNotice(actor(owner),input,async()=>true);const item=await m.noticeItem(actor(owner),input.id),key=sql.prepare('SELECT file_key FROM jac_notice_attachments WHERE notice_id=?').get(input.id).file_key;
 sql.exec("CREATE TRIGGER fixture_board_delete_failure BEFORE DELETE ON jac_notice_recipients WHEN OLD.notice_id='"+input.id+"' BEGIN SELECT RAISE(ABORT,'simulated failure'); END;");
 try{assert.equal((await api(ownerToken,{action:'deleteBoardingPass',id:input.id,confirmation:input.id})).status,502);assert.ok(await m.noticeAttachment(actor(owner),input.id,item.attachments[0].id));assert.equal(sql.prepare('SELECT id FROM jac_deleted_itineraries WHERE id=?').get(input.id),undefined);}finally{sql.exec('DROP TRIGGER fixture_board_delete_failure');}
 beforeDelete=async k=>{if(k===key)throw Error('simulated R2 failure');};try{await m.deleteBoardingPass(actor(owner),input.id,input.id,async()=>true);assert.ok(bucket.has(key));await assert.rejects(()=>m.noticeAttachment(actor(owner),input.id,item.attachments[0].id),e=>e.status===404);assert.ok(!(await m.boardingFeed(actor(owner),true)).notices.some(n=>n.id===input.id));}finally{beforeDelete=undefined;}
 await m.purgeNoticeAttachments();assert.equal(bucket.has(key),false);
});
test('Pase Slack eliminado no revive por replay ni importación concurrente; limpia copias tardías',async()=>{
 const id='FBOARDDELETE36',channel='C0C7QKT2FJQ';fileMeta={...fileMeta,name:'Camilo 16 de octubre 2026 Pereira-Bogota.pdf',channels:[channel]};await m.queueSlackFiles([id],channel);await m.importSlackFiles();const item=sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:'+id);assert.ok(item);
 sql.prepare("UPDATE jac_slack_files SET status='pending' WHERE id=?").run(id);
 beforeFirst=async q=>{if(q.text.includes("WHERE source=? AND kind='boarding_pass'")&&q.args[0]==='slack:'+id){beforeFirst=undefined;await m.deleteBoardingPass(actor(owner),item.id,item.id,async()=>true);}};
 try{await m.importSlackFiles();}finally{beforeFirst=undefined;}
 assert.equal(sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:'+id),undefined);assert.equal(sql.prepare("SELECT id FROM jac_notice_attachments WHERE state='deleted' AND cleaned=0").get(),undefined);
 const before=writes;calls=[];await m.queueSlackFiles([id],channel);sql.prepare("UPDATE jac_slack_files SET status='pending' WHERE id=?").run(id);await m.importSlackFiles();assert.equal(writes,before);assert.equal(calls.length,0);assert.equal(sql.prepare('SELECT status FROM jac_slack_files WHERE id=?').get(id).status,'deleted');
});
test('El destinatario se revalida dentro de la transacción de borrado del pase',async()=>{
 const input={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase con destinatario revocado',body:'',travelDate:'2026-10-16',recipients:[owner],files:[upload()]};await m.publishManualNotice(actor(owner),input,async()=>true);
 await assert.rejects(()=>m.deleteBoardingPass(actor(owner),input.id,input.id,async()=>{sql.prepare('DELETE FROM jac_notice_recipients WHERE notice_id=?').run(input.id);return true;}),e=>e.status===404);
 assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(input.id));assert.equal(sql.prepare('SELECT id FROM jac_deleted_itineraries WHERE id=?').get(input.id),undefined);assert.equal(sql.prepare('SELECT state FROM jac_notice_attachments WHERE notice_id=?').get(input.id).state,'ready');
});


test('Alertas: Jhon y Alex pendientes aparecen; recepción privada y push solo tras activar acceso',async()=>{
 const jhon=crypto.randomUUID(),alex=crypto.randomUUID(),inactive=crypto.randomUUID();
 for(const [id,name,limited,active] of [[jhon,'Jhon pendiente',0,1],[alex,'Alex pendiente',1,1],[inactive,'Inactivo',0,0]])sql.prepare('INSERT INTO payroll_users(id,username,email,name,itineraries_only,active,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)').run(id,id,id+'@example.invalid',name,limited,active,'[]','fixture','fixture');
 const feed=await api(ownerToken);for(const id of [jhon,alex])assert.deepEqual(feed.body.users.find(u=>u.id===id),{id,name:id===jhon?'Jhon pendiente':'Alex pendiente',ready:false});assert.ok(!feed.body.users.some(u=>u.id===inactive));assert.deepEqual((await api(luisaToken)).body.users,[]);
 const legacy=alert([jhon]);assert.equal((await api(ownerToken,{action:'alert',alert:legacy})).status,200);
 const manual={id:crypto.randomUUID(),kind:'alert',title:'Alerta pendiente privada',body:'Solo destinatarios',recipients:[jhon,alex],files:[{filename:'Adjunto.pdf',data:Buffer.from(pdfBytes).toString('base64')}]};
 assert.equal(await m.publishManualNotice(actor(owner),manual,async()=>true),manual.id);assert.equal(sql.prepare('SELECT count(*) n FROM jac_push_deliveries WHERE notice_id=?').get(manual.id).n,0);
 await assert.rejects(()=>m.publishManualNotice(actor(owner),{...manual,id:crypto.randomUUID(),recipients:[inactive]},async()=>true),e=>e.status===409);
 for(const id of [jhon,alex])sql.prepare('UPDATE payroll_users SET password_hash=? WHERE id=?').run(m.hashPassword('fixture-password',globalThis.__noticesEnv.PAYROLL_AUTH_KEY),id);
 const allNotices=async token=>{let cursor='',items=[];do{const list=await api(token,undefined,cursor?'?cursor='+encodeURIComponent(cursor):'');assert.equal(list.status,200);assert.deepEqual(list.body.users,[]);items.push(...list.body.notices);cursor=list.body.nextCursor;}while(cursor);return items;};
 const jhonToken=await m.makeSession(jhon),alexToken=await m.makeSession(alex);for(const token of [jhonToken,alexToken])assert.ok((await allNotices(token)).some(n=>n.id===manual.id));
 assert.ok((await allNotices(jhonToken)).some(n=>n.id===legacy.id));assert.equal((await api(alexToken,undefined,'?item='+legacy.id)).status,404);
 const selected=await api(alexToken,undefined,'?item='+manual.id);assert.equal(selected.status,200);const file=selected.body.item.attachments[0];assert.ok(await m.noticeAttachment({...actor(alex),itinerariesOnly:true},manual.id,file.id));assert.equal((await api(paulaToken,undefined,'?item='+manual.id)).status,404);
 assert.equal((await api(alexToken,{action:'alert',alert:alert([alex])})).status,403);
 const device=crypto.randomUUID();assert.equal((await api(alexToken,{action:'register',id:device,platform:'ios',token:'ef'.repeat(32),environment:'sandbox'})).status,200);
 calls=[];const current=alert([alex]);assert.equal((await api(ownerToken,{action:'alert',alert:current})).status,200);assert.equal(calls.filter(c=>c.url.hostname==='api.sandbox.push.apple.com').length,1);
 sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(alex);assert.equal((await api(alexToken,undefined,'?item='+manual.id)).status,401);
 sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(jhon);
});


test('administrador delegado gestiona alertas sin acceso a pases privados ajenos',async()=>{
 const id=crypto.randomUUID(),now=new Date().toISOString();
 sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run(id,'delegate-notices','delegate-notices@example.invalid','Administrador ficticio',m.hashPassword('fixture',globalThis.__noticesEnv.PAYROLL_AUTH_KEY),JSON.stringify([m.ADMINISTRATOR_ROLE]),now,now);
 const token=await m.makeSession(id),delegate=await m.authenticatedSession(token);assert.equal(m.noticeOwner(delegate),true);
 const alertInput=alert([owner]);assert.equal((await api(token,{action:'alert',alert:alertInput})).status,200);
 assert.deepEqual(sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=?').all(alertInput.id).map(r=>r.user_id),[owner]);
 assert.equal((await api(token,{action:'deleteAlert',id:alertInput.id,confirmation:alertInput.id})).status,200);
 const pass={id:crypto.randomUUID(),kind:'boarding_pass',title:'Pase privado ficticio',body:'',travelDate:'2026-10-16',recipients:[owner],files:[upload()]};await m.publishManualNotice(actor(owner),pass,async()=>true);
 assert.equal((await api(token,undefined,'?item='+pass.id)).status,404);
 const file=sql.prepare('SELECT id FROM jac_notice_attachments WHERE notice_id=?').get(pass.id);
 await assert.rejects(()=>m.noticeAttachment(delegate,pass.id,file.id),e=>e.status===404);
 assert.equal((await api(token,{action:'deleteBoardingPass',id:pass.id,confirmation:pass.id})).status,404);
 assert.ok(sql.prepare('SELECT id FROM jac_notices WHERE id=?').get(pass.id));
 sql.prepare('UPDATE payroll_users SET permissions=? WHERE id=?').run('[]',id);
 assert.equal((await api(token,{action:'alert',alert:alert([owner])})).status,403);assert.equal((await api(token,{action:'configure',kind:'web',version:(await m.noticeConfig()).version})).status,403);
});

test('confirmación explícita es privada, idempotente y solo corresponde a la versión leída',async()=>{
 const admin=await m.authenticatedSession(ownerToken),reader=await m.authenticatedSession(luisaToken),other=await m.authenticatedSession(paulaToken),id=crypto.randomUUID();
 await m.saveManualNotice(admin,{id,title:'Recibido ficticio',body:'Confirmación explícita',recipients:[luisa]},async()=>true);
 await m.markNoticeRead(reader,id);assert.equal((await m.noticeItem(reader,id)).confirmed,false,'Abrir no confirma');
 await m.confirmNotice(reader,id,1,async()=>true);const first=sql.prepare('SELECT confirmed_at FROM jac_notice_recipients WHERE notice_id=? AND user_id=?').get(id,luisa).confirmed_at;
 await m.confirmNotice(reader,id,1,async()=>true);assert.equal(sql.prepare('SELECT confirmed_at FROM jac_notice_recipients WHERE notice_id=? AND user_id=?').get(id,luisa).confirmed_at,first);
 assert.equal((await m.noticeItem(reader,id)).confirmed,true);assert.equal((await m.noticeItem(reader,id)).receipts,undefined);assert.equal((await m.noticeItem(admin,id)).receipts.find(r=>r.userId===luisa).confirmed,true);
 await assert.rejects(()=>m.confirmNotice(other,id,1,async()=>true),e=>e.status===404);
 await assert.rejects(()=>m.confirmNotice(reader,id,2,async()=>true),e=>e.status===409);
 await assert.rejects(()=>m.confirmNotice(reader,id,1,async()=>false),e=>e.status===403);
});
test('actualizar itinerario conserva destinatarios, exige revisión, revoca adjuntos y confirma cada versión',async()=>{
 const admin=await m.authenticatedSession(ownerToken),reader=await m.authenticatedSession(luisaToken),id=crypto.randomUUID(),payload={id,kind:'itinerary',title:'Viaje ficticio',body:'Versión inicial',recipients:[],files:[{filename:'Inicial.pdf',data:Buffer.from(pdfBytes).toString('base64')}]};
 await m.publishManualNotice(admin,payload,async()=>true);await m.confirmNotice(reader,id,1,async()=>true);const old=(await m.noticeItem(reader,id)).attachments[0],recipients=sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=? ORDER BY user_id').all(id);
 const update={id,requestId:crypto.randomUUID(),revision:1,title:'Viaje ficticio corregido',body:'Información completa',summary:'Cambio de hora: salida a las 07:30',files:[{filename:'Actualizado.pdf',data:Buffer.from(pdfBytes).toString('base64')}]};
 await assert.rejects(()=>m.updateItinerary(reader,update,async()=>true),e=>e.status===403);
 await m.updateItinerary(admin,update,async()=>true);await m.updateItinerary(admin,update,async()=>true);
 const item=await m.noticeItem(reader,id);assert.equal(item.revision,2);assert.equal(item.confirmed,false);assert.equal(item.changeSummary,update.summary);assert.deepEqual(sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=? ORDER BY user_id').all(id),recipients);
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_itinerary_updates WHERE notice_id=?').get(id).n,1);await assert.rejects(()=>m.noticeAttachment(reader,id,old.id),e=>e.status===404);
 await assert.rejects(()=>m.confirmNotice(reader,id,1,async()=>true),e=>e.status===409);await m.confirmNotice(reader,id,2,async()=>true);assert.equal((await m.noticeItem(reader,id)).confirmed,true);
 await assert.rejects(()=>m.updateItinerary(admin,{...update,requestId:crypto.randomUUID()},async()=>true),e=>e.status===409);
 await assert.rejects(()=>m.updateItinerary(admin,{...update,summary:'Otro contenido'},async()=>true),e=>e.status===409);
 assert.deepEqual(m.noticePushContent(item),{title:'JAC · Itinerario actualizado',body:update.summary});
 const aborted={...update,requestId:crypto.randomUUID(),revision:2};let checks=0;await assert.rejects(()=>m.updateItinerary(admin,aborted,async()=>++checks===1),e=>e.status===403);assert.equal((await m.noticeItem(reader,id)).revision,2);
});
test('gastos con comprobantes son privados, reintentos estables y rechazos no cambian nómina',async()=>{
 const admin=await m.authenticatedSession(ownerToken),reader=await m.authenticatedSession(luisaToken),other=await m.authenticatedSession(paulaToken),id=crypto.randomUUID(),input={id,concept:'Taxi ficticio',amount:35000,expenseDate:'2026-10-08',note:'Prueba sin viaje real',files:[{filename:'Recibo.pdf',data:Buffer.from(pdfBytes).toString('base64')}]};
 await m.submitExpense(reader,input,async()=>true);await m.submitExpense(reader,input,async()=>true);assert.equal(sql.prepare('SELECT count(*) n FROM jac_travel_expenses WHERE id=?').get(id).n,1);
 assert.equal((await m.expenseFeed(other)).expenses.some(e=>e.id===id),false);assert.deepEqual((await m.expenseFeed(reader)).employees,[]);assert.deepEqual((await m.expenseFeed(reader)).periods,[]);
 const expense=(await m.expenseFeed(reader)).expenses.find(e=>e.id===id);await assert.rejects(()=>m.expenseAttachment(other,id,expense.attachments[0].id),e=>e.status===404);assert.ok((await m.expenseAttachment(reader,id,expense.attachments[0].id)).object);
 await assert.rejects(()=>m.noticeAttachment(admin,id,expense.attachments[0].id),e=>e.status===404);
 await assert.rejects(()=>m.submitExpense(reader,{...input,amount:40000},async()=>true),e=>e.status===409);
 await assert.rejects(()=>m.submitExpense(reader,{...input,id:crypto.randomUUID(),files:[]},async()=>true),e=>e.status===400);
 const review={id,version:1,decision:'reject',reason:'Comprobante incompleto',employeeId:'',periodId:''};await assert.rejects(()=>m.reviewExpense(reader,review,async()=>true),e=>e.status===403);
 const before=await m.readPayroll();await m.reviewExpense(admin,review,async()=>true);await m.reviewExpense(admin,review,async()=>true);assert.deepEqual(await m.readPayroll(),before);assert.equal((await m.allowedExpense(reader,id)).status,'rejected');
});
test('aprobar gasto incorpora un solo reintegro con CAS; no admite cierres ni carreras de revisión',async()=>{
 const admin=await m.authenticatedSession(ownerToken),reader=await m.authenticatedSession(luisaToken),current=await m.readPayroll(),employee=current.data.employees.find(e=>e.active&&!e.deleted),period={id:'travel-fixture-period',start:'2026-10-01',end:'2026-10-15',status:'abierta',shows:[],movements:[],routes:[],hours:[],excludedEmployees:[]};
 current.data.periods=[];current.data.periods.push(period);await m.writePayroll(current.data,current.version,owner);
 const create=async()=>{const id=crypto.randomUUID();await m.submitExpense(reader,{id,concept:'Hotel ficticio',amount:120000,expenseDate:'2026-10-08',note:'Solo prueba',files:[{filename:'Recibo.pdf',data:Buffer.from(pdfBytes).toString('base64')}]},async()=>true);return id;};
 const id=await create(),review={id,version:1,decision:'approve',reason:'Validado ficticio',employeeId:employee.id,periodId:period.id};
 await m.reviewExpense(admin,review,async()=>true);await m.reviewExpense(admin,review,async()=>true);const saved=await m.readPayroll(),movements=saved.data.periods[0].movements;assert.equal(movements.length,1);assert.equal(movements[0].id,id);assert.equal(movements[0].kind,'reintegro');assert.equal(movements[0].amount,120000);assert.equal((await m.allowedExpense(reader,id)).status,'approved');
 const id2=await create();saved.data.periods[0].status='cerrada';await m.writePayroll(saved.data,saved.version,owner);await assert.rejects(()=>m.reviewExpense(admin,{...review,id:id2},async()=>true),e=>e.status===400);
 const reopened=await m.readPayroll();reopened.data.periods[0].status='abierta';await m.writePayroll(reopened.data,reopened.version,owner);
 const before=await m.readPayroll();let checks=0;await assert.rejects(()=>m.reviewExpense(admin,{...review,id:id2},async()=>{if(++checks===2)sql.prepare("UPDATE jac_travel_expenses SET status='rejected',version=version+1 WHERE id=?").run(id2);return true;}),e=>e.status===409);assert.deepEqual(await m.readPayroll(),before,'Rechazo concurrente bloquea el reintegro completo');
});

test('API gastos exige sesión y origen, limita la revisión y entrega archivos privados sin caché',async()=>{
 const call=async(token,body,origin=base)=>{const cookie=token?'__Host-jac_session='+token:'';globalThis.__noticesHeaders=new Headers({cookie,host:'notices.example.invalid'});const r=await m.expensesApi[body?'POST':'GET'](new Request(base+'/api/expenses',body?{method:'POST',headers:{cookie,origin},body:JSON.stringify(body)}:{}));return {status:r.status,body:await r.json(),headers:r.headers};};
 assert.equal((await call('')).status,401);const id=crypto.randomUUID(),input={id,concept:'Comprobante API ficticio',amount:1,expenseDate:'2026-10-08',note:'',files:[{filename:'Ficticio.pdf',data:Buffer.from(pdfBytes).toString('base64')}]};
 assert.equal((await call(luisaToken,input,'https://untrusted.example.invalid')).status,403);assert.equal((await call(luisaToken,input)).status,200);
 const feed=await call(luisaToken);assert.match(feed.headers.get('cache-control'),/private, no-store/);assert.deepEqual(feed.body.employees,[]);
 const item=feed.body.expenses.find(x=>x.id===id);globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+paulaToken,host:'notices.example.invalid'});const file=await m.expenseFilesApi.GET(new Request(base+'/api/expenses/file?id='+id+'&file='+item.attachments[0].id));assert.equal(file.status,404);
 globalThis.__noticesHeaders=new Headers({cookie:'__Host-jac_session='+luisaToken,host:'notices.example.invalid'});const review=await m.expensesApi.POST(new Request(base+'/api/expenses?review=1',{method:'POST',headers:{origin:base},body:JSON.stringify({id,version:1,decision:'approve',reason:'',employeeId:'fake',periodId:'fake'})}));assert.equal(review.status,403);
 const allowed=await m.expenseFilesApi.GET(new Request(base+'/api/expenses/file?id='+id+'&file='+item.attachments[0].id));assert.equal(allowed.status,200);assert.match(allowed.headers.get('cache-control'),/private, no-store/);
});

async function sectionFixture(sections){
 const id=crypto.randomUUID(),stamp=new Date().toISOString();
 sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,itineraries_only,section_access,created_at,updated_at) VALUES (?,?,?,?,?,?,1,1,?,?,?)').run(id,'sections-'+id,id+'@example.invalid','Secciones ficticias',m.hashPassword('fixture',globalThis.__noticesEnv.PAYROLL_AUTH_KEY),'[]',JSON.stringify(sections),stamp,stamp);
 const token=await m.makeSession(id);return {id,token,user:await m.authenticatedSession(token)};
}
test('secciones independientes: híbrido de fotografía y alertas no hereda itinerarios ni pases',async()=>{
 const alerts=await sectionFixture(['media','alerts']),itineraries=await sectionFixture(['media','itineraries']),boarding=await sectionFixture(['boarding']),photos=await sectionFixture(['media']);
 assert.equal(alerts.user.mediaOnly,true,'El indicador compatible no bloquea las secciones modernas');
 const a={...manualInput('alert',[upload()]),recipients:[alerts.id]};assert.equal((await manualAPI(ownerToken,a)).status,200);
 const itinerary=manualInput('itinerary',[upload()]);assert.equal((await manualAPI(ownerToken,itinerary)).status,200);
 const pass={...manualInput('boarding_pass',[upload('Pase.pdf')]),body:'',travelDate:'2090-10-10',recipients:[boarding.id]};assert.equal((await manualAPI(ownerToken,pass)).status,200);
 const feed=await api(alerts.token);assert.equal(feed.status,200);assert.ok(feed.body.notices.some(n=>n.id===a.id));assert.ok(feed.body.notices.every(n=>n.kind==='alert'));
 const itineraryFeed=await api(itineraries.token);assert.equal(itineraryFeed.status,200);const allItineraries=[...itineraryFeed.body.notices];let cursor=itineraryFeed.body.nextCursor;while(cursor){const page=await api(itineraries.token,undefined,'?cursor='+encodeURIComponent(cursor));assert.equal(page.status,200);allItineraries.push(...page.body.notices);cursor=page.body.nextCursor;}assert.ok(allItineraries.some(n=>n.id===itinerary.id));assert.ok(allItineraries.every(n=>n.kind==='itinerary'));
 const item=await m.noticeItem(alerts.user,a.id);assert.equal((await readAttachment(alerts.token,a.id,item.attachments[0].id)).status,200);
 const other=await m.noticeItem(itineraries.user,itinerary.id);assert.equal((await readAttachment(alerts.token,itinerary.id,other.attachments[0].id)).status,404);
 assert.equal((await api(alerts.token,undefined,'?boarding=current')).status,403);assert.equal((await api(photos.token)).status,403);
 assert.equal((await api(boarding.token,undefined,'?boarding=current')).body.notices.length,1);
 assert.equal((await api(ownerToken,undefined,'?item='+pass.id)).status,404,'Administrar no concede lectura de pases ajenos');
 await assert.rejects(()=>m.markNoticeRead(alerts.user,itinerary.id),e=>e.status===404);
 await assert.rejects(()=>m.confirmNotice(alerts.user,itinerary.id,1,async()=>true),e=>e.status===404);
});
test('destinatarios y altas automáticas respetan la sección de cada aviso, no el perfil compatible',async()=>{
 // This case also runs in isolation; its synthetic Slack setup must not depend on another test.
 if(!(await m.pushCredentials()).slack)assert.equal((await configure('slack',{token:slackToken,signingSecret:slackSecret})).status,200);
 const alertOnly=await sectionFixture(['media','alerts']),travelOnly=await sectionFixture(['media','itineraries']),passOnly=await sectionFixture(['media','boarding']),calendarOnly=await sectionFixture(['calendar']),photoOnly=await sectionFixture(['media']);
 const feed=await m.noticeFeed(await m.authenticatedSession(ownerToken));
 assert.ok(feed.users.some(u=>u.id===alertOnly.id));assert.ok(!feed.users.some(u=>[travelOnly.id,passOnly.id,calendarOnly.id,photoOnly.id].includes(u.id)));
 assert.ok(feed.boardingUsers.some(u=>u.id===passOnly.id));assert.ok(!feed.boardingUsers.some(u=>[travelOnly.id,alertOnly.id,calendarOnly.id,photoOnly.id].includes(u.id)));
 const bad={...manualInput('alert'),recipients:[travelOnly.id]};assert.equal((await manualAPI(ownerToken,bad)).status,409);
 const itinerary=manualInput('itinerary',[upload()]);assert.equal((await manualAPI(ownerToken,itinerary)).status,200);
 const recipients=sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=?').all(itinerary.id).map(r=>r.user_id);
 assert.ok(recipients.includes(travelOnly.id));for(const person of [alertOnly,passOnly,calendarOnly,photoOnly])assert.ok(!recipients.includes(person.id));
 const previous=fileMeta;fileMeta={id:'FSECTIONPDF01',mimetype:'application/pdf',name:'Itinerario ficticio.pdf',size:pdfBytes.length,url_private_download:'https://files.slack.com/sections-fixture.pdf',channels:[m.ITINERARY_CHANNEL]};
 try{await slack(event('FSECTIONPDF01'));const imported=sql.prepare('SELECT id FROM jac_notices WHERE source=?').get('slack:FSECTIONPDF01');assert.ok(imported);const automatic=sql.prepare('SELECT user_id FROM jac_notice_recipients WHERE notice_id=?').all(imported.id).map(r=>r.user_id);assert.ok(automatic.includes(travelOnly.id));for(const person of [alertOnly,passOnly,calendarOnly,photoOnly])assert.ok(!automatic.includes(person.id));}finally{fileMeta=previous;}
});
test('quitar una sección durante R2 o confirmación bloquea el AccessUser anterior y los adjuntos',async()=>{
 const person=await sectionFixture(['media','alerts']),admin=await m.authenticatedSession(ownerToken),input={...manualInput('alert',[upload()]),recipients:[person.id]};
 await m.publishManualNotice(admin,input,async()=>true);const item=await m.noticeItem(person.user,input.id);
 beforeGet=async()=>{beforeGet=undefined;sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["media"]',person.id);};
 try{await assert.rejects(()=>m.noticeAttachment(person.user,input.id,item.attachments[0].id),e=>e.status===404);}finally{beforeGet=undefined;}
 assert.ok(!(await m.noticeFeed(person.user)).notices.some(n=>n.id===input.id));
 await assert.rejects(()=>m.markNoticeRead(person.user,input.id),e=>e.status===404);
 sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["media","alerts"]',person.id);
 await assert.rejects(()=>m.confirmNotice(person.user,input.id,1,async()=>{sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["media"]',person.id);return true;}),e=>e.status===409);
 assert.equal(sql.prepare('SELECT confirmed_revision FROM jac_notice_recipients WHERE notice_id=? AND user_id=?').get(input.id,person.id).confirmed_revision,0);
 assert.equal((await readAttachment(person.token,input.id,item.attachments[0].id)).status,403);
});
test('push se registra por secciones disponibles y revalida el tipo antes del proveedor simulado',async()=>{
 const person=await sectionFixture(['media','alerts']),photo=await sectionFixture(['media']),calendar=await sectionFixture(['calendar']),device=crypto.randomUUID();
 assert.equal((await api(person.token,{action:'register',id:device,platform:'ios',token:'ab'.repeat(32),environment:'sandbox'})).status,200);
 // Photo-only users now receive new-folder pushes. Their independent device
 // must not reuse this alert recipient's token and silently replace it.
 assert.equal((await api(photo.token,{action:'register',id:crypto.randomUUID(),platform:'ios',token:Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('hex'),environment:'sandbox'})).status,200);
 assert.equal((await api(calendar.token,{action:'register',id:crypto.randomUUID(),platform:'ios',token:'ab'.repeat(32),environment:'sandbox'})).status,403);
 const travel=manualInput('itinerary',[upload()]);await m.publishManualNotice(await m.authenticatedSession(ownerToken),travel,async()=>true);
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_push_deliveries WHERE notice_id=? AND device_id=?').get(travel.id,device).n,0);
 const input=alert([person.id]);await m.saveManualNotice(await m.authenticatedSession(ownerToken),input,async()=>true);
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_push_deliveries WHERE notice_id=? AND device_id=?').get(input.id,device).n,1);
 let checks=0;beforeFirst=async query=>{if(query.text.includes("p.status='sending'")&&query.args[0]===input.id&&++checks===2)sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["media"]',person.id);};calls=[];
 try{await m.dispatchPush();}finally{beforeFirst=undefined;}
 assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE notice_id=? AND device_id=?').get(input.id,device).status,'disabled');
 assert.ok(!calls.some(c=>c.url.hostname.includes('push.apple.com')&&JSON.parse(c.options.body).noticeId===input.id));
});
test('GET no serializa feed, detalle o pases si cambian permisos o sesión durante la lectura de adjuntos',async()=>{
 const admin=await m.authenticatedSession(ownerToken);
 for(const route of ['feed','item','boarding'])for(const change of ['sections','session']){
  const person=await sectionFixture(['media',route==='boarding'?'boarding':'alerts']);
  const input={...manualInput(route==='boarding'?'boarding_pass':'alert',[upload()]),recipients:[person.id],...(route==='boarding'?{travelDate:'2090-10-10'}:{})};
  await m.publishManualNotice(admin,input,async()=>true);let changed=false;
  // The SELECT already produced attachment metadata; invalidate access before
  // the awaited noticeViews result reaches the route's response construction.
  afterAll=async query=>{if(query.text.startsWith('SELECT id,notice_id,filename,mime_type,size FROM jac_notice_attachments')&&query.args.includes(input.id)){afterAll=undefined;changed=true;if(change==='sections')sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run(JSON.stringify(['media',route==='boarding'?'alerts':'boarding']),person.id);else sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(person.token));}};
  const beforeScheduled=scheduled;
  try{
   const query=route==='feed'?'':route==='item'?'?item='+input.id:'?boarding=current',result=await api(person.token,undefined,query);
   assert.equal(changed,true,route+' must reach the awaited attachment read');assert.equal(result.status,403,route+' / '+change);assert.deepEqual(Object.keys(result.body),['error']);assert.equal(scheduled,beforeScheduled,'An invalidated read must not start background imports');
  }finally{afterAll=undefined;}
 }
});

test('abandoned push claims become uncertain and fresh in-flight deliveries are never restarted',async()=>{
 const old='audit-stale-push',fresh='audit-live-push';
 for(const [id,stamp] of [[old,'2000-01-01T00:00:00Z'],[fresh,new Date().toISOString()]])sql.prepare("INSERT INTO jac_push_deliveries(id,notice_id,device_id,status,updated_at) VALUES(?,'fixture-only','fixture-only','sending',?)").run(id,stamp);
 await m.dispatchPush();assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE id=?').get(old).status,'uncertain');assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE id=?').get(fresh).status,'sending');await m.dispatchPush();assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE id=?').get(old).status,'uncertain');
});


async function recipientRoster(token){
 globalThis.__noticesHeaders=new Headers({cookie:token?'__Host-jac_session='+token:'',host:'notices.example.invalid'});
 const response=await m.recipientApi.GET();return {response,status:response.status,body:await response.json()};
}
test('destinatarios actualizados: consulta privada solo administrativa sin importaciones ni envíos',async()=>{
 const beforeScheduled=scheduled,beforeCalls=calls.length;
 assert.equal((await recipientRoster('')).status,401);
 assert.equal((await recipientRoster(luisaToken)).status,403);
 const result=await recipientRoster(ownerToken);assert.equal(result.status,200);
 assert.deepEqual(Object.keys(result.body).sort(),['boardingUsers','users']);
 assert.match(result.response.headers.get('Cache-Control'),/private, no-store/);
 for(const user of result.body.users)assert.deepEqual(Object.keys(user).sort(),['id','name','ready']);
 for(const user of result.body.boardingUsers)assert.deepEqual(Object.keys(user).sort(),['id','name']);
 assert.equal(scheduled,beforeScheduled);assert.equal(calls.length,beforeCalls);
});
test('destinatarios actualizados: usuarios nuevos y pendientes aparecen por permisos actuales sin ampliar otras cuentas',async()=>{
 const fresh=crypto.randomUUID(),pending=crypto.randomUUID(),excluded=crypto.randomUUID(),inactive=crypto.randomUUID(),boardingOnly=crypto.randomUUID();
 const insert=(id,name,sections,active=1,password='')=>sql.prepare("INSERT INTO payroll_users(id,username,email,name,active,permissions,itineraries_only,media_only,section_access,password_hash,created_at,updated_at) VALUES (?,?,?,?,?,'[]',1,0,?,?, 'fixture','fixture')").run(id,id,id+'@example.invalid',name,active,JSON.stringify(sections),password);
 insert(excluded,'Sin alertas ficticio',['music']);insert(inactive,'Inactivo ficticio',['alerts'],0);insert(boardingOnly,'Solo pase ficticio',['boarding']);
 let result=await recipientRoster(ownerToken);for(const id of [excluded,inactive,boardingOnly])assert.ok(!result.body.users.some(user=>user.id===id));assert.ok(result.body.boardingUsers.some(user=>user.id===boardingOnly));
 insert(fresh,'Persona nueva ficticia',['alerts','music'],1,'fixture-hash');insert(pending,'Persona pendiente ficticia',['alerts']);
 result=await recipientRoster(ownerToken);assert.deepEqual(result.body.users.find(user=>user.id===fresh),{id:fresh,name:'Persona nueva ficticia',ready:true});assert.deepEqual(result.body.users.find(user=>user.id===pending),{id:pending,name:'Persona pendiente ficticia',ready:false});
 const other=sql.prepare('SELECT section_access,permissions,itineraries_only,media_only FROM payroll_users WHERE id=?').get(excluded);
 sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["music"]',fresh);
 sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(pending);
 result=await recipientRoster(ownerToken);assert.ok(!result.body.users.some(user=>user.id===fresh||user.id===pending));assert.deepEqual(sql.prepare('SELECT section_access,permissions,itineraries_only,media_only FROM payroll_users WHERE id=?').get(excluded),other);
});
test('destinatarios actualizados: cambio de sesión durante la consulta impide devolver los nombres',async()=>{
 const original=sql.prepare('SELECT name FROM payroll_users WHERE id=?').get(owner).name;let changed=false;
 afterAll=async query=>{if(!changed&&query.text.includes('ORDER BY name,id')){changed=true;sql.prepare('UPDATE payroll_users SET name=? WHERE id=?').run('Actor cambiado durante consulta',owner);}};
 try{const result=await recipientRoster(ownerToken);assert.equal(changed,true);assert.equal(result.status,403);assert.deepEqual(Object.keys(result.body),['error']);}
 finally{afterAll=undefined;sql.prepare('UPDATE payroll_users SET name=? WHERE id=?').run(original,owner);}
});
