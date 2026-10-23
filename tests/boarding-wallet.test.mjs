import {test,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {build} from 'esbuild';
import {mkdtemp,readFile,readdir,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

// Disposable D1/R2 and independent encryption keys. Signing is intercepted so
// these cases isolate HTTP/access/CAS races; the core suite checks real CMS/ZIP.
// No real Apple certificate, mailbox, push registration or user file is used.
const sql=new DatabaseSync(':memory:');
for(const file of (await readdir('drizzle')).filter(file=>file.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+file,'utf8'));
let beforeFirst,beforeRun,beforeGet,normalizeHook,signHook,m;
class Query{
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const query=sql.prepare(this.text);return query.columns().length?{results:query.all(...this.args),meta:{changes:0}}:{results:[],meta:{changes:Number(query.run(...this.args).changes)}};}
 async run(){await beforeRun?.(this);return this.execute();}
 async all(){return this.execute();}
 async first(){await beforeFirst?.(this);return sql.prepare(this.text).get(...this.args)||null;}
}
const bucket=new Map(),calls=[],signatures=[];
globalThis.__walletTestEnv={DB:{prepare:sql=>new Query(sql),batch:async queries=>{sql.exec('BEGIN');try{const result=queries.map(query=>query.execute());sql.exec('COMMIT');return result;}catch(error){sql.exec('ROLLBACK');throw error;}}},BUCKET:{get:async key=>{await beforeGet?.(key);const value=bucket.get(key);return value?{body:new Response(value).body}:null;}},PAYROLL_AUTH_KEY:'wallet-authentication-test-only-independent-key',PAYROLL_MAIL_KEY:Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url')};
globalThis.__walletTestHeaders=new Headers();
const fakeCredentials={teamId:'TESTTEAM01',passTypeId:'pass.invalid.jac.boarding',certificate:'SYNTHETIC_CERTIFICATE_ONLY',privateKey:'SYNTHETIC_PRIVATE_KEY_ONLY',wwdr:'SYNTHETIC_WWDR_ONLY',expiresAt:new Date(Date.now()+86400000).toISOString()};
const fakePass=Uint8Array.from([80,75,3,4,10,20,30,40]);
globalThis.__walletTestCore={
 normalize:async input=>{await normalizeHook?.(input);if(input.p12==='INVALID_CERTIFICATE')throw new m.NoticeFailure('El certificado de Wallet no es válido.');return {...fakeCredentials,teamId:input.teamId,passTypeId:input.passTypeId};},
 barcode:input=>{if(!['PKBarcodeFormatQR','PKBarcodeFormatPDF417','PKBarcodeFormatAztec'].includes(input.format)||!/^M[1-4][\x20-\x7e]{58,4094}$/.test(input.message))throw new m.NoticeFailure('El código del pase no es compatible con Wallet.');return {format:input.format,message:input.message};},
 sign:async(credentials,input)=>{signatures.push({credentials,input});await signHook?.();return fakePass;},
};
const compiled=await build({stdin:{contents:"export * as api from './app/api/notices/wallet/route';export * from './lib/boarding-wallet-store';export * from './lib/notifications-core';export * from './lib/notifications';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-mail-core';export {mailKey} from './lib/payroll-mail';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'wallet-test-runtime',setup(b){
 b.onResolve({filter:/boarding-wallet-core$/},()=>({path:'wallet-core',namespace:'fixture'}));
 b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},args=>({path:args.path,namespace:'fixture'}));
 b.onLoad({filter:/.*/,namespace:'fixture'},args=>({loader:'js',contents:args.path==='cloudflare:workers'?'export const env=globalThis.__walletTestEnv;export const waitUntil=()=>{throw new Error("No background delivery is allowed in Wallet tests");};':args.path==='next/headers'?'export const headers=async()=>globalThis.__walletTestHeaders;':'export const normalizeWalletCredentials=(x)=>globalThis.__walletTestCore.normalize(x);export const validateWalletBarcode=(x)=>globalThis.__walletTestCore.barcode(x);export const buildBoardingWalletPass=(c,x)=>globalThis.__walletTestCore.sign(c,x);'}));
}}]});
const temp=await mkdtemp(resolve('work/wallet-server-tests-')),modulePath=temp+'/module.mjs';
await writeFile(modulePath,compiled.outputFiles[0].contents);m=await import(pathToFileURL(modulePath).href);await rm(temp,{recursive:true});
const owner=await m.bootstrapOwner('wallet-owner-fixture','independent-local-password');
const reader=sql.prepare('SELECT id FROM payroll_users WHERE email=?').get('info@jacmusic.co').id;
const other=sql.prepare('SELECT id FROM payroll_users WHERE email=?').get('contabilidad@jacmusic.co').id;
for(const [id,name] of [[reader,'Reader'],[other,'Other']])sql.prepare('UPDATE payroll_users SET email=?,name=?,password_hash=?,permissions=?,section_access=? WHERE id=?').run(name.toLowerCase()+'@example.invalid',name,m.hashPassword('independent-local-password',globalThis.__walletTestEnv.PAYROLL_AUTH_KEY),'[]','["boarding"]',id);
let ownerToken,readerToken,otherToken;
const base='https://wallet.example.invalid';
const original=new TextEncoder().encode('%PDF-1.4\n% Synthetic boarding document, not a real ticket.\n%%EOF');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const noticeId='33333333-3333-4333-8333-333333333333',fileId='44444444-4444-4444-8444-444444444444',sourceKey='private-fixture-boarding-source';
const message='M1'+'FAKE FIXTURE PASSENGER'.padEnd(58,' ');
const createInput=()=>({action:'create',id:noticeId,file:fileId,revision:1,sourceSha256:digest(original),barcode:{format:'PKBarcodeFormatPDF417',message}});
const bcbpLeg=({origin='BOG',destination='MDE',seat='012A',variable=''}={})=>'DEMO123'+origin+destination+'XX '+'00123'+'100'+'Y'+seat+'00001'+'1'+variable.length.toString(16).toUpperCase().padStart(2,'0')+variable;
const bcbp=(legs=[bcbpLeg()])=>'M'+legs.length+'TRAVELLER/FIXTURE'.padEnd(20,' ')+'E'+legs.join('');
const emptyDetails=()=>({passenger:'',origin:'',destination:'',departureTime:'',boardingTime:'',seat:''});
const currentVersion=()=>sql.prepare('SELECT version FROM jac_notice_settings WHERE id=?').get('jac').version;
const configureInput=()=>({action:'configure',version:currentVersion(),teamId:'TESTTEAM01',passTypeId:'pass.invalid.jac.boarding',p12:'SYNTHETIC_PKCS12_ONLY',password:'SYNTHETIC_PASSWORD_ONLY',wwdr:'SYNTHETIC_INTERMEDIATE_ONLY'});
async function request(token,{body,raw,method=body||raw?'POST':'GET',origin=base,headers={}}={}){
 const cookie=token?'__Host-jac_session='+token:'';globalThis.__walletTestHeaders=new Headers({cookie,host:'wallet.example.invalid'});
 const req=new Request(base+'/api/notices/wallet',{method,headers:{cookie,origin,'Content-Type':'application/json',...headers},...(method==='POST'?{body:raw??JSON.stringify(body)}:{})});
 const response=await m.api[method](req),type=response.headers.get('content-type')??'';
 return {response,status:response.status,body:type.includes('application/json')?await response.json():new Uint8Array(await response.arrayBuffer())};
}
async function setKeys(keys){sql.prepare('UPDATE jac_notice_settings SET credentials=? WHERE id=?').run(await m.encryptMail(keys,m.mailKey()),'jac');}
const originalKeys=()=>({apns:{teamId:'KEEPTEAM01',keyId:'KEEPKEY001',privateKey:'KEEP_APNS_FIXTURE_ONLY'},slack:{token:'KEEP_SLACK_FIXTURE_ONLY',signingSecret:'KEEP_SLACK_SECRET_ONLY'},web:{publicKey:'KEEP_WEB_FIXTURE_ONLY',privateKey:{kty:'EC',d:'KEEP_WEB_PRIVATE_FIXTURE_ONLY'}}});
beforeEach(async()=>{
 beforeFirst=beforeRun=beforeGet=normalizeHook=signHook=undefined;signatures.length=0;calls.length=0;bucket.clear();
 sql.exec('DELETE FROM payroll_sessions;DELETE FROM jac_notice_recipients;DELETE FROM jac_notice_attachments;DELETE FROM jac_notices;DELETE FROM jac_notice_settings;');
 sql.prepare('UPDATE payroll_users SET active=1,section_access=? WHERE id IN (?,?)').run('["boarding"]',reader,other);
 sql.prepare('UPDATE payroll_users SET name=? WHERE id=?').run('Reader',reader);
 ownerToken=await m.makeSession(owner);readerToken=await m.makeSession(reader);otherToken=await m.makeSession(other);
 sql.prepare('INSERT INTO jac_notice_settings(id,credentials,version) VALUES (?,?,1)').run('jac',await m.encryptMail({...originalKeys(),wallet:{...fakeCredentials}},m.mailKey()));
 sql.prepare('INSERT INTO jac_notices(id,kind,title,filename,size,created_at,travel_date) VALUES (?,\'boarding_pass\',?,?,?,?,?)').run(noticeId,'Synthetic boarding fixture','',0,new Date().toISOString(),'2027-04-10');
 sql.prepare('INSERT INTO jac_notice_recipients(id,notice_id,user_id) VALUES (?,?,?)').run(noticeId+'|'+reader,noticeId,reader);
 sql.prepare("INSERT INTO jac_notice_attachments(id,notice_id,file_key,filename,mime_type,size,state,expires_at) VALUES (?,?,?,?,?,?,'ready',?)").run(fileId,noticeId,sourceKey,'Reader 10 de abril 2027 Pereira-Bogota.pdf','application/pdf',original.length,'2030-01-01T00:00:00Z');
 bucket.set(sourceKey,original);
 globalThis.fetch=async input=>{calls.push(String(input));throw new Error('Every outbound network request is blocked in Wallet tests.');};
});

