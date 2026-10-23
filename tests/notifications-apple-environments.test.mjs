import {test,before,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {build} from 'esbuild';
import {mkdtemp,readFile,readdir,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createPublicKey,verify} from 'node:crypto';

// Independent D1 and providers: no real Apple keys, devices, notices or traffic.
const sql=new DatabaseSync(':memory:');
let beforeFirst,waiting=[],calls=[],m,owner,reader,production,sandbox;
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const statement=sql.prepare(this.text);return statement.columns().length?{results:statement.all(...this.args),meta:{changes:0}}:{results:[],meta:{changes:Number(statement.run(...this.args).changes)}};}
 async run(){return this.execute();}
 async all(){return this.execute();}
 async first(){if(beforeFirst)await beforeFirst(this);return sql.prepare(this.text).get(...this.args)??null;}
}
globalThis.__appleEnvironmentEnv={
 DB:{prepare:text=>new Query(text),batch:async statements=>{sql.exec('BEGIN');try{const results=statements.map(statement=>statement.execute());sql.exec('COMMIT');return results;}catch(error){sql.exec('ROLLBACK');throw error;}}},
 BUCKET:{get:async()=>null,delete:async()=>{},put:async()=>{throw Error('No attachments are uploaded by Apple environment tests.');}},
 PAYROLL_AUTH_KEY:'apns-environments-independent-synthetic-authentication-key',
 PAYROLL_MAIL_KEY:Buffer.alloc(32,73).toString('base64url'),
};
globalThis.__appleEnvironmentHeaders=new Headers();
globalThis.__appleEnvironmentWait=promise=>waiting.push(promise);
// Register every case synchronously: an interrupted async fixture must report
// setup failures/cancellations instead of a misleading empty-file success.
before(async()=>{
for(const name of(await readdir('drizzle')).filter(name=>name.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+name,'utf8'));
const compiled=await build({stdin:{resolveDir:process.cwd(),contents:`
 export * as api from './app/api/notices/route';
 export * from './lib/notifications';
 export * from './lib/notifications-core';
 export * from './lib/payroll-auth-store';
 export * from './lib/payroll-auth-crypto';
 export {encryptMail} from './lib/payroll-mail-core';
 export {mailKey} from './lib/payroll-mail';
 `},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'apple-environment-fixtures',setup(plugin){
 plugin.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},args=>({path:args.path,namespace:'synthetic-platform'}));
 plugin.onLoad({filter:/.*/,namespace:'synthetic-platform'},args=>({loader:'js',contents:args.path==='cloudflare:workers'?'export const env=globalThis.__appleEnvironmentEnv;export const waitUntil=globalThis.__appleEnvironmentWait;':'export const headers=async()=>globalThis.__appleEnvironmentHeaders;'}));
 }}]});
