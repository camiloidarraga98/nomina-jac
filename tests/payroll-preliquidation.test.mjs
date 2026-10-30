import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir} from 'node:fs/promises';

const sql=new DatabaseSync(':memory:');
for(const file of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+file,'utf8'));
class Query{
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};const out=q.run(...this.args);return {results:[],meta:{changes:Number(out.changes)}};}
 async run(){return this.execute();}async all(){return this.execute();}async first(){return sql.prepare(this.text).get(...this.args)||null;}
}
globalThis.__mobileEnv={DB:{prepare:s=>new Query(s),batch:async qs=>{if(globalThis.__beforeClosureWrite&&qs.some(q=>q.text.startsWith('UPDATE payroll_state SET'))){const hook=globalThis.__beforeClosureWrite;globalThis.__beforeClosureWrite=undefined;await hook();}sql.exec('BEGIN');try{const out=qs.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},PAYROLL_AUTH_KEY:'independent-mobile-test-key-at-least-32-characters'};
globalThis.__mobileHeaders=new Headers();globalThis.__mailTasks=[];globalThis.__afterReview=undefined;globalThis.__mobileEnv.PAYROLL_MAIL_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const bundle=await build({stdin:{contents:"export * as api from './app/api/mobile/payroll/route';export * as exportsApi from './app/api/payroll/export/route';export * as emailApi from './app/api/payroll/email/route';export * from './lib/payroll-mail';export * from './lib/payroll-mail-core';export * from './lib/payroll-seed';export * as webApi from './app/api/payroll/route';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-store';export * from './lib/payroll';export * from './lib/payroll-mobile';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'mobile-platform',setup(b){b.onResolve({filter:/^@\/lib\/payroll-export$/},()=>({path:'review-export',namespace:'review-mock'}));b.onLoad({filter:/.*/,namespace:'review-mock'},()=>({contents:"export * from './lib/payroll-export';import {payrollPdf as original} from './lib/payroll-export';export async function payrollPdf(...args){const out=await original(...args);if(globalThis.__afterReview)await globalThis.__afterReview();return out;}",resolveDir:process.cwd(),loader:'js'}));b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__mobileEnv;export const waitUntil=p=>globalThis.__mailTasks.push(p);':'export const headers=async()=>globalThis.__mobileHeaders;',loader:'js'}));}}]});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
const base='https://mobile.example.invalid';
let sent=0;
globalThis.fetch=async(url)=>{
 if(String(url)==='https://oauth2.googleapis.com/token')return Response.json({access_token:'fixture-only'});
 if(String(url)==='https://gmail.googleapis.com/gmail/v1/users/me/messages/send'){sent++;return Response.json({id:'fixture-'+sent});}
 throw new Error('No external service is allowed in these tests.');
};
async function session(id,permissions=['export','payroll','close','send'],section='["payroll"]'){
 const stamp=new Date().toISOString();sql.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,section_access,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)').run(id,id,id+'@example.invalid','Persona ficticia',m.hashPassword('x',globalThis.__mobileEnv.PAYROLL_AUTH_KEY),JSON.stringify(permissions),section,stamp,stamp);return m.makeSession(id);
}
function headers(token){globalThis.__mobileHeaders=new Headers({host:'mobile.example.invalid',cookie:token?'__Host-jac_session='+token:''});return {origin:base,'content-type':'application/json'};}
async function exportFile(token,version,extra=''){
 headers(token);return m.exportsApi.GET(new Request(base+'/api/payroll/export?period=review&mode=preliquidation&version='+version+extra));
}
async function command(token,body,api=m.webApi){const response=await api.POST(new Request(base+'/api/payroll',{method:'POST',headers:headers(token),body:JSON.stringify(body)}));return {status:response.status,body:await response.json()};}
async function fixture(){
 await Promise.all(globalThis.__mailTasks.splice(0));sql.prepare('DELETE FROM payroll_gmail').run();
 const current=await m.readPayroll(),state=m.initialPayroll(),prototype=state.employees[0];state.settings.company='Empresa ficticia';state.settings.nit='TEST';
 state.employees=['person-a','person-b'].map(id=>({...prototype,id,name:id,document:'TEST-'+id,email:id+'@example.invalid',active:true,deleted:false,category:'musicos',showRate:100000,fixedService:0,salary:0,transport:0,withholding:0,ica:0}));
 const p=m.newPeriod('2090-11-01','2090-11-15');p.id='review';p.shows=[{id:'show',name:'Show ficticio',date:p.start,sale:1000000,participants:state.employees.map(e=>({employeeId:e.id,amount:100000}))}];state.periods=[p];
 sql.prepare('DELETE FROM payroll_mail_jobs').run();sql.prepare('DELETE FROM payroll_mail_batches').run();sent=0;
 return m.writePayroll(state,current.version,'fixture');
}
const counts=()=>['payroll_mail_jobs','payroll_mail_batches'].map(table=>sql.prepare('SELECT count(*) n FROM '+table).get().n);
async function connectMail(){
 const encrypted=await m.encryptMail({clientId:'fixture.apps.googleusercontent.com',clientSecret:'fixture',refreshToken:'fixture'},globalThis.__mobileEnv.PAYROLL_MAIL_KEY);
 sql.prepare('INSERT OR REPLACE INTO payroll_gmail(id,credentials,connected_email,enabled,error,updated_at) VALUES (?,?,?,1,?,?)').run('jac',encrypted,m.GMAIL_SENDER,'','fixture');
}

test('preliquidar PDF/Excel deja quincena, versión, cierres y correo intactos; edición normal permite regenerar',async()=>{
 const token=await session('reviewer'),initial=await fixture();
 for(const format of ['pdf','xlsx']){
  const response=await exportFile(token,initial.version,'&format='+format);assert.equal(response.status,200);assert.match(response.headers.get('content-disposition'),/preliquidacion-v/);assert.match(response.headers.get('cache-control'),/private, no-store/);assert.ok((await response.arrayBuffer()).byteLength>1000);
 }
 assert.deepEqual(await m.readPayroll(),initial);assert.deepEqual(counts(),[0,0]);await m.processMailQueue();assert.equal(sent,0);
 const edited=structuredClone(initial.data);edited.periods[0].shows[0].participants[0].amount=125000;
 const saved=await command(token,{action:'save',version:initial.version,data:edited});assert.equal(saved.status,200);assert.equal(saved.body.data.periods[0].status,'abierta');assert.equal(saved.body.data.periods[0].snapshot,undefined);
 assert.equal((await exportFile(token,initial.version)).status,409);assert.equal((await exportFile(token,saved.body.version)).status,200);assert.deepEqual(counts(),[0,0]);
 const closing=await command(token,{action:'close',periodId:'review',version:saved.body.version});assert.equal(closing.status,200);assert.equal(closing.body.data.periods[0].status,'cerrada');assert.deepEqual(counts(),[2,1]);await Promise.all(globalThis.__mailTasks.splice(0));await m.processMailQueue();assert.equal(sent,0,'Gmail desconectado conserva la cola sin fingir envíos');
 assert.equal((await exportFile(token,closing.body.version)).status,400);
 headers(token);const final=await m.exportsApi.GET(new Request(base+'/api/payroll/export?period=review&format=pdf'));assert.equal(final.status,200);assert.match(final.headers.get('content-disposition'),/resumen-nomina/);assert.deepEqual(counts(),[2,1]);
});

test('permiso de exportación, formatos y versión se validan; no permite desprendibles de una quincena abierta',async()=>{
 const initial=await fixture(),token=await session('format-reviewer'),reader=await session('reader',[]),denied=await session('wrong-section',['export'],'["calendar"]');
 assert.equal((await exportFile('',initial.version)).status,401);assert.equal((await exportFile(reader,initial.version)).status,403);assert.equal((await exportFile(denied,initial.version)).status,403);
 for(const extra of ['&format=zip','&format=slips','&format=pdf&employee=person-a','&format=xlsx&employee='])assert.equal((await exportFile(token,initial.version,extra)).status,400);
 for(const version of ['','abc','-1'])assert.equal((await exportFile(token,version)).status,400);
 headers(token);assert.equal((await m.exportsApi.GET(new Request(base+'/api/payroll/export?period=review&format=slips'))).status,400);
 assert.deepEqual(await m.readPayroll(),initial);assert.deepEqual(counts(),[0,0]);
});

test('una edición o revocación durante el PDF impide entregar una preliquidación obsoleta o privada',async()=>{
 const initial=await fixture(),token=await session('race-reviewer');
 globalThis.__afterReview=async()=>{sql.prepare("UPDATE payroll_state SET version=version+1 WHERE id='jac'").run();};
 try{assert.equal((await exportFile(token,initial.version)).status,409);}finally{globalThis.__afterReview=undefined;}
 const current=await m.readPayroll();globalThis.__afterReview=async()=>{sql.prepare("UPDATE payroll_users SET version=version+1 WHERE username='race-reviewer'").run();};
 try{assert.equal((await exportFile(token,current.version)).status,403);}finally{globalThis.__afterReview=undefined;}
 assert.deepEqual(counts(),[0,0]);assert.equal(sent,0);
});

test('cierre anterior sin cola conserva envío manual: consultar no envía, selección individual y lote no duplican',async()=>{
 const initial=await fixture(),token=await session('sender');
 // Simulate a closure saved before automatic sending was restored.
 const p=initial.data.periods[0];p.snapshot={...m.calculate(initial.data,p),employees:structuredClone(initial.data.employees),closedAt:'2026-10-30T18:00:00Z',closedBy:'fixture@example.invalid'};p.status='cerrada';
 await m.writePayroll(initial.data,initial.version,'fixture');await connectMail();
 headers(token);let preview=await(await m.emailApi.GET(new Request(base+'/api/payroll/email?period=review'))).json();assert.equal(preview.prepared,false);assert.equal(preview.jobs.length,2);assert.deepEqual(counts(),[0,0]);await m.processMailQueue();assert.equal(sent,0);
 assert.equal((await command(token,{action:'send',periodId:'review',employeeId:'person-a'},m.emailApi)).status,200);await Promise.all(globalThis.__mailTasks.splice(0));await m.processMailQueue();assert.equal(sent,1);assert.equal(counts()[0],1);
 headers(token);preview=await(await m.emailApi.GET(new Request(base+'/api/payroll/email?period=review'))).json();assert.equal(preview.jobs.length,2);assert.equal(preview.jobs.find(j=>j.employeeId==='person-a').status,'sent');assert.equal(preview.jobs.find(j=>j.employeeId==='person-b').status,'pending');
 assert.equal((await command(token,{action:'send',periodId:'review'},m.emailApi)).status,200);await Promise.all(globalThis.__mailTasks.splice(0));assert.equal(sent,2);await m.processMailQueue();assert.equal(sent,2);
 assert.equal((await command(token,{action:'send',periodId:'review'},m.emailApi)).status,200);await Promise.all(globalThis.__mailTasks.splice(0));assert.equal(sent,2);
});

test('cierre definitivo web y móvil envía automáticamente una vez; el permiso de cierre autoriza su lote',async()=>{
 for(const [label,api] of [['web',m.webApi],['mobile',m.api]]){
  const initial=await fixture(),token=await session('closer-'+label,['close']);await connectMail();
  const result=await command(token,{action:'close',periodId:'review',version:initial.version},api);assert.equal(result.status,200);assert.match(result.body.mailNotice,/automáticamente/);assert.ok(result.body.mailBatchId);assert.deepEqual(counts(),[2,1]);
  await Promise.all(globalThis.__mailTasks.splice(0));assert.equal(sent,2);assert((await m.mailJobs(result.body.mailBatchId)).every(j=>j.status==='sent'));
  assert.equal((await command(token,{action:'close',periodId:'review',version:initial.version},api)).status,409);
  assert.equal((await command(token,{action:'close',periodId:'review',version:result.body.version},api)).status,400);
  headers(token);await m.emailApi.GET(new Request(base+'/api/payroll/email?period=review'));await m.processMailQueue();assert.equal(sent,2);assert.deepEqual(counts(),[2,1]);
 }
});

test('cierre rechazado o revocado durante el guardado no crea cola ni envía',async()=>{
 for(const scenario of ['permission','stale','concurrent','revoked']){
  const initial=await fixture(),token=await session('blocked-'+scenario,scenario==='permission'?['send']:['close']);await connectMail();
  if(scenario==='concurrent')globalThis.__beforeClosureWrite=()=>sql.prepare("UPDATE payroll_state SET version=version+1 WHERE id='jac'").run();
  if(scenario==='revoked')globalThis.__beforeClosureWrite=()=>sql.prepare('UPDATE payroll_users SET version=version+1 WHERE username=?').run('blocked-'+scenario);
  const result=await command(token,{action:'close',periodId:'review',version:initial.version-(scenario==='stale'?1:0)});assert.equal(result.status,scenario==='permission'?403:409);
  await Promise.all(globalThis.__mailTasks.splice(0));assert.deepEqual(counts(),[0,0]);assert.equal(sent,0);assert.equal((await m.readPayroll()).data.periods[0].status,'abierta');
 }
});

test('sin Gmail conserva el cierre y los destinatarios pendientes; al conectar continúa sin otro cierre',async()=>{
 const initial=await fixture(),token=await session('disconnected-closer',['close']);
 const result=await command(token,{action:'close',periodId:'review',version:initial.version});assert.equal(result.status,200);
 await Promise.all(globalThis.__mailTasks.splice(0));assert.deepEqual(counts(),[2,1]);assert.equal(sent,0);assert((await m.mailJobs(result.body.mailBatchId)).every(j=>j.status==='pending'));
 await connectMail();await m.processMailQueue();assert.equal(sent,2);await m.processMailQueue();assert.equal(sent,2);
});
