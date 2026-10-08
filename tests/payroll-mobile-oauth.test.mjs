import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

const sql=new DatabaseSync(':memory:');
for(const file of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+file,'utf8'));
class Query{
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};const out=q.run(...this.args);return {results:[],meta:{changes:Number(out.changes)}};}
 async run(){return this.execute();}async all(){return this.execute();}async first(){return sql.prepare(this.text).get(...this.args)||null;}
}
globalThis.__nativeOauthEnv={DB:{prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const out=qs.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},PAYROLL_AUTH_KEY:'oauth-tests-independent-auth-key-only',PAYROLL_MAIL_KEY:Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url')};
globalThis.__nativeOauthHeaders=new Headers();
const bundle=await build({stdin:{contents:"export * as api from './app/api/mobile/gmail/route';export * as callback from './app/api/payroll/gmail/callback/route';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-mobile-oauth';export * from './lib/payroll-mail';export * from './lib/payroll-mail-core';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__nativeOauthEnv;export const waitUntil=p=>p.catch(()=>{});':'export const headers=async()=>globalThis.__nativeOauthHeaders;',loader:'js'}));}}]});
const temporary=await mkdtemp(resolve('work/oauth-tests-'));
const moduleFile=temporary+'/bundle.mjs';await writeFile(moduleFile,bundle.outputFiles[0].contents);
const m=await import(pathToFileURL(moduleFile).href);await rm(temporary,{recursive:true});
const base='https://oauth.example.invalid';
const owner=await m.bootstrapOwner('oauth-owner','1');
let calls=[];
globalThis.fetch=async(input,options={})=>{
 const url=String(input);calls.push({url,options});
 if(url==='https://oauth2.googleapis.com/token')return Response.json({access_token:'simulated-access',refresh_token:'simulated-refresh',scope:'https://www.googleapis.com/auth/gmail.send'});
 if(url==='https://openidconnect.googleapis.com/v1/userinfo')return Response.json({email:m.GMAIL_SENDER,email_verified:true});
 if(url==='https://oauth2.googleapis.com/revoke')return Response.json({});
 throw new Error('Las pruebas no admiten otros destinos ni correo real.');
};
async function start(token,origin=base){
 globalThis.__nativeOauthHeaders=new Headers({host:'oauth.example.invalid',cookie:token?'__Host-jac_session='+token:''});
 const r=await m.api.POST(new Request(base+'/api/mobile/gmail',{method:'POST',headers:{origin,cookie:token?'__Host-jac_session='+token:''},body:'{}'}));
 return {status:r.status,body:await r.json(),headers:r.headers};
}
async function handoff(token){
 const result=await start(token);assert.equal(result.status,200,result.body.error);
 const ticket=new URL(result.body.url).searchParams.get('ticket');
 const browser=await m.api.GET(new Request(result.body.url)),location=browser.headers.get('location');
 assert.equal(browser.status,303);assert.equal(new URL(location).host,'accounts.google.com');
 const cookie=browser.headers.get('set-cookie');assert.match(cookie,/^__Host-jac_native_gmail=/);assert.match(cookie,/HttpOnly; Secure; SameSite=Lax/);assert.ok(!cookie.includes('__Host-jac_session'));
 const state=new URL(location).searchParams.get('state');
 return {...result.body,ticket,state,cookie:cookie.split(';')[0],google:new URL(location)};
}
function request(context,cookie=context.cookie,query='code=simulated-code'){
 return new Request(m.GMAIL_CALLBACK+'?state='+context.state+'&'+query,{headers:cookie?{cookie}:undefined});
}

test('Gmail nativo requiere propietario, origen y sesión real; ticket no entrega sesión al navegador',async()=>{
 await m.saveMailCredentials('simulated.apps.googleusercontent.com','simulated-secret');
 assert.equal((await start('')).status,401);
 const now=new Date().toISOString(),reader='oauth-reader';
 sql.prepare('INSERT INTO payroll_users (id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run(reader,reader,reader+'@example.invalid','Lector de prueba',m.hashPassword('1',globalThis.__nativeOauthEnv.PAYROLL_AUTH_KEY),'["send"]',now,now);
 assert.equal((await start(await m.makeSession(reader))).status,403);
 const token=await m.makeSession(owner);assert.equal((await start(token,'https://other.example.invalid')).status,403);
 const context=await handoff(token);
 assert.match(context.nonce,/^[A-Za-z0-9_-]{43}$/);assert.ok(!JSON.stringify(context).includes(token));
 assert.equal(context.google.searchParams.get('redirect_uri'),m.GMAIL_CALLBACK);assert.equal(context.google.searchParams.get('code_challenge_method'),'S256');
 assert.equal(calls.length,0,'Preparar la autorización no llama a Google ni envía correo');
 assert.equal((await m.api.GET(new Request(context.url))).status,400,'El ticket es de un solo uso');
 assert.equal((await m.api.GET(new Request(m.GMAIL_CALLBACK.replace('/api/payroll/gmail/callback','/api/mobile/gmail')+'?ticket=invalid'))).status,400);
 const noGuard=await m.finishNativeMailOauth(request(context,''));assert.equal(new URL(noGuard.url).searchParams.get('result'),'error');assert.equal(calls.length,0);
 assert.ok(sql.prepare('SELECT id FROM payroll_oauth WHERE id=?').get('native:'+context.state),'Un navegador sin guard no consume la autorización válida');
 const callback=await m.callback.GET(request(context));assert.equal(callback.status,303);
 const destination=new URL(callback.headers.get('location'));assert.equal(destination.protocol,'jacnomina:');assert.equal(destination.host,'gmail');assert.equal(destination.searchParams.get('nonce'),context.nonce);assert.equal(destination.searchParams.get('result'),'connected');
 assert.equal(callback.headers.get('referrer-policy'),'no-referrer');assert.ok(!callback.headers.get('location').includes('simulated-access'));assert.ok(!callback.headers.get('location').includes('simulated-code'));
 assert.equal(calls.length,2);const exchanged=new URLSearchParams(calls[0].options.body);assert.equal(exchanged.get('code'),'simulated-code');assert.equal(exchanged.get('redirect_uri'),m.GMAIL_CALLBACK);assert.match(exchanged.get('code_verifier'),/^[A-Za-z0-9_-]{43}$/);
 assert.equal(await m.finishNativeMailOauth(request(context)),null,'El callback nativo solo se canjea una vez');assert.equal(calls.length,2);
 assert.equal((await m.mailConnection()).connected,true);
 const row=sql.prepare('SELECT credentials FROM payroll_gmail').get();assert.ok(!row.credentials.includes('simulated-refresh'),'Los tokens se conservan cifrados');
 await m.disconnectMail();assert.equal((await m.mailConnection()).connected,false);
});

test('expiración, revocación y cancelación impiden conectar Gmail desde una autorización vieja',async()=>{
 calls=[];const token=await m.makeSession(owner);
 const expiredStart=await start(token),ticket=new URL(expiredStart.body.url).searchParams.get('ticket');
 sql.prepare('UPDATE payroll_oauth SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z','handoff:'+m.tokenHash(ticket));
 assert.equal((await m.api.GET(new Request(expiredStart.body.url))).status,400);
 const expiredCallback=await handoff(token);sql.prepare('UPDATE payroll_oauth SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z','native:'+expiredCallback.state);
 assert.equal(new URL((await m.finishNativeMailOauth(request(expiredCallback))).url).searchParams.get('result'),'error');assert.equal(calls.length,0);
 const cancelled=await handoff(token);assert.equal(new URL((await m.finishNativeMailOauth(request(cancelled,cancelled.cookie,'error=access_denied'))).url).searchParams.get('result'),'error');assert.equal(calls.length,0);
 const revokedHandoff=await start(token);sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(token));
 assert.equal((await m.api.GET(new Request(revokedHandoff.body.url))).status,400);
 const replacement=await m.makeSession(owner),revokedCallback=await handoff(replacement);
 sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(owner);
 assert.equal(new URL((await m.finishNativeMailOauth(request(revokedCallback))).url).searchParams.get('result'),'error');assert.equal(calls.length,0,'Revocar la sesión impide canjear el código');
 assert.equal((await m.mailConnection()).connected,false);
});


test('administrador delegado conecta Gmail nativo; revocar el rol bloquea un callback pendiente',async()=>{
 const id=crypto.randomUUID(),now=new Date().toISOString();
 sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run(id,'delegate-native','delegate-native@example.invalid','Administrador ficticio',m.hashPassword('fixture',globalThis.__nativeOauthEnv.PAYROLL_AUTH_KEY),JSON.stringify([m.ADMINISTRATOR_ROLE]),now,now);
 const token=await m.makeSession(id);calls=[];const context=await handoff(token);
 assert.equal(calls.length,0);const callback=await m.callback.GET(request(context));assert.equal(new URL(callback.headers.get('location')).searchParams.get('result'),'connected');assert.equal(calls.length,2);
 const revoked=await handoff(token);calls=[];sql.prepare('UPDATE payroll_users SET permissions=? WHERE id=?').run('[]',id);
 assert.equal(new URL((await m.finishNativeMailOauth(request(revoked))).url).searchParams.get('result'),'error');assert.equal(calls.length,0);assert.equal((await start(token)).status,403);
});


test('Gmail nativo acepta sesión persistente antigua sin prolongar tickets OAuth',async()=>{
 const id=sql.prepare('SELECT id FROM payroll_users WHERE owner=1').get().id,token=await m.makeSession(id,true);
 sql.prepare('UPDATE payroll_sessions SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z',m.tokenHash(token));
 const context=await handoff(token);calls=[];
 const result=await m.finishNativeMailOauth(request(context));assert.equal(new URL(result.url).searchParams.get('result'),'connected');assert.equal(calls.length,2);
 await m.revokeSession(token);assert.equal((await start(token)).status,401);
});
