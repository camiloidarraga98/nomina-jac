import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {build} from 'esbuild';
import {readFile,readdir,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const sql=new DatabaseSync(':memory:');
for(const file of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+file,'utf8'));
class Query{
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};const result=q.run(...this.args);return {results:[],meta:{changes:Number(result.changes)}};}
 async run(){return this.execute();}async all(){return this.execute();}async first(){return sql.prepare(this.text).get(...this.args)||null;}
}
globalThis.__contractMobileEnv={DB:{prepare:s=>new Query(s),batch:async statements=>{sql.exec('BEGIN');try{const result=statements.map(q=>q.execute());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}},PAYROLL_AUTH_KEY:'contract-mobile-tests-independent-auth-key'};
globalThis.__contractMobileBeforePdf=null;
globalThis.__contractMobilePdfCalls=0;
globalThis.fetch=async()=>{throw new Error('Las pruebas de contratos no permiten servicios externos.');};
const bundle=await build({stdin:{resolveDir:process.cwd(),contents:"export * as api from './app/api/mobile/contracts/route';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export {PDFDocument} from 'pdf-lib';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'contract-mobile-isolated-platform',setup(b){
 b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'platform'}));
 b.onLoad({filter:/.*/,namespace:'platform'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__contractMobileEnv;export const waitUntil=p=>p.catch(()=>{});':"export const headers=async()=>new Headers({'oai-authenticated-user-email':'camilo@mac2you.co'});",loader:'js'}));
 b.onResolve({filter:/contract-pdf$/},()=>({path:'pdf',namespace:'instrumented'}));
 b.onLoad({filter:/.*/,namespace:'instrumented'},()=>({resolveDir:process.cwd(),contents:"import {contractPdf as original} from './lib/contract-pdf.ts';export async function contractPdf(input){globalThis.__contractMobilePdfCalls++;await globalThis.__contractMobileBeforePdf?.();return original(input);}",loader:'js'}));
}}]});
const temporary=await mkdtemp(resolve('work/contracts-mobile-tests-'));
await writeFile(temporary+'/bundle.mjs',bundle.outputFiles[0].contents);
const m=await import(pathToFileURL(temporary+'/bundle.mjs').href);await rm(temporary,{recursive:true});
const base='https://contracts-mobile.example.invalid';
const fixture={company:'EMPRESA FICTICIA S.A.S.',nit:'900.000.000-0',representative:'MARÍA JOSÉ MUÑOZ ÁLVAREZ',identity:'00.000.000',eventDate:'2027-11-21',venue:'Teatro ficticio',municipality:'Soracá',department:'Boyacá',showTime:'23:00',price:140000000,deposited:22000000,halfDeadline:'2027-11-10'};
let sequence=0;
async function actor({administrator=true,sections=['crm'],persistent=false,mediaOnly=false,itinerariesOnly=false}={}){
 const id='contract-mobile-'+(++sequence),now=new Date().toISOString();
 sql.prepare('INSERT INTO payroll_users (id,username,email,name,password_hash,permissions,section_access,media_only,itineraries_only,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)').run(id,id,id+'@example.invalid','Administrador ficticio','not-an-empty-fixture-hash',JSON.stringify(administrator?[m.ADMINISTRATOR_ROLE]:[]),JSON.stringify(sections),Number(mediaOnly),Number(itinerariesOnly),now,now);
 return {id,token:await m.makeSession(id,persistent)};
}
function request(token='',body=fixture,extra={}){
 const headers={'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{}),...extra.headers};
 return new Request(base+'/api/mobile/contracts',{method:'POST',headers,body:typeof body==='string'||body instanceof ReadableStream?body:JSON.stringify(body),...(body instanceof ReadableStream?{duplex:'half'}:{}),...extra.options});
}
function reset(){globalThis.__contractMobileBeforePdf=null;globalThis.__contractMobilePdfCalls=0;}

test('contratos móviles exigen Bearer real; cookies e identidad legacy no autorizan',async()=>{
 reset();const account=await actor();
 for(const req of [request(),request('',fixture,{headers:{cookie:'__Host-jac_session='+account.token}}),request('',fixture,{headers:{authorization:'Basic '+account.token}}),request('malformed'),request('x'.repeat(43))])assert.equal((await m.api.POST(req)).status,401);
 assert.equal(globalThis.__contractMobilePdfCalls,0);
});
test('contratos móviles conservan los roles CRM y bloquean perfiles limitados',async()=>{
 reset();for(const options of [{administrator:false},{administrator:false,sections:['media','calendar']},{administrator:false,sections:['crm','payroll']},{mediaOnly:true},{itinerariesOnly:true}]){
  const account=await actor(options);assert.equal((await m.api.POST(request(account.token))).status,403);
 }
 assert.equal(globalThis.__contractMobilePdfCalls,0);
});
test('sesión móvil vencida, revocada, contraseña retirada o revisión anterior impide generar',async()=>{
 reset();for(const change of [a=>sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(a.token)),a=>sql.prepare("UPDATE payroll_sessions SET expires_at='2000-01-01T00:00:00Z' WHERE id=?").run(m.tokenHash(a.token)),a=>sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(a.id),a=>sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(a.id),a=>sql.prepare("UPDATE payroll_users SET password_hash='' WHERE id=?").run(a.id)]){
  const account=await actor();change(account);assert.equal((await m.api.POST(request(account.token))).status,401);
 }
 assert.equal(globalThis.__contractMobilePdfCalls,0);
});
test('contratos móviles validan JSON, 8KiB reales y las reglas del mismo formulario web',async()=>{
 reset();const account=await actor();
 for(const [body,headers,status]of [[fixture,{'content-type':'text/plain'},415],[fixture,{'content-type':'application/jsonevil'},415],['{bad',{},400],[{...fixture,price:0},{},400],[{...fixture,deposited:100000000},{},400],[{...fixture,eventDate:'2027-02-29'},{},400],[{...fixture,signature:'changed'},{},400],['x'.repeat(8193),{'content-length':'1'},413],['á'.repeat(4097),{},413]])assert.equal((await m.api.POST(request(account.token,body,{headers}))).status,status);
 const stream=new ReadableStream({start(c){for(let i=0;i<9;i++)c.enqueue(new Uint8Array(1024));c.close();}});
 assert.equal((await m.api.POST(request(account.token,stream))).status,413);
 assert.equal(globalThis.__contractMobilePdfCalls,0);
});
test('revocar sesión, versión, rol o sección durante generación bloquea el PDF completo',async()=>{
 for(const change of [a=>sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(a.token)),a=>sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(a.id),a=>sql.prepare("UPDATE payroll_users SET permissions='[]' WHERE id=?").run(a.id),a=>sql.prepare("UPDATE payroll_users SET section_access='[\"calendar\"]' WHERE id=?").run(a.id),a=>sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(a.id),a=>sql.prepare("UPDATE payroll_users SET password_hash='' WHERE id=?").run(a.id)]){
  reset();const account=await actor();globalThis.__contractMobileBeforePdf=()=>change(account);
  const response=await m.api.POST(request(account.token));assert.equal(response.status,403);assert.match(response.headers.get('content-type'),/application\/json/);assert.equal(globalThis.__contractMobilePdfCalls,1);assert.doesNotMatch(await response.text(),/%PDF/);
 }
 reset();
});
test('revocar mientras llega el formulario evita iniciar la generación',async()=>{
 reset();const account=await actor(),bytes=new TextEncoder().encode(JSON.stringify(fixture));
 const body=new ReadableStream({pull(controller){sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(account.id);controller.enqueue(bytes);controller.close();}},{highWaterMark:0});
 const response=await m.api.POST(request(account.token,body));assert.equal(response.status,403);assert.equal(globalThis.__contractMobilePdfCalls,0);
});
test('sesión persistente genera cuatro páginas privadas con nombre seguro y sin mutaciones',async()=>{
 reset();const account=await actor({persistent:true});
 sql.prepare("UPDATE payroll_sessions SET expires_at='2000-01-01T00:00:00Z' WHERE id=?").run(m.tokenHash(account.token));
 const snapshot=sql.prepare('SELECT total_changes() AS n').get().n;
 const response=await m.api.POST(request(account.token,fixture,{headers:{origin:'https://unrelated.example.invalid'}}));
 assert.equal(response.status,200,await response.clone().text());assert.equal(response.headers.get('content-type'),'application/pdf');assert.equal(response.headers.get('cache-control'),'private, no-store, max-age=0');assert.equal(response.headers.get('vary'),'Authorization');assert.equal(response.headers.get('x-content-type-options'),'nosniff');assert.equal(response.headers.get('content-security-policy'),"default-src 'none'; sandbox");
 assert.equal(response.headers.get('set-cookie'),null);const disposition=response.headers.get('content-disposition');assert.match(disposition,/filename="Contrato JAC - Soraca - 21 de noviembre 2027\.pdf"/);assert.match(disposition,/filename\*=UTF-8''Contrato%20JAC%20-%20Sorac%C3%A1/);
 assert.equal((await m.PDFDocument.load(await response.arrayBuffer())).getPageCount(),4);assert.equal(sql.prepare('SELECT total_changes() AS n').get().n,snapshot,'El endpoint no escribe D1 ni prepara conexiones o envíos');
});