test('Wallet HTTP access uses own sessions, owner-only configuration, same origin and bounded JSON without exposing signer material',async()=>{
 assert.equal((await request('')).status,401);
 sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',other);
 assert.equal((await request(otherToken)).status,403);
 assert.equal((await request(readerToken,{body:configureInput()})).status,403);
 assert.equal((await request(ownerToken,{body:configureInput(),origin:'https://untrusted.example.invalid'})).status,403);
 assert.equal((await request(ownerToken,{raw:'{not-json'})).status,400);
 assert.equal((await request(ownerToken,{raw:'[]'})).status,400);
 assert.equal((await request(ownerToken,{raw:'x'.repeat(200*1024+1)})).status,413);
 const status=await request(readerToken);assert.equal(status.status,200);assert.equal(status.body.configured,true);assert.equal(status.body.passTypeId,fakeCredentials.passTypeId);
 assert.deepEqual(Object.keys(status.body).sort(),['configured','expiresAt','passTypeId','version']);
 assert.match(status.response.headers.get('cache-control'),/private, no-store/);assert.equal(status.response.headers.get('vary'),'Cookie');
 assert.ok(!JSON.stringify(status.body).includes('SYNTHETIC'));assert.deepEqual(calls,[]);
});

test('Wallet credential updates encrypt only the normalized signer, preserve APNs Slack and Web keys, and reject stale versions and invalid certificates',async()=>{
 const input=configureInput(),before=await m.pushCredentials();
 const result=await request(ownerToken,{body:input});assert.equal(result.status,200);assert.equal(result.body.version,input.version+1);
 const after=await m.pushCredentials();for(const name of ['apns','slack','web'])assert.deepEqual(after[name],before[name]);
 assert.deepEqual(after.wallet,fakeCredentials);const plain=JSON.stringify(after);
 assert.ok(!plain.includes(input.password));assert.ok(!plain.includes(input.p12));
 const stored=sql.prepare('SELECT credentials FROM jac_notice_settings WHERE id=?').get('jac').credentials;assert.ok(!stored.includes(fakeCredentials.privateKey));assert.ok(!stored.includes('KEEP_APNS'));
 assert.equal((await request(ownerToken,{body:input})).status,409);
 const good=stored;assert.equal((await request(ownerToken,{body:{...configureInput(),p12:'INVALID_CERTIFICATE'}})).status,400);assert.equal(sql.prepare('SELECT credentials FROM jac_notice_settings WHERE id=?').get('jac').credentials,good);
 await setKeys({...after,wallet:{...fakeCredentials,expiresAt:'2000-01-01T00:00:00Z'}});assert.equal((await request(readerToken)).body.configured,false);assert.equal((await request(readerToken,{body:createInput()})).status,409);
 assert.deepEqual(calls,[]);
});

