import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {generateKeyPairSync,privateDecrypt,createDecipheriv,constants,createHash} from 'node:crypto';
import {build} from 'esbuild';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const dir=await mkdtemp(join(tmpdir(),'jac-transfer-test-')),out=join(dir,'module.mjs');
await build({stdin:{contents:"export * from './lib/hosting-transfer';export * from './lib/hosting-cutover';export {POST as sourceApi} from './app/api/hosting-transfer/route';export {POST as inventoryApi} from './app/api/hosting-transfer-inventory/route';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',outfile:out,plugins:[{name:'fake',setup(b){
 b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fake'}));
 b.onResolve({filter:/^@\/lib\/payroll-auth-store$/},()=>({path:'auth',namespace:'fake'}));
 b.onLoad({filter:/.*/,namespace:'fake'},a=>({contents:a.path==='env'?'export const env=globalThis.__transferTestEnv;':'export const OWNER_EMAIL="camilo@mac2you.co";export async function authenticatedSession(token){return globalThis.__transferUsers.get(token)||null;}'}));
}}]});
globalThis.__transferTestEnv={};globalThis.__transferUsers=new Map();const m=await import(pathToFileURL(out));
const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const jwk={...publicKey.export({format:'jwk'}),alg:'RSA-OAEP-256',key_ops:['encrypt'],ext:true};
const token='t'.repeat(43),expiry=()=>new Date(Date.now()+600000).toISOString();
function open(v){const key=privateDecrypt({key:privateKey,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(v.key,'base64')),bytes=Buffer.from(v.data,'base64'),d=createDecipheriv('aes-256-gcm',key,Buffer.from(v.iv,'base64'));d.setAuthTag(bytes.subarray(-16));return JSON.parse(Buffer.concat([d.update(bytes.subarray(0,-16)),d.final()]).toString());}
function setup(){
 const sql=new DatabaseSync(':memory:');sql.exec('CREATE TABLE payroll_users(id TEXT PRIMARY KEY,email TEXT,owner INTEGER,active INTEGER);CREATE TABLE records(id INTEGER PRIMARY KEY AUTOINCREMENT,value TEXT);INSERT INTO records(value) VALUES (\'Ficticio\');');
 const db={prepare(query){let args=[];return {bind(...v){args=v;return this;},async all(){return {results:sql.prepare(query).all(...args)};},async first(){return sql.prepare(query).get(...args)||null;},async run(){const result=sql.prepare(query).run(...args);return {meta:{changes:Number(result.changes)}};}};},async batch(statements){sql.exec('BEGIN');try{const result=[];for(const s of statements)result.push(await s.all());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
 const bytes=Buffer.alloc(1024*1024+7,42),objects=new Map([['private/id.pdf',{bytes,httpMetadata:{contentType:'application/pdf'},customMetadata:{name:'Prueba ñ'},etag:'old'}]]);let afterGet=()=>{};
 const bucket={async list(){return {objects:[...objects].map(([key,o])=>({key,size:o.bytes.length,etag:o.etag})),truncated:false};},async get(key,options){const o=objects.get(key);if(!o)return null;if(options.onlyIf.etagMatches!==o.etag)return {etag:o.etag};const bytes=o.bytes.subarray(options.range.offset,options.range.offset+options.range.length);afterGet();return {body:true,key,size:o.bytes.length,etag:o.etag,httpMetadata:o.httpMetadata,customMetadata:o.customMetadata,arrayBuffer:async()=>Uint8Array.from(bytes).buffer};},async put(key,body,options){const bytes=Buffer.from(await new Response(body).arrayBuffer());if(createHash('sha256').update(bytes).digest('hex')!==Buffer.from(options.sha256).toString('hex'))throw Error('checksum');objects.set(key,{bytes,...options,etag:'new'});return {size:bytes.length};}};
 const env={DB:db,BUCKET:bucket,JAC_TRANSFER_TOKEN:token,JAC_TRANSFER_EXPIRES:expiry(),JAC_TRANSFER_PUBLIC_KEY:JSON.stringify(jwk),PAYROLL_AUTH_KEY:'fake-auth-key-'.repeat(4),PAYROLL_MAIL_KEY:'fake-mail-key-'.repeat(4)};
 return {env,sql,objects,setAfterGet(fn){afterGet=fn;}};
}
function req(value,{source=false,auth=token,origin=source?'https://source.example.invalid':null}={}){return new Request((source?'https://source.example.invalid/api/hosting-transfer':'https://target.example.invalid/_jac/transfer'),{method:'POST',headers:{'Content-Type':'application/json',...(origin?{Origin:origin}:{}),...(auth?{Authorization:'Bearer '+auth}:{})},body:JSON.stringify(value)});}
test.after(async()=>{await rm(dir,{recursive:true,force:true});});
test('el corte bloquea toda operación del origen y deja la copia privada sin afectar al destino',()=>{
 for(const path of ['/api/payroll','/api/notices/slack','/api/calendar','/api/media/upload','/crm','/acceso']){
  const request=new Request('https://source.example.invalid'+path,{method:path.startsWith('/api/')?'POST':'GET'});
  assert.equal(m.frozenOriginResponse(request,{JAC_ORIGIN_FROZEN:'1'}).status,503);
  assert.equal(m.frozenOriginResponse(request,{}),null);assert.equal(m.frozenOriginResponse(request,{JAC_ORIGIN_FROZEN:'1',JAC_HOSTING:'cloudflare'}),null);
 }
 for(const path of ['/migracion','/api/hosting-transfer','/api/hosting-transfer-inventory','/assets/client-123.js'])assert.equal(m.frozenOriginResponse(new Request('https://source.example.invalid'+path),{JAC_ORIGIN_FROZEN:'1'}),null);
 assert.equal(m.frozenOriginResponse(new Request('https://source.example.invalid/assets/../api/payroll'),{JAC_ORIGIN_FROZEN:'1'}).status,503);
});
test('el origen exige sesión vigente del fundador, mismo origen, clave pública fijada y plazo acotado',async()=>{
 const {env,sql}=setup();
 for(const [e,request,guard] of [[env,req({action:'secrets'},{source:true}),async()=>false],[env,req({action:'secrets'},{source:true,origin:'https://evil.invalid'}),async()=>true],[{...env,JAC_TRANSFER_EXPIRES:'2000-01-01'},req({action:'secrets'},{source:true}),async()=>true],[{...env,JAC_TRANSFER_EXPIRES:new Date(Date.now()+3*3600000).toISOString()},req({action:'secrets'},{source:true}),async()=>true]]){
  const r=await m.sourceTransfer(request,e,guard);assert.equal(r.status,404);assert.equal(await r.text(),'');
 }
 const r=await m.sourceTransfer(req({action:'secrets'},{source:true}),env,async()=>true);assert.equal(r.status,200);const cipher=await r.text();assert.ok(!cipher.includes(env.PAYROLL_AUTH_KEY));assert.deepEqual(open(JSON.parse(cipher)).values,{PAYROLL_AUTH_KEY:env.PAYROLL_AUTH_KEY,PAYROLL_MAIL_KEY:env.PAYROLL_MAIL_KEY});sql.close();
});
test('una sesión administrativa de jac no sustituye la sesión del fundador',async()=>{
 const {env,sql}=setup();Object.assign(globalThis.__transferTestEnv,env);sql.prepare('INSERT INTO payroll_users VALUES (?,?,?,1)').run('owner','camilo@mac2you.co',1);
 globalThis.__transferUsers.set('founder',{id:'owner',email:'camilo@mac2you.co'});globalThis.__transferUsers.set('jac',{id:'jac',email:'jac@example.invalid',isOwner:true});
 const call=async(cookie)=>{const r=req({action:'secrets'},{source:true});r.headers.set('Cookie','__Host-jac_session='+cookie);return m.sourceApi(r);};
 assert.equal((await call('jac')).status,404);assert.equal((await call('founder')).status,200);sql.close();
});
test('la base y las secuencias se cifran sin modificar el origen',async()=>{
 const {env,sql}=setup();const r=await m.sourceTransfer(req({action:'database'},{source:true}),env,async()=>true),data=open(await r.json());assert.equal(data.kind,'database');assert.deepEqual(data.tables.find(t=>t.name==='records').rows,[{id:1,value:'Ficticio'}]);assert.ok(data.sequences.some(s=>s.name==='records'&&s.seq===1));assert.equal(sql.prepare('SELECT count(*) n FROM records').get().n,1);sql.close();
});
test('los contadores internos no se copian y una tabla vacía conserva su siguiente identificador',async()=>{
 const {env,sql}=setup();sql.exec('CREATE TABLE d1_migrations(id INTEGER PRIMARY KEY AUTOINCREMENT);INSERT INTO d1_migrations DEFAULT VALUES;CREATE TABLE __appgarden_migrations(id INTEGER PRIMARY KEY);INSERT INTO __appgarden_migrations VALUES (1);DELETE FROM records;UPDATE sqlite_sequence SET seq=71 WHERE name=\'records\';');
 const copy=open(await (await m.sourceTransfer(req({action:'database'},{source:true}),env,async()=>true)).json());assert.ok(!copy.sequences.some(s=>s.name==='d1_migrations'));assert.ok(!copy.tables.some(t=>t.name==='__appgarden_migrations'));assert.equal(sql.prepare('SELECT count(*) n FROM __appgarden_migrations').get().n,1);
 sql.exec('DELETE FROM sqlite_sequence WHERE name=\'records\';');assert.equal((await m.targetTransfer(req({action:'sequences',sequences:copy.sequences}),env)).status,200);
 sql.exec("INSERT INTO records(value) VALUES ('Nuevo ficticio');");assert.equal(sql.prepare('SELECT id FROM records').get().id,72);sql.close();
});
test('el inventario privado exige fundador, origen y plazo y revalida al terminar',async()=>{
 const {env,sql}=setup();Object.assign(globalThis.__transferTestEnv,env);sql.prepare('INSERT INTO payroll_users VALUES (?,?,?,1)').run('owner','camilo@mac2you.co',1);globalThis.__transferUsers.set('inventory-founder',{id:'owner',email:'camilo@mac2you.co'});
 const call=(origin='https://source.example.invalid',cookie='inventory-founder')=>{const r=req({},{source:true,origin});r.headers.set('Cookie','__Host-jac_session='+cookie);return m.inventoryApi(r);};
 assert.equal((await call()).status,200);assert.equal((await call('https://evil.invalid')).status,404);assert.equal((await call(undefined,'jac')).status,404);
 globalThis.__transferTestEnv.BUCKET={async list(){sql.exec('UPDATE payroll_users SET active=0');return {objects:[],truncated:false};}};assert.equal((await call()).status,404);sql.close();
});
test('los documentos conservan revisión y rango, y una revocación impide entregar el resultado',async()=>{
 const {env,sql,setAfterGet}=setup();
 const first=open(await (await m.sourceTransfer(req({action:'object',key:'private/id.pdf',etag:'old',offset:0},{source:true}),env,async()=>true)).json());assert.equal(Buffer.from(first.bytes,'base64').length,1024*1024);assert.equal(first.size,1024*1024+7);
 assert.equal((await m.sourceTransfer(req({action:'object',key:'private/id.pdf',etag:'changed',offset:0},{source:true}),env,async()=>true)).status,409);
 let allowed=true;setAfterGet(()=>{allowed=false;});assert.equal((await m.sourceTransfer(req({action:'object',key:'private/id.pdf',etag:'old',offset:0},{source:true}),env,async()=>allowed)).status,404);sql.close();
});
test('el destino exige capacidad temporal y se bloquea para siempre al activar la aplicación',async()=>{
 const {env,sql}=setup();for(const [e,request] of [[env,req({action:'clear',confirmation:'jac-nomina-staging'},{auth:'wrong'})],[{...env,JAC_READY:'1'},req({action:'clear',confirmation:'jac-nomina-staging'})],[{...env,JAC_TRANSFER_EXPIRES:'2000-01-01'},req({action:'clear',confirmation:'jac-nomina-staging'})]])assert.equal((await m.targetTransfer(request,e)).status,404);
 assert.equal(sql.prepare('SELECT count(*) n FROM records').get().n,1);
 assert.equal((await m.targetTransfer(req({action:'clear',confirmation:'wrong'}),env)).status,409);assert.equal((await m.targetTransfer(req({action:'rows',table:'records;DROP TABLE payroll_users',rows:[]}),env)).status,409);sql.close();
});
test('la copia comprueba filas, huellas y checksum, y mantiene metadatos UTF-8',async()=>{
 const {env,sql,objects}=setup();assert.equal((await m.targetTransfer(req({action:'clear',confirmation:'jac-nomina-staging'}),env)).status,200);
 assert.equal((await m.targetTransfer(req({action:'rows',table:'records',rows:[{id:9,value:'Otro ficticio'}]}),env)).status,200);
 const hashes=await (await m.targetTransfer(req({action:'fingerprints'}),env)).json();assert.equal(hashes.tables.find(t=>t.name==='records').count,1);assert.equal(sql.prepare('SELECT value FROM records WHERE id=9').get().value,'Otro ficticio');
 const bytes=Buffer.from('PDF ficticio'),sha=createHash('sha256').update(bytes).digest('hex'),metadata={httpMetadata:{contentType:'application/pdf'},customMetadata:{name:'Prueba ñ'}};
 const request=()=>new Request('https://target.example.invalid/_jac/transfer?action=object&key=copia.pdf',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Length':String(bytes.length),'X-JAC-SHA256':sha,'X-JAC-Metadata':Buffer.from(JSON.stringify(metadata)).toString('base64')},body:bytes});
 const corrupted=request();corrupted.headers.set('X-JAC-SHA256','0'.repeat(64));assert.equal((await m.targetTransfer(corrupted,env)).status,409);assert.ok(!objects.has('copia.pdf'));
 assert.equal((await m.targetTransfer(request(),env)).status,200);assert.equal(objects.get('copia.pdf').customMetadata.name,'Prueba ñ');sql.close();
});
