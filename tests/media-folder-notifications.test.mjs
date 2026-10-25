import test,{beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createECDH,createDecipheriv,hkdfSync} from 'node:crypto';
import {readFile,readdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {build} from 'esbuild';

// Fixture metadata and independent ephemeral keys only. There is no real R2,
// account, photo, Slack import, key file, notification, or external request.
const sql=new DatabaseSync(':memory:');
const migrations=(await readdir('drizzle')).filter(name=>name.endsWith('.sql')).sort();
for(const name of migrations)sql.exec(await readFile('drizzle/'+name,'utf8'));
let beforeQuery,providerHook,calls,queryHook;
class Query{
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);return q.columns().length?{results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() n').get().n)}}:{results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async first(){await beforeQuery?.(this);return sql.prepare(this.text).get(...this.args)??null;}
 async all(){await queryHook?.(this);return this.execute();}
 async run(){await queryHook?.(this);return this.execute();}
}
globalThis.__mediaPushEnv={DB:{prepare:text=>new Query(text),batch:async queries=>{sql.exec('BEGIN');try{const rows=queries.map(query=>query.execute());sql.exec('COMMIT');return rows;}catch(error){sql.exec('ROLLBACK');throw error;}}},PAYROLL_AUTH_KEY:'independent-media-folder-push-fixture-auth',PAYROLL_MAIL_KEY:Buffer.alloc(32,53).toString('base64url')};
globalThis.__mediaPushHeaders=new Headers();
const bundled=await build({stdin:{contents:"export * from './lib/media-folder-notifications';export * from './lib/notifications-core';export * from './lib/notifications';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export {encryptMail,decryptMail} from './lib/payroll-mail-core';export * as api from './app/api/notices/route';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'media-push-fixtures',setup(builder){builder.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},args=>({path:args.path,namespace:'fixture'}));builder.onLoad({filter:/.*/,namespace:'fixture'},args=>({contents:args.path==='cloudflare:workers'?'export const env=globalThis.__mediaPushEnv;export const waitUntil=()=>{throw Error("No imports should be scheduled by registration tests");};':'export const headers=async()=>globalThis.__mediaPushHeaders;',loader:'js'}));}}]});
const dir=await mkdtemp(resolve('work/media-folder-push-')),file=dir+'/fixture.mjs';await writeFile(file,bundled.outputFiles[0].contents);const m=await import(pathToFileURL(file).href);await rm(dir,{recursive:true});
const FOLDER='application/vnd.google-apps.folder',stamp=(ago=0)=>new Date(Date.now()-ago).toISOString();
let keys;
beforeEach(async()=>{
 beforeQuery=undefined;queryHook=undefined;providerHook=undefined;calls=[];
 sql.exec('DELETE FROM jac_media_folder_push_deliveries;DELETE FROM jac_media_folder_notifications;DELETE FROM jac_media_r2_entries;DELETE FROM jac_media_operations;DELETE FROM jac_media_r2_connection;DELETE FROM jac_notice_settings;DELETE FROM jac_push_devices;DELETE FROM payroll_sessions;DELETE FROM payroll_users;');
 sql.prepare("INSERT INTO jac_media_r2_connection(id,credentials,enabled,version,updated_at) VALUES('jac','fixture-only-no-storage-connection',1,1,?)").run(stamp());
 const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']),pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';
 keys={apns:{teamId:'FIXTURE001',keyId:'FIXTUREKEY',privateKey:pem},apnsSandbox:{teamId:'FIXTURE002',keyId:'SANDBOXKEY',privateKey:pem},web:await m.createWebKeys()};
 sql.prepare("INSERT INTO jac_notice_settings(id,credentials) VALUES('jac',?)").run(await m.encryptMail(keys,globalThis.__mediaPushEnv.PAYROLL_MAIL_KEY));
 globalThis.fetch=async(input,options={})=>{const url=new URL(String(input));assert.ok(['api.push.apple.com','api.sandbox.push.apple.com','fcm.googleapis.com'].includes(url.hostname),'All non-fixture provider traffic is blocked');calls.push({url,options});return await providerHook?.(url,options)??new Response(null,{status:200});};
});
async function user({sections=['media'],legacy=false,active=1,owner=false}={}){
 const id=crypto.randomUUID();sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,section_access,media_only,active,owner,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').run(id,'fixture-'+id,id+'@example.invalid','Usuario ficticio','fixture-password-never-used','[]',legacy?null:JSON.stringify(sections),Number(legacy),active,Number(owner),stamp(),stamp());
 const token=active?await m.makeSession(id,true):'';return {id,token,actor:active?await m.authenticatedSession(token):null};
}
async function device(person,platform='ios',environment='production'){
 const id=crypto.randomUUID();let receiver,subscription;
 if(platform==='web'){receiver=createECDH('prime256v1');receiver.generateKeys();subscription={endpoint:'https://fcm.googleapis.com/fcm/send/'+id,keys:{p256dh:receiver.getPublicKey().toString('base64url'),auth:Buffer.alloc(16,19).toString('base64url')}};}
 await m.registerDevice(person.actor,{id,platform,...(platform==='ios'?{token:'ad'.repeat(32),environment}:{subscription})},person.token,async()=>true);
 return {id,receiver,subscription};
}
function folder(name='Show de prueba',parent='jac_r2_root'){
 const id='r2_'+crypto.randomUUID();sql.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,?,?,?,?)').run(id,parent,name,FOLDER,'fixture-uploader','fixture-folder',stamp(300_000),stamp(300_000));return id;
}
function upload(parent,{status='ready',age=180_000,mime='image/jpeg',published=status==='ready',claim='',claimAge=0}={}){
 const id=crypto.randomUUID(),entry='r2_'+id;sql.prepare('INSERT INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,drive_id,name,mime_type,size,offset,status,connection_version,claim,claim_at,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').run(id,'fixture-uploader',parent,'fixture-upload','r2-upload',entry,'fixture.jpg',mime,100,status==='ready'?100:0,status,1,claim,claim?stamp(claimAge):'',stamp(86_400_000),stamp(-7*86_400_000));
 if(published)sql.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,?,?,?,?,?,?)').run(entry,parent,'fixture.jpg',mime,100,'originals/'+id,'fixture-uploader','fixture-upload',stamp(age),stamp(age));return id;
}
const status=id=>sql.prepare('SELECT status FROM jac_media_folder_notifications WHERE folder_id=?').get(id)?.status;

test('migration creates no historical events; a future folder gets one durable candidate',async()=>{
 const historical=new DatabaseSync(':memory:');
 for(const name of migrations.filter(name=>!name.startsWith('0036_')))historical.exec(await readFile('drizzle/'+name,'utf8'));
 historical.exec("INSERT INTO jac_media_r2_connection(id,enabled,version,updated_at) VALUES('jac',1,1,'2026-01-01');INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,actor_id,payload_hash,created_at,modified_at) VALUES('r2_11111111-1111-4111-8111-111111111111','jac_r2_root','Anterior','application/vnd.google-apps.folder','fixture','fixture','2026-01-01','2026-01-01');");
 historical.exec(await readFile('drizzle/0036_media_folder_notifications.sql','utf8'));assert.equal(historical.prepare('SELECT count(*) n FROM jac_media_folder_notifications').get().n,0);historical.close();
 const id=folder();assert.equal(status(id),'waiting');assert.equal(sql.prepare('SELECT count(*) n FROM jac_media_folder_notifications').get().n,1);
 upload('jac_r2_root');assert.equal(sql.prepare('SELECT count(*) n FROM jac_media_folder_notifications').get().n,1);await m.processMediaFolderNotifications();assert.equal(calls.length,0);
});

test('empty, pending, canceled and invalid uploads do not publish; latest successful completion controls quiet time',async()=>{
 await device(await user());const empty=folder('Vacía'),pending=folder('Pendiente'),canceled=folder('Cancelada'),invalid=folder('Inválida'),recent=folder('Acaba de terminar');
 upload(pending,{status:'pending'});upload(canceled,{status:'cancelled'});upload(invalid,{status:'pending',mime:'application/octet-stream'});upload(recent,{age:5000});
 await m.processMediaFolderNotifications();assert.equal(calls.length,0);for(const id of [empty,pending,canceled,invalid,recent])assert.equal(status(id),'waiting');
 sql.prepare('UPDATE jac_media_r2_entries SET modified_at=? WHERE parent_id=?').run(stamp(180_000),recent);await m.processMediaFolderNotifications();assert.equal(calls.length,1);assert.equal(status(recent),'published');
});

test('one event per new folder survives concurrent cron and repeated uploads without entering old notice feeds',async()=>{
 await device(await user());const id=folder('Medellín · sábado');upload(id);upload(id);
 await Promise.all([m.publishMediaFolderNotifications(),m.publishMediaFolderNotifications()]);await m.dispatchMediaFolderPush();await m.processMediaFolderNotifications();
 assert.equal(calls.length,1);assert.equal(sql.prepare('SELECT count(*) n FROM jac_media_folder_push_deliveries').get().n,1);assert.equal(sql.prepare('SELECT count(*) n FROM jac_notices').get().n,0);
 const push=JSON.parse(calls[0].options.body);assert.deepEqual(push.aps.alert,{title:'¡Nuevas fotos disponibles!',body:'Ya está disponible la carpeta «Medellín · sábado».'});assert.equal(push.kind,'media_folder');assert.equal(push.folderId,id);assert.equal(push.noticeId,id.slice(3));
 upload(id);await m.processMediaFolderNotifications();assert.equal(calls.length,1);
});

test('media-only legacy and explicit media users receive independently of alerts; revoked sessions and grants do not',async()=>{
 const legacy=await user({legacy:true}),explicit=await user(),alerts=await user({sections:['alerts']}),expired=await user(),revoked=await user(),disabled=await user(),stale=await user();
 await device(legacy);await device(explicit);await device(alerts);await device(expired);await device(revoked);await device(disabled);await device(stale);
 sql.prepare('UPDATE payroll_sessions SET persistent=0,expires_at=? WHERE user_id=?').run(stamp(1),expired.id);sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',revoked.id);sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(disabled.id);sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(stale.id);
 const id=folder();upload(id);await m.processMediaFolderNotifications();assert.equal(calls.length,2);assert.deepEqual(sql.prepare('SELECT user_id FROM jac_media_folder_push_deliveries ORDER BY user_id').all().map(row=>row.user_id),[legacy.id,explicit.id].sort());
});

test('pending descendants and active leases block publication; nested deletions and connection changes suppress delivery',async()=>{
 await device(await user());const parent=folder('Principal'),child=folder('Subcarpeta',parent);upload(parent);const pending=upload(child,{status:'pending'});
 await m.processMediaFolderNotifications();assert.equal(calls.length,0);sql.prepare("UPDATE jac_media_operations SET status='cancelled' WHERE id=?").run(pending);
 const claimed=upload(parent,{claim:'fixture-lease'});await m.processMediaFolderNotifications();assert.equal(calls.length,0);sql.prepare("UPDATE jac_media_operations SET claim='',claim_at='' WHERE id=?").run(claimed);
 await m.publishMediaFolderNotifications();assert.equal(status(parent),'published');
 sql.prepare("INSERT INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,name,mime_type,connection_version,created_at,expires_at) VALUES(?,?,?,'fixture','r2-delete-folder','fixture','',1,?,?)").run('r2-delete:'+parent,'fixture',parent,stamp(),stamp());
 await m.dispatchMediaFolderPush();assert.equal(calls.length,0);assert.equal(sql.prepare('SELECT status FROM jac_media_folder_push_deliveries').get().status,'disabled');
 const newer=folder();upload(newer);await m.publishMediaFolderNotifications();sql.exec('UPDATE jac_media_r2_connection SET version=2');await m.dispatchMediaFolderPush();assert.equal(calls.length,0);
});

test('permission, session deletion and a new pending upload are rechecked after signing and before the provider call',async()=>{
 for(const mutation of ['permission','session','pending']){
  const person=await user();await device(person);const id=folder(mutation);upload(id);await m.publishMediaFolderNotifications();let checks=0;
  beforeQuery=query=>{if(query.text.includes('AS settled')&&++checks===2){if(mutation==='permission')sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',person.id);if(mutation==='session')sql.prepare('DELETE FROM payroll_sessions WHERE user_id=?').run(person.id);if(mutation==='pending')upload(id,{status:'pending'});}};
  await m.dispatchMediaFolderPush();beforeQuery=undefined;assert.equal(calls.length,0);
  const state=sql.prepare('SELECT status FROM jac_media_folder_push_deliveries WHERE event_id=?').get(id.slice(3)).status;assert.equal(state,mutation==='pending'?'pending':'disabled');
  if(mutation==='pending'){sql.prepare("UPDATE jac_media_operations SET status='cancelled' WHERE parent_id=? AND status='pending'").run(id);await m.dispatchMediaFolderPush();assert.equal(calls.length,1);calls=[];}
 }
});

test('ambiguous provider results and abandoned sending leases are terminal and cannot resend',async()=>{
 await device(await user());const id=folder();upload(id);providerHook=()=>{throw Error('Fixture lost response');};await m.processMediaFolderNotifications();assert.equal(calls.length,1);assert.equal(sql.prepare('SELECT status FROM jac_media_folder_push_deliveries').get().status,'uncertain');providerHook=undefined;await m.processMediaFolderNotifications();assert.equal(calls.length,1);
 const next=folder();upload(next);await m.publishMediaFolderNotifications();sql.prepare("UPDATE jac_media_folder_push_deliveries SET status='sending',updated_at=? WHERE event_id=?").run(stamp(180_000),next.slice(3));await m.dispatchMediaFolderPush();assert.equal(calls.length,1);assert.equal(sql.prepare('SELECT status FROM jac_media_folder_push_deliveries WHERE event_id=?').get(next.slice(3)).status,'uncertain');
});

test('APNs environments stay separate and Web Push carries the exact folder in an independently decrypted payload',async()=>{
 const person=await user();await device(person,'ios','sandbox');await device(person,'ios','production');const web=await device(person,'web'),id=folder('Carpeta web');upload(id);await m.processMediaFolderNotifications();assert.equal(calls.length,3);
 const sandbox=calls.find(call=>call.url.hostname==='api.sandbox.push.apple.com'),production=calls.find(call=>call.url.hostname==='api.push.apple.com');
 const keyId=call=>JSON.parse(Buffer.from(call.options.headers.Authorization.split(' ')[1].split('.')[0],'base64url')).kid;assert.equal(keyId(sandbox),'SANDBOXKEY');assert.equal(keyId(production),'FIXTUREKEY');
 const payload=Buffer.from(calls.find(call=>call.url.hostname==='fcm.googleapis.com').options.body),salt=payload.subarray(0,16),sender=payload.subarray(21,21+payload[20]),cipher=payload.subarray(21+payload[20]),shared=web.receiver.computeSecret(sender),auth=Buffer.from(web.subscription.keys.auth,'base64url');
 const ikm=Buffer.from(hkdfSync('sha256',shared,auth,Buffer.concat([Buffer.from('WebPush: info\0'),web.receiver.getPublicKey(),sender]),32)),key=Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: aes128gcm\0'),16)),nonce=Buffer.from(hkdfSync('sha256',ikm,salt,Buffer.from('Content-Encoding: nonce\0'),12));
 const decipher=createDecipheriv('aes-128-gcm',key,nonce);decipher.setAuthTag(cipher.subarray(-16));const decoded=Buffer.concat([decipher.update(cipher.subarray(0,-16)),decipher.final()]);assert.equal(decoded.at(-1),2);assert.deepEqual(JSON.parse(decoded.subarray(0,-1).toString()),{id:id.slice(3),kind:'media_folder',folderId:id,title:'¡Nuevas fotos disponibles!',body:'Ya está disponible la carpeta «Carpeta web».'});
});

test('media-only registration and public push settings work while ordinary notice actions remain forbidden',async()=>{
 const person=await user({legacy:true});
 const request=async(body,query='')=>{const cookie='__Host-jac_session='+person.token;globalThis.__mediaPushHeaders=new Headers({host:'media-push.example.invalid',cookie});const req=new Request('https://media-push.example.invalid/api/notices'+query,{...(body?{method:'POST',body:JSON.stringify(body)}:{}),headers:{cookie,origin:'https://media-push.example.invalid'}});return m.api[body?'POST':'GET'](req);};
 const settings=await request(undefined,'?push=1');assert.equal(settings.status,200);assert.deepEqual(await settings.json(),{settings:{webPublicKey:keys.web.publicKey}});assert.equal((await request()).status,403);
 assert.equal((await request({action:'register',id:crypto.randomUUID(),platform:'ios',token:'ab'.repeat(32),environment:'production'})).status,200);
 assert.equal((await request({action:'read',id:crypto.randomUUID()})).status,403);assert.equal((await request({action:'alert',alert:{}})).status,403);assert.equal(calls.length,0);
});