test('Only the private boarding recipient can create a revision and hash-bound pass; exact barcode bytes remain unchanged and no source is modified',async()=>{
 const input=createInput();assert.equal((await request(ownerToken,{body:input})).status,404);assert.equal((await request(otherToken,{body:input})).status,404);
 assert.equal((await request(readerToken,{body:{...input,sourceSha256:'0'.repeat(64)}})).status,409);
 assert.equal((await request(readerToken,{body:{...input,revision:2}})).status,409);
 assert.equal((await request(readerToken,{body:{...input,barcode:{format:'PKBarcodeFormatQR',message:'https://untrusted.example.invalid/not-a-boarding-pass'}}})).status,400);
 assert.equal((await request(readerToken,{body:{...input,barcode:{...input.barcode,format:'DataMatrix'}}})).status,400);
 const result=await request(readerToken,{body:input});assert.equal(result.status,200);assert.deepEqual(result.body,fakePass);assert.equal(result.response.headers.get('content-type'),'application/vnd.apple.pkpass');assert.match(result.response.headers.get('content-disposition'),/\.pkpass"$/);assert.match(result.response.headers.get('cache-control'),/private, no-store/);
 assert.equal(signatures.length,1);assert.equal(signatures[0].input.barcode.message,message);assert.equal(signatures[0].input.origin,'Pereira');assert.equal(signatures[0].input.destination,'Bogota');assert.equal(signatures[0].input.travelDate,'2027-04-10');assert.equal(signatures[0].input.passenger,'Reader');
 assert.match(signatures[0].input.serialNumber,/^JAC-[a-f0-9]{64}$/);assert.ok(!signatures[0].input.serialNumber.includes(reader));
 assert.deepEqual(bucket.get(sourceKey),original);assert.equal(sql.prepare('SELECT count(*) n FROM jac_push_deliveries').get().n,0);assert.deepEqual(calls,[]);
});

test('Wallet signs reviewed flight details while preserving the private source and exact original barcode',async()=>{
 const details={passenger:'Andrea Torres',origin:'Medellín · MDE',destination:'Bogotá · BOG',departureTime:'00:15',boardingTime:'23:40',seat:'12A'};
 const input={...createInput(),details,legIndex:0};
 assert.equal((await request(otherToken,{body:input})).status,404);
 assert.equal((await request(readerToken,{body:{...input,sourceSha256:'0'.repeat(64)}})).status,409);
 const result=await request(readerToken,{body:input});assert.equal(result.status,200);
 for(const [key,value] of Object.entries(details))assert.equal(signatures[0].input[key],value);
 assert.equal(signatures[0].input.barcode.message,message);assert.deepEqual(bucket.get(sourceKey),original);
 assert.deepEqual(calls,[]);
});

test('Wallet omitted details can use conservative source suggestions while explicit blanks suppress them and never become profile data',async()=>{
 const barcode={format:'PKBarcodeFormatPDF417',message:bcbp()};
 assert.equal((await request(readerToken,{body:{...createInput(),barcode}})).status,200);
 assert.equal(signatures[0].input.passenger,'FIXTURE TRAVELLER');assert.equal(signatures[0].input.origin,'BOG');assert.equal(signatures[0].input.destination,'MDE');assert.equal(signatures[0].input.seat,'12A');
 assert.equal(signatures[0].input.departureTime,undefined);assert.equal(signatures[0].input.boardingTime,undefined);
 assert.equal((await request(readerToken,{body:{...createInput(),barcode,details:emptyDetails()}})).status,200);
 for(const key of Object.keys(emptyDetails()))assert.equal(signatures[1].input[key],undefined,key+' stays intentionally blank');
 sql.prepare('UPDATE jac_notice_attachments SET filename=? WHERE id=?').run('unidentified-source.pdf',fileId);
 assert.equal((await request(readerToken,{body:createInput()})).status,200);
 assert.equal(signatures[2].input.passenger,undefined,'The authenticated profile is not the traveller identity.');assert.equal(signatures[2].input.origin,undefined);assert.equal(signatures[2].input.seat,undefined);
 assert.deepEqual(calls,[]);
});

test('Wallet selects multi-leg display data explicitly and old clients receive a compatible minimal copy',async()=>{
 const barcode={format:'PKBarcodeFormatPDF417',message:bcbp([bcbpLeg({variable:'ABCD'}),bcbpLeg({origin:'MDE',destination:'CTG',seat:'002F'})])};
 const input={...createInput(),barcode};
 assert.equal((await request(readerToken,{body:input})).status,200);
 assert.equal(signatures[0].input.passenger,'FIXTURE TRAVELLER');assert.equal(signatures[0].input.origin,undefined);assert.equal(signatures[0].input.destination,undefined);assert.equal(signatures[0].input.seat,undefined);
 assert.equal((await request(readerToken,{body:{...input,details:{}}})).status,400,'The new flow must choose its leg.');
 assert.equal((await request(readerToken,{body:{...input,legIndex:2}})).status,400);
 assert.equal((await request(readerToken,{body:{...input,legIndex:0,details:{}}})).status,200);
 assert.equal((await request(readerToken,{body:{...input,legIndex:1,details:{}}})).status,200);
 assert.equal(signatures[1].input.origin,'BOG');assert.equal(signatures[1].input.destination,'MDE');assert.equal(signatures[1].input.seat,'12A');
 assert.equal(signatures[2].input.origin,'MDE');assert.equal(signatures[2].input.destination,'CTG');assert.equal(signatures[2].input.seat,'2F');
 assert.equal(signatures[0].input.serialNumber,signatures[1].input.serialNumber);assert.notEqual(signatures[1].input.serialNumber,signatures[2].input.serialNumber);
 assert.equal(signatures[2].input.barcode.message,barcode.message);assert.deepEqual(calls,[]);
});

test('Wallet rejects unbounded, hidden or invalid reviewed details before signing',async()=>{
 for(const changes of [{departureTime:'24:00'},{boardingTime:'7:30'},{boardingTime:'17:60'},{seat:'12 A'},{seat:'0000'},{passenger:'a'.repeat(121)},{origin:'City\u202eOther'},{destination:'Line\nOther'},{departureTime:'14:30Z'},{unknown:'x'}]){
  const result=await request(readerToken,{body:{...createInput(),details:{...emptyDetails(),...changes}}});assert.equal(result.status,400);
 }
 for(const legIndex of [-1,4,0.5])assert.equal((await request(readerToken,{body:{...createInput(),legIndex}})).status,400);
 assert.equal(signatures.length,0);assert.deepEqual(calls,[]);
});

test('Credential configuration refuses revoked sessions during normalization and enforces SQL session and CAS guards at the write',async()=>{
 const before=sql.prepare('SELECT credentials FROM jac_notice_settings WHERE id=?').get('jac').credentials;
 normalizeHook=async()=>{sql.prepare('DELETE FROM payroll_sessions WHERE user_id=?').run(owner);};
 assert.equal((await request(ownerToken,{body:configureInput()})).status,403);assert.equal(sql.prepare('SELECT credentials FROM jac_notice_settings WHERE id=?').get('jac').credentials,before);
 normalizeHook=undefined;ownerToken=await m.makeSession(owner);
 beforeRun=async query=>{if(query.text.startsWith('UPDATE jac_notice_settings SET credentials=')){beforeRun=undefined;sql.prepare('DELETE FROM payroll_sessions WHERE user_id=?').run(owner);}};
 assert.equal((await request(ownerToken,{body:configureInput()})).status,403);assert.equal(sql.prepare('SELECT credentials FROM jac_notice_settings WHERE id=?').get('jac').credentials,before);
 ownerToken=await m.makeSession(owner);
 beforeRun=async query=>{if(query.text.startsWith('UPDATE jac_notice_settings SET credentials=')){beforeRun=undefined;sql.prepare('UPDATE jac_notice_settings SET version=version+1 WHERE id=?').run('jac');}};
 assert.equal((await request(ownerToken,{body:configureInput()})).status,409);assert.equal(sql.prepare('SELECT credentials FROM jac_notice_settings WHERE id=?').get('jac').credentials,before);
 assert.deepEqual(calls,[]);
});

test('Signing never releases a private pass after session permission recipient source revision deletion or signer configuration changes',async()=>{
 const cases=[
  [403,()=>sql.prepare('DELETE FROM payroll_sessions WHERE user_id=?').run(reader)],
  [403,()=>sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('[]',reader)],
  [403,()=>sql.prepare('UPDATE payroll_users SET name=? WHERE id=?').run('Changed actor during signing',reader)],
  [404,()=>sql.prepare('DELETE FROM jac_notice_recipients WHERE notice_id=?').run(noticeId)],
  [409,()=>sql.prepare('UPDATE jac_notices SET revision=revision+1 WHERE id=?').run(noticeId)],
  [404,()=>sql.prepare("UPDATE jac_notice_attachments SET state='deleted' WHERE id=?").run(fileId)],
  [409,()=>sql.prepare('UPDATE jac_notice_settings SET version=version+1 WHERE id=?').run('jac')],
 ];
 for(const [status,mutate] of cases){
  sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["boarding"]',reader);readerToken=await m.makeSession(reader);
  sql.prepare('UPDATE jac_notices SET revision=1 WHERE id=?').run(noticeId);sql.prepare("UPDATE jac_notice_attachments SET state='ready' WHERE id=?").run(fileId);
  sql.prepare('INSERT OR IGNORE INTO jac_notice_recipients(id,notice_id,user_id) VALUES (?,?,?)').run(noticeId+'|'+reader,noticeId,reader);
  signHook=async()=>{mutate();};const response=await request(readerToken,{body:createInput()});assert.equal(response.status,status);assert.ok(response.body.error);assert.equal(response.response.headers.get('content-type'),'application/json');
 }
 assert.deepEqual(calls,[]);
});

test('Final atomic gate closes recipient revocation races and source reads remain byte bounded before signing',async()=>{
 beforeFirst=async query=>{if(query.text.startsWith('SELECT 1 AS permitted FROM jac_notices wallet_notice')){beforeFirst=undefined;sql.prepare('DELETE FROM jac_notice_recipients WHERE notice_id=?').run(noticeId);}};
 assert.equal((await request(readerToken,{body:createInput()})).status,403);
 sql.prepare('INSERT INTO jac_notice_recipients(id,notice_id,user_id) VALUES (?,?,?)').run(noticeId+'|'+reader,noticeId,reader);signatures.length=0;
 bucket.set(sourceKey,new Uint8Array(10*1024*1024+1));
 assert.equal((await request(readerToken,{body:createInput()})).status,413);assert.equal(signatures.length,0);
 assert.deepEqual(calls,[]);
});