const directory=await mkdtemp(resolve('work/apple-environments-tests-')),path=directory+'/fixture.mjs';
try{await writeFile(path,compiled.outputFiles[0].contents);m=await import(pathToFileURL(path).href);}finally{await rm(directory,{recursive:true,force:true});}
owner=await m.bootstrapOwner('apple-environments-owner','synthetic-password');
reader=crypto.randomUUID();
sql.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,section_access,created_at,updated_at) VALUES (?,'synthetic-apple-reader','reader@example.invalid','Synthetic Reader','synthetic-ready','[]','[\"alerts\"]','fixture','fixture')").run(reader);
production=await syntheticAppleKey('PRODKEY001');sandbox=await syntheticAppleKey('SANDKEY001');
});
async function syntheticAppleKey(keyId){
 const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const encoded=Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64');
 return {credentials:{teamId:'TESTTEAM01',keyId,privateKey:'-----BEGIN PRIVATE KEY-----\n'+encoded+'\n-----END PRIVATE KEY-----'},publicKey:createPublicKey({key:await crypto.subtle.exportKey('jwk',pair.publicKey),format:'jwk'})};
}
const preserved=()=>({slack:{token:'xoxb-synthetic-never-use',signingSecret:'synthetic-slack-secret'},web:{publicKey:'synthetic-public-browser-key',privateKey:{d:'synthetic-private-browser-key'}},wallet:{privateKey:'synthetic-private-wallet-key',certificate:'synthetic-wallet-certificate'}});
const base='https://apns-environments.example.invalid';let ownerToken,readerToken;
async function setCredentials(keys){sql.prepare('UPDATE jac_notice_settings SET credentials=?,version=version+1 WHERE id=?').run(await m.encryptMail(keys,m.mailKey()),'jac');}
async function settle(){while(waiting.length){const batch=waiting;waiting=[];await Promise.all(batch);}}
async function api(token,body,{origin=base}={}){
 const cookie=token?'__Host-jac_session='+token:'';globalThis.__appleEnvironmentHeaders=new Headers({cookie,host:'apns-environments.example.invalid'});
 const request=new Request(base+'/api/notices',body?{method:'POST',headers:{cookie,origin,'Content-Type':'application/json'},body:JSON.stringify(body)}:{headers:{cookie}});
 const response=await m.api[body?'POST':'GET'](request),result={status:response.status,body:await response.json()};await settle();return result;
}
async function configure(credentials,environment){return api(ownerToken,{action:'configure',kind:'apple',version:(await m.noticeConfig()).version,...credentials,...(environment===undefined?{}:{environment})});}
async function register(environment,token){const id=crypto.randomUUID();assert.equal((await api(readerToken,{action:'register',id,platform:'ios',token,environment})).status,200);return id;}
async function alert(){const value={id:crypto.randomUUID(),title:'Synthetic environment notice',body:'No real recipient or provider is contacted.',recipients:[reader]};assert.equal((await api(ownerToken,{action:'alert',alert:value})).status,200);return value;}
function jwt(call){const headers=new Headers(call.options.headers),parts=headers.get('authorization').split(' ')[1].split('.');return {header:JSON.parse(Buffer.from(parts[0],'base64url')),claims:JSON.parse(Buffer.from(parts[1],'base64url')),signature:Buffer.from(parts[2],'base64url'),signed:Buffer.from(parts.slice(0,2).join('.'))};}
beforeEach(async()=>{
 beforeFirst=undefined;waiting=[];calls=[];
 for(const table of ['jac_push_deliveries','jac_push_devices','jac_notice_recipients','jac_notice_attachments','jac_notices','jac_notice_settings','payroll_sessions'])sql.exec('DELETE FROM '+table);
 sql.prepare('UPDATE payroll_users SET active=1 WHERE id IN (?,?)').run(owner,reader);
 sql.prepare('INSERT INTO jac_notice_settings(id,credentials,version) VALUES (?,?,1)').run('jac',await m.encryptMail(preserved(),m.mailKey()));
 ownerToken=await m.makeSession(owner);readerToken=await m.makeSession(reader);
 globalThis.fetch=async(input,options={})=>{const url=new URL(String(input));assert.ok(['https://api.push.apple.com','https://api.sandbox.push.apple.com'].includes(url.origin),'Every provider is intercepted; unexpected traffic is forbidden.');calls.push({url,options});return new Response(null,{status:200});};
});

test('Apple credentials keep production and sandbox isolated, default legacy saves to production, and expose only configuration booleans',async()=>{
 const initial=await configure(production.credentials);assert.equal(initial.status,200);assert.equal(initial.body.settings.appleConfigured,true);assert.equal(initial.body.settings.appleSandboxConfigured,false);
 const first=await m.pushCredentials();assert.equal(first.apns.keyId,production.credentials.keyId);assert.equal(first.apnsSandbox,undefined);
 const second=await configure(sandbox.credentials,'sandbox');assert.equal(second.status,200);assert.equal(second.body.settings.appleConfigured,true);assert.equal(second.body.settings.appleSandboxConfigured,true);
 const both=await m.pushCredentials();assert.deepEqual(both.apns,first.apns);assert.equal(both.apnsSandbox.keyId,sandbox.credentials.keyId);assert.equal(both.apnsSandbox.privateKey,sandbox.credentials.privateKey);
 assert.equal((await configure({...production.credentials,keyId:'PRODROT001'})).status,200);
 const rotated=await m.pushCredentials();assert.deepEqual(rotated.apnsSandbox,both.apnsSandbox);for(const key of ['slack','web','wallet'])assert.deepEqual(rotated[key],preserved()[key]);
 const encrypted=(await m.noticeConfig()).credentials;for(const secret of [production.credentials.privateKey,sandbox.credentials.privateKey,'synthetic-private-browser-key','synthetic-private-wallet-key'])assert.ok(!encrypted.includes(secret));
 const feed=await api(ownerToken),serialized=JSON.stringify(feed.body);assert.equal(feed.status,200);for(const value of ['PRIVATE KEY',production.credentials.keyId,sandbox.credentials.keyId,'synthetic-private-browser-key','synthetic-private-wallet-key','xoxb-synthetic-never-use'])assert.ok(!serialized.includes(value));
 assert.deepEqual(calls,[]);
});

