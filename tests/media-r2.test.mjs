import test,{beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {build} from 'esbuild';

// Only in-memory D1 and a pinned, intercepted S3 endpoint. No real credentials.
const sql=new DatabaseSync(':memory:');
for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+name,'utf8'));
let beforeQuery;
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};return {results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async first(){await beforeQuery?.(this);return sql.prepare(this.text).get(...this.args)||null;}
 async run(){await beforeQuery?.(this);return {meta:{changes:Number(sql.prepare(this.text).run(...this.args).changes)}};}
}
globalThis.__r2Fixture={DB:{prepare:text=>new Query(text),batch:async queries=>{sql.exec('BEGIN');try{const out=queries.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},PAYROLL_AUTH_KEY:'separate-r2-fixture-auth-key-2026',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')};
globalThis.__r2Headers=new Headers();
const bundled=await build({stdin:{contents:"export * from './lib/media-r2';export * from './lib/media-drive';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export {decryptMail} from './lib/payroll-mail-core';export * as api from './app/api/media/storage/route';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'r2-fixtures',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__r2Fixture;':'export const headers=async()=>globalThis.__r2Headers;',loader:'js'}));}}]});
const dir=await mkdtemp(resolve('work/r2-fixture-')),file=dir+'/fixture.mjs';await writeFile(file,bundled.outputFiles[0].contents);const m=await import(pathToFileURL(file).href);await rm(dir,{recursive:true});
const ownerID=await m.bootstrapOwner('separate-r2-owner-fixture','fixture'),reader=crypto.randomUUID(),stamp=new Date().toISOString();
sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)').run(reader,'photo-r2','photo@example.invalid','Fotógrafo ficticio','fixture','[]',1,stamp,stamp);
const input={accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64),version:0};
let token,readerToken,calls,hook;
beforeEach(async()=>{
 beforeQuery=undefined;hook=undefined;calls=[];sql.exec('DELETE FROM jac_media_r2_connection');sql.prepare('UPDATE payroll_users SET active=1 WHERE id=?').run(ownerID);
 token=await m.makeSession(ownerID);readerToken=await m.makeSession(reader);
 sql.prepare("INSERT OR REPLACE INTO jac_media_connection(id,credentials,email,version,updated_at) VALUES('jac','unchanged-drive-cipher','jacmusicestudios@gmail.com',7,?)").run(stamp);
 globalThis.fetch=async(request,options={})=>{assert.ok(request instanceof Request);assert.equal(request.url,'https://'+'1'.repeat(32)+'.r2.cloudflarestorage.com/jac-fotografia');assert.equal(request.method,'HEAD');assert.equal(request.redirect,'manual');assert.equal(options.redirect,'manual');assert.equal(request.headers.has('cookie'),false);assert.equal(request.headers.has('origin'),false);assert.ok(request.headers.get('authorization').startsWith('AWS4-HMAC-SHA256 Credential='));calls.push({request,options});return hook?hook():new Response(null,{status:200});};
});
function req(body,session=token,origin='https://r2.example.invalid'){
 const headers={cookie:'__Host-jac_session='+session,origin,'content-type':'application/json'};globalThis.__r2Headers=new Headers({host:'r2.example.invalid',...headers});
 return new Request('https://r2.example.invalid/api/media/storage',body===undefined?{headers}:{method:'POST',headers,body:typeof body==='string'?body:JSON.stringify(body)});
}
async function post(body=input,session=token,origin){return m.api.POST(req(body,session,origin));}
const row=()=>sql.prepare("SELECT * FROM jac_media_r2_connection WHERE id='jac'").get();

test('R2 credentials are encrypted, redacted and staged without replacing Drive',async()=>{
 const response=await post();assert.equal(response.status,200);const publicState=await response.json();assert.deepEqual(publicState,{configured:true,active:false,version:1,accountId:input.accountId,bucket:input.bucket});
 const saved=row();assert.equal(saved.enabled,0);assert.ok(saved.credentials&&!saved.credentials.includes(input.secretAccessKey)&&!saved.credentials.includes(input.accessKeyId));assert.deepEqual(await m.decryptMail(saved.credentials,globalThis.__r2Fixture.PAYROLL_MAIL_KEY),{accountId:input.accountId,bucket:input.bucket,accessKeyId:input.accessKeyId,secretAccessKey:input.secretAccessKey});
 assert.equal(sql.prepare("SELECT credentials FROM jac_media_connection WHERE id='jac'").get().credentials,'unchanged-drive-cipher');
 const read=await m.api.GET(req());assert.deepEqual(await read.json(),publicState);assert.equal(read.headers.get('cache-control'),'private, no-store, max-age=0');assert.equal(calls.length,1);
});
test('photographer, forged origin and missing session cannot inspect or configure R2',async()=>{
 assert.equal((await post(input,readerToken)).status,403);assert.equal((await m.api.GET(req(undefined,readerToken))).status,403);
 assert.equal((await post(input,token,'https://attacker.invalid')).status,403);assert.equal((await post(input,'invalid')).status,401);assert.equal(calls.length,0);assert.equal(row(),undefined);
});
test('S3 credentials stay on the pinned host and redirects are rejected',async()=>{
 hook=()=>new Response(null,{status:307,headers:{location:'https://attacker.invalid'}});assert.equal((await post()).status,502);assert.equal(calls.length,1);assert.equal(row(),undefined);
 const request=m.mediaR2BucketRequest(input,new Date('2026-10-16T12:34:56.000Z'));assert.equal(request.headers.get('x-amz-date'),'20261016T123456Z');assert.match(request.headers.get('authorization'),/\/20261016\/auto\/s3\/aws4_request/);assert.ok(!request.url.includes(input.accessKeyId)&&!request.url.includes(input.secretAccessKey));
});
test('revocation during the S3 check prevents the encrypted save',async()=>{
 hook=()=>{sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(ownerID);return new Response(null,{status:200});};assert.equal((await post()).status,403);assert.equal(row(),undefined);
});
test('SQL guard also prevents a save when authorization changes immediately before commit',async()=>{
 let fired=false;beforeQuery=q=>{if(!fired&&q.text.startsWith('INSERT INTO jac_media_r2_connection')){fired=true;sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(ownerID);}};
 assert.equal((await post()).status,409);assert.equal(row(),undefined);assert.equal(fired,true);
});
test('concurrent credentials and stale editors cannot overwrite a newer connection',async()=>{
 assert.equal((await post()).status,200);const initial=row();assert.equal((await post()).status,409);assert.equal(row().credentials,initial.credentials);
 hook=()=>{sql.exec("UPDATE jac_media_r2_connection SET version=version+1 WHERE id='jac'");return new Response(null,{status:200});};assert.equal((await post({...input,version:1})).status,409);assert.equal(row().credentials,initial.credentials);
});
test('credential rotation is versioned and an active gallery cannot be blindly repointed',async()=>{
 assert.equal((await post()).status,200);assert.equal((await post({...input,version:1,secretAccessKey:'4'.repeat(64)})).status,200);assert.equal(row().version,2);
 sql.exec("UPDATE jac_media_r2_connection SET enabled=1 WHERE id='jac'");assert.equal((await post({...input,version:2})).status,409);assert.equal(row().version,2);
});
test('foreign URLs, bucket names, oversized requests and malformed secrets never reach S3',async()=>{
 for(const override of [{accountId:'https://attacker.invalid'},{bucket:'payroll'},{bucket:'jac-fotografia/path'},{accessKeyId:'bad\nheader'},{secretAccessKey:'a'},{version:-1}])assert.ok((await post({...input,...override})).status>=400);
 assert.equal((await post('x'.repeat(8193))).status,413);assert.equal(calls.length,0);assert.equal(row(),undefined);
});
test('S3 permission and temporary failures preserve the previous connection and redact keys',async()=>{
 for(const status of [403,404,429,503]){hook=()=>new Response(null,{status});const response=await post(),body=await response.text();assert.ok(response.status>=400);assert.ok(!body.includes(input.secretAccessKey)&&!body.includes(input.accessKeyId));assert.equal(row(),undefined);}
});
