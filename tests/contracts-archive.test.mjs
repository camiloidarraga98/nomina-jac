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
const temporary=await mkdtemp(resolve('work/contracts-archive-tests-'));
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


const objects=new Map();let beforePut=null,beforeGet=null,failPut=false;
globalThis.__contractMobileEnv.BUCKET={put:async(key,data)=>{if(beforePut)await beforePut();if(failPut)throw Error('R2 simulado fuera de servicio');objects.set(key,Uint8Array.from(data));},get:async key=>{if(beforeGet)await beforeGet();const bytes=objects.get(key);return bytes?{body:new Response(bytes).body}:null;},delete:async key=>objects.delete(key)};
const create=(account,id=crypto.randomUUID(),showId=null,input=fixture)=>m.api.POST(request(account.token,{action:'save',id,showId,input}));
const get=(account,query='')=>m.api.GET(new Request(base+'/api/mobile/contracts'+query,{headers:{authorization:'Bearer '+account.token}}));
const link=(account,id,showId,version)=>m.api.POST(request(account.token,{action:'link',id,showId,version}));
function show(title='PEREIRA FICTICIO',date='2020-01-10'){const id=crypto.randomUUID(),now=new Date().toISOString();sql.prepare('INSERT INTO jac_crm_shows (id,calendar_id,event_id,title,municipality,show_date,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run(id,'calendar.invalid',id,title,'Pereira',date,now,now);return id;}

test('guarda PDF exacto, reintento idempotente y listado privado compartido entre administradores',async()=>{
 reset();const a=await actor(),b=await actor(),id=crypto.randomUUID(),showId=show();
 const first=await create(a,id,showId);assert.equal(first.status,200,await first.clone().text());const bytes=Buffer.from(await first.arrayBuffer());assert.equal((await m.PDFDocument.load(bytes)).getPageCount(),4);assert.equal(first.headers.get('x-jac-contract-id'),id);
 const again=await create(a,id,showId);assert.equal(again.status,200);assert.deepEqual(Buffer.from(await again.arrayBuffer()),bytes);assert.equal(sql.prepare('SELECT count(*) AS n FROM jac_crm_contracts WHERE id=?').get(id).n,1);
 const data=await (await get(b)).json(),row=data.contracts.find(c=>c.id===id);assert.equal(row.showTitle,'PEREIRA FICTICIO');assert.equal(row.company,fixture.company);assert.equal(row.input_json,undefined);assert.equal(row.file_key,undefined);
 assert.deepEqual(Buffer.from(await (await get(b,'?id='+id)).arrayBuffer()),bytes);
 assert.equal((await create(a,id,showId,{...fixture,company:'OTRA EMPRESA'})).status,409);assert.equal((await create(b,id,showId)).status,409);
 const choices=await (await get(a,'?view=shows&q=PEREIRA')).json();assert.ok(choices.shows.some(s=>s.id===showId),'También se pueden asignar shows anteriores');
});
test('asignación y desasignación con CAS no cambian PDF, valores o abonos; show eliminado conserva contrato',async()=>{
 reset();const a=await actor(),id=crypto.randomUUID(),showId=show();await create(a,id);const before=Buffer.from(await (await get(a,'?id='+id)).arrayBuffer()),showBefore=sql.prepare('SELECT * FROM jac_crm_shows WHERE id=?').get(showId);
 assert.equal((await link(a,id,showId,1)).status,200);assert.equal((await link(a,id,null,1)).status,409);assert.equal((await link(a,id,null,2)).status,200);assert.equal((await link(a,id,crypto.randomUUID(),3)).status,409);assert.equal((await link(a,id,showId,3)).status,200);
 assert.deepEqual(sql.prepare('SELECT * FROM jac_crm_shows WHERE id=?').get(showId),showBefore);assert.deepEqual(Buffer.from(await (await get(a,'?id='+id)).arrayBuffer()),before);
 sql.prepare("UPDATE jac_crm_shows SET source_state='deleted' WHERE id=?").run(showId);const data=await (await get(a)).json();assert.equal(data.contracts.find(c=>c.id===id).showTitle,'');assert.equal((await get(a,'?id='+id)).status,200);assert.equal((await link(a,id,null,4)).status,200);
});
test('concurrencia de creación mantiene un único PDF listo; fallo R2 permite recuperación sin duplicar',async()=>{
 reset();const a=await actor(),id=crypto.randomUUID();const replies=await Promise.all([create(a,id),create(a,id)]);assert.ok(replies.some(r=>r.status===200));assert.ok(replies.every(r=>[200,409].includes(r.status)));assert.equal(sql.prepare('SELECT count(*) AS n FROM jac_crm_contracts WHERE id=?').get(id).n,1);
 const second=crypto.randomUUID();failPut=true;assert.equal((await create(a,second)).status,503);failPut=false;assert.equal(sql.prepare('SELECT state FROM jac_crm_contracts WHERE id=?').get(second).state,'failed');assert.equal((await get(a,'?id='+second)).status,404);assert.equal((await create(a,second)).status,200);
});
test('permisos y revocación antes/después de R2 bloquean archivos y guardado; no expone pendientes',async()=>{
 reset();const a=await actor(),id=crypto.randomUUID();await create(a,id);const reader=await actor({administrator:false,sections:['calendar']});assert.equal((await get(reader)).status,403);assert.equal((await get(reader,'?id='+id)).status,403);assert.equal((await link(reader,id,null,1)).status,403);
 beforeGet=()=>sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(a.id);assert.equal((await get(a,'?id='+id)).status,403);beforeGet=null;
 const b=await actor(),blocked=crypto.randomUUID();beforePut=()=>sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(b.id);assert.equal((await create(b,blocked)).status,403);beforePut=null;assert.equal(sql.prepare('SELECT state FROM jac_crm_contracts WHERE id=?').get(blocked).state,'failed');assert.equal([...objects.keys()].some(k=>k.includes(blocked)),false);
 const c=await actor();assert.equal((await get(c,'?offset=-1')).status,400);assert.equal((await create(c,crypto.randomUUID(),crypto.randomUUID())).status,409);
});