test('Apple dispatch signs each device environment with its matching key and provider endpoint',async()=>{
 assert.equal((await configure(production.credentials,'production')).status,200);assert.equal((await configure(sandbox.credentials,'sandbox')).status,200);
 const prodId=await register('production','ab'.repeat(32)),sandboxId=await register('sandbox','cd'.repeat(32)),notice=await alert();
 assert.equal(calls.length,2);
 for(const [origin,key,otherKey,token] of [['https://api.push.apple.com',production,sandbox,'ab'.repeat(32)],['https://api.sandbox.push.apple.com',sandbox,production,'cd'.repeat(32)]]){
  const call=calls.find(call=>call.url.origin===origin);assert.ok(call);assert.equal(call.url.pathname,'/3/device/'+token);assert.equal(call.options.redirect,'manual');
  const parsed=jwt(call);assert.equal(parsed.header.kid,key.credentials.keyId);assert.equal(parsed.header.alg,'ES256');assert.equal(parsed.claims.iss,key.credentials.teamId);
  assert.ok(verify('sha256',parsed.signed,{key:key.publicKey,dsaEncoding:'ieee-p1363'},parsed.signature));assert.equal(verify('sha256',parsed.signed,{key:otherKey.publicKey,dsaEncoding:'ieee-p1363'},parsed.signature),false);
  assert.equal(new Headers(call.options.headers).get('apns-topic'),'co.jacmusic.nomina');assert.equal(JSON.parse(call.options.body).noticeId,notice.id);
 }
 assert.deepEqual(sql.prepare('SELECT device_id,status FROM jac_push_deliveries WHERE notice_id=? ORDER BY device_id').all(notice.id).map(row=>[row.device_id,row.status]),[[prodId,'sent'],[sandboxId,'sent']].sort(([a],[b])=>a.localeCompare(b)));
 await m.dispatchPush();assert.equal(calls.length,2,'Already delivered notices are not resent while environments are selected.');
});

test('Sandbox keeps the legacy production-key fallback while sandbox-only credentials never serve a production device',async()=>{
 await setCredentials({...preserved(),apns:production.credentials});const sandboxId=await register('sandbox','ef'.repeat(32));await alert();
 assert.equal(calls.length,1);assert.equal(calls[0].url.origin,'https://api.sandbox.push.apple.com');assert.equal(jwt(calls[0]).header.kid,production.credentials.keyId);
 await setCredentials({...preserved(),apnsSandbox:sandbox.credentials});const prodId=await register('production','12'.repeat(32));calls=[];const notice=await alert();
 assert.equal(calls.length,1);assert.equal(calls[0].url.origin,'https://api.sandbox.push.apple.com');assert.equal(jwt(calls[0]).header.kid,sandbox.credentials.keyId);
 assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE notice_id=? AND device_id=?').get(notice.id,prodId).status,'unconfigured');assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE notice_id=? AND device_id=?').get(notice.id,sandboxId).status,'sent');
 const state=await api(ownerToken);assert.equal(state.body.settings.appleConfigured,false);assert.equal(state.body.settings.appleSandboxConfigured,true);
});

test('Apple environment configuration preserves owner authorization, origin, CAS and session revocation checks',async()=>{
 const version=(await m.noticeConfig()).version,body={action:'configure',kind:'apple',environment:'sandbox',version,...sandbox.credentials},before=(await m.noticeConfig()).credentials;
 assert.equal((await api('',body)).status,401);assert.equal((await api(readerToken,body)).status,403);assert.equal((await api(ownerToken,body,{origin:'https://untrusted.example.invalid'})).status,403);
 assert.equal((await api(ownerToken,{...body,version:version-1})).status,409);assert.equal((await api(ownerToken,{...body,environment:'both'})).status,400);
 await assert.rejects(()=>m.configureNotices('apple',body,async()=>false),error=>error.status===403);
 assert.equal((await m.noticeConfig()).credentials,before);
 beforeFirst=async query=>{if(query.text==='SELECT credentials,version FROM jac_notice_settings WHERE id=?'){beforeFirst=undefined;sql.prepare('DELETE FROM payroll_sessions WHERE user_id=?').run(owner);}};
 assert.equal((await api(ownerToken,body)).status,403);assert.equal((await m.noticeConfig()).credentials,before);assert.deepEqual(calls,[]);
});
