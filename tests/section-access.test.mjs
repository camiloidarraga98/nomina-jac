import assert from 'node:assert/strict';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir} from 'node:fs/promises';
import {build} from 'esbuild';

// Memory-only D1 and intercepted services: no real accounts, mail or Calendar.
const sql=new DatabaseSync(':memory:');
for(const file of (await readdir('drizzle')).filter(f=>f.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+file,'utf8'));
let beforeQuery=null,beforeBatch=null,financialReads=0,externalCalls=0;
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){if(/SELECT (?:data,version FROM payroll_state|data FROM payroll_periods)/.test(this.text))financialReads++;if(beforeQuery)beforeQuery(this);const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};return {results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async run(){return this.execute();}async all(){return this.execute();}async first(){if(beforeQuery)beforeQuery(this);return sql.prepare(this.text).get(...this.args)||null;}
}
const db={prepare:s=>new Query(s),batch:async qs=>{if(beforeBatch)beforeBatch(qs);sql.exec('BEGIN');try{const r=qs.map(q=>q.execute());sql.exec('COMMIT');return r;}catch(e){sql.exec('ROLLBACK');throw e;}}};
globalThis.__sectionEnv={DB:db,PAYROLL_AUTH_KEY:'section-access-independent-fixture-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,13).toString('base64url'),BUCKET:{get:async()=>{throw new Error('Unexpected bucket access.');},put:async()=>{throw new Error('Unexpected bucket write.');}}};
globalThis.__sectionHeaders=new Headers();globalThis.fetch=async()=>{externalCalls++;throw new Error('External services are blocked.');};
const exports=[
 "export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-permissions';export * from './lib/payroll-store';export * from './lib/payroll-section-guard';export * from './lib/travel-expenses';export * from './lib/crm-core';export * from './lib/calendar-permissions';export * from './lib/crm-access';export * from './lib/media-core';",
 ...Object.entries({users:'users',payroll:'payroll',mobile:'mobile/payroll',mail:'payroll/email',export:'payroll/export',calendar:'calendar',expenses:'expenses',expenseFile:'expenses/file',crm:'crm',crmFile:'crm/file'}).map(([name,path])=>`export * as ${name}Api from './app/api/${path}/route';`),
].join('');
const bundle=await build({stdin:{contents:exports,resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'test-platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers|next\/navigation)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__sectionEnv;export const waitUntil=()=>{};':a.path==='next/headers'?'export const headers=async()=>globalThis.__sectionHeaders;':'export const redirect=()=>{throw new Error("redirect");};',loader:'js'}));}}]});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
const base='https://section-access.example.invalid',ownerID=await m.bootstrapOwner('fixture-owner','fixture'),ownerToken=await m.makeSession(ownerID);
function setHeaders(token){const cookie=token?'__Host-jac_session='+token:'';globalThis.__sectionHeaders=new Headers({host:'section-access.example.invalid',cookie});return cookie;}
async function call(api,body,{token=ownerToken,get=false,path='/api/test'}={}){
 const cookie=setHeaders(token),response=await api[get?'GET':'POST'](new Request(base+path,{method:get?'GET':'POST',headers:{cookie,origin:base,'Content-Type':'application/json'},...(get?{}:{body:JSON.stringify(body??{})})}));
 return {status:response.status,body:await response.json()};
}
let sequence=0;
async function create(sections,extra={}){
 const key='section-fixture-'+(++sequence),record={username:key,name:'Cuenta ficticia '+sequence,email:key+'@example.invalid',active:true,permissions:[...m.permissionKeys],...(sections===undefined?{}:{sections}),...extra};
 const result=await call(m.usersApi,{action:'create',user:record});assert.equal(result.status,200,JSON.stringify(result.body));
 const row=sql.prepare('SELECT * FROM payroll_users WHERE username=?').get(key);sql.prepare('UPDATE payroll_users SET password_hash=? WHERE id=?').run(m.hashPassword('fixture',globalThis.__sectionEnv.PAYROLL_AUTH_KEY),row.id);
 return {id:row.id,token:await m.makeSession(row.id)};
}
const rowFor=id=>sql.prepare('SELECT * FROM payroll_users WHERE id=?').get(id);
const revoke=id=>{sql.prepare('UPDATE payroll_users SET version=version+1,section_access=?,itineraries_only=1,media_only=0,permissions=? WHERE id=?').run('[]','[]',id);sql.prepare('DELETE FROM payroll_sessions WHERE user_id=?').run(id);};

test('each selected section is independent and financial data stays absent for non-payroll accounts',async()=>{
 for(const sections of [[],['calendar'],['alerts'],['boarding'],['itineraries'],['media'],['media','mediaUpload'],['calendar','itineraries','alerts','boarding','media','mediaUpload']]){
  const account=await create(sections),row=rowFor(account.id),user=await m.authenticatedSession(account.token);
  assert.deepEqual(user.sections,sections);assert.equal(row.itineraries_only,1);assert.equal(row.media_only,0);assert.equal(user.itinerariesOnly,true);assert.equal(!!user.mediaOnly,sections.includes('media'));assert.deepEqual(user.permissions,[]);
  assert.equal(m.hasSection(user,'payroll'),false);assert.equal(m.canCrm(user),false);assert.equal(m.canEditAgenda(user),false);assert.equal(m.canUploadMedia(user),sections.includes('mediaUpload'));
  const readsBefore=financialReads;
  for(const api of [m.payrollApi,m.mailApi,m.exportApi,m.crmApi,m.crmFileApi])assert.equal((await call(api,null,{token:account.token,get:true})).status,403);
  for(const api of [m.payrollApi,m.mobileApi,m.mailApi])assert.equal((await call(api,{action:'save'},{token:account.token})).status,403);
  const mobile=await call(m.mobileApi,null,{token:account.token,get:true,path:'/api/mobile/payroll?workspace=1'});assert.equal(mobile.status,200);assert.deepEqual(mobile.body.data.periods,[]);assert.deepEqual(mobile.body.data.employees,[]);assert.deepEqual(mobile.body.periods,[]);assert.deepEqual(mobile.body.employees,[]);assert.equal(mobile.body.version,0);assert.deepEqual(mobile.body.user.sections,sections);
  assert.equal((await call(m.mobileApi,null,{token:account.token,get:true,path:'/api/mobile/payroll?period=known'})).status,403);assert.equal(financialReads,readsBefore,'restricted requests must not even read payroll state');
  const calendar=await call(m.calendarApi,null,{token:account.token,get:true});assert.equal(calendar.status,sections.includes('calendar')?200:403);assert.equal((await call(m.calendarApi,{action:'createEvent'},{token:account.token})).status,403);
  assert.equal((await call(m.expensesApi,null,{token:account.token,get:true})).status,sections.includes('itineraries')?200:403);
 }
 assert.equal(externalCalls,0);
});

test('payroll section alone grants read; write permissions and other sections remain independent',async()=>{
 const account=await create(['payroll'],{permissions:[]}),user=await m.authenticatedSession(account.token);assert.equal(!!user.itinerariesOnly,false);assert.equal(!!user.mediaOnly,false);assert.equal(m.hasSection(user,'payroll'),true);assert.ok(m.permissionKeys.every(key=>!m.can(user,key)));
 const state=await call(m.payrollApi,null,{token:account.token,get:true});assert.equal(state.status,200);assert.ok(state.body.data.employees.length>0);
 assert.equal((await call(m.mobileApi,null,{token:account.token,get:true,path:'/api/mobile/payroll?workspace=1'})).status,200);
 for(const api of [m.calendarApi,m.expensesApi,m.exportApi,m.crmApi])assert.equal((await call(api,null,{token:account.token,get:true})).status,403);
 const changed=structuredClone(state.body.data);changed.employees[0].name+=' Modificado';assert.equal((await call(m.payrollApi,{action:'save',data:changed,version:state.body.version},{token:account.token})).status,403);
});

test('legacy profiles preserve their exact effective sections and administrators gain upload',async()=>{
 for(const [extra,want] of [[{},['payroll','calendar','itineraries','alerts','boarding']],[{itinerariesOnly:true},['calendar','itineraries','alerts','boarding']],[{mediaOnly:true},['media','mediaUpload']]]){
  const account=await create(undefined,extra),user=await m.authenticatedSession(account.token);assert.equal(rowFor(account.id).section_access,null);assert.equal(user.sections,undefined);assert.deepEqual(m.resolvedSections(user),want);
 }
 const account=await create(['media'],{administrator:true}),user=await m.authenticatedSession(account.token);assert.equal(user.isOwner,true);assert.equal(!!user.mediaOnly,false);assert.equal(!!user.itinerariesOnly,false);assert.deepEqual(m.resolvedSections(user),m.sectionKeys);assert.equal(m.canUploadMedia(user),true);assert.equal(m.canCrm(user),true);assert.equal(m.canEditAgenda(user),true);
 const founder=await m.authenticatedSession(ownerToken);assert.equal(m.canUploadMedia(founder),true);
});

test('invalid combinations are rejected without creating an account',async()=>{
 const before=sql.prepare('SELECT count(*) AS n FROM payroll_users').get().n,common={username:'invalid-sections',name:'Ficticio inválido',email:'invalid@example.invalid',active:true,permissions:[]};
 for(const sections of [['mediaUpload'],['crm'],['unknown'],['calendar',1],null,'calendar'])assert.equal((await call(m.usersApi,{action:'create',user:{...common,sections}})).status,400);
 assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_users').get().n,before);
});

test('SQL and JavaScript agree across every valid section combination; CRM stays admin-only',async()=>{
 const account=await create([]),keys=m.sectionKeys.filter(key=>key!=='crm');
 for(let mask=0;mask<1<<keys.length;mask++){
  const sections=keys.filter((_,index)=>mask&(1<<index));if(sections.includes('mediaUpload')&&!sections.includes('media'))continue;
  sql.prepare('UPDATE payroll_users SET section_access=?,itineraries_only=?,media_only=0 WHERE id=?').run(JSON.stringify(sections),Number(!sections.includes('payroll')),account.id);
  const row=rowFor(account.id),user=m.accessUser(row);
  for(const key of m.sectionKeys){const match=sql.prepare('SELECT count(*) AS n FROM payroll_users u WHERE id=? AND '+m.sectionSql('u',key)).get(account.id);assert.equal(match.n===1,m.hasSection(user,key),JSON.stringify({sections,key}));}
 }
 for(const raw of ['not-json','null','"calendar"','{}','["calendar",4]','["calendar","unknown"]']){
  sql.prepare('UPDATE payroll_users SET section_access=?,itineraries_only=1 WHERE id=?').run(raw,account.id);const user=m.accessUser(rowFor(account.id));assert.deepEqual(user.sections,[]);
  for(const key of m.sectionKeys)assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_users u WHERE id=? AND '+m.sectionSql('u',key)).get(account.id).n,0,JSON.stringify({raw,key}));
 }
 assert.throws(()=>m.sectionSql('u;DROP TABLE payroll_users','calendar'));
});

test('older editors preserve custom sections, safe flags, revocation and CAS',async()=>{
 const account=await create(['calendar','alerts','media','mediaUpload']),row=rowFor(account.id),pub=m.publicUser(row),oldClient={...pub,permissions:[...m.permissionKeys]};delete oldClient.sections;delete oldClient.administrator;
 const encoded=row.section_access;assert.equal((await call(m.usersApi,{action:'update',id:row.id,version:row.version,user:oldClient})).status,200);assert.equal(await m.authenticatedSession(account.token),null);
 const after=rowFor(row.id);assert.equal(after.section_access,encoded);assert.equal(after.itineraries_only,1);assert.equal(after.media_only,0);assert.deepEqual(JSON.parse(after.permissions),[]);
 const fresh=await m.makeSession(row.id);assert.equal((await call(m.usersApi,{action:'update',id:row.id,version:row.version,user:{...oldClient,sections:['payroll']}})).status,409);assert.ok(await m.authenticatedSession(fresh));assert.equal(rowFor(row.id).section_access,encoded);
 const modern={...m.publicUser(after),sections:['itineraries'],permissions:[...m.permissionKeys]};assert.equal((await call(m.usersApi,{action:'update',id:row.id,version:after.version,user:modern})).status,200);assert.equal(await m.authenticatedSession(fresh),null);assert.deepEqual(m.accessUser(rowFor(row.id)).sections,['itineraries']);
});

test('revoked permission while financial data is loading never returns that data',async()=>{
 for(const api of [m.payrollApi,m.mobileApi,m.mailApi]){
  const account=await create(['payroll']);beforeQuery=q=>{if(q.text==='SELECT data,version FROM payroll_state WHERE id = ?'){beforeQuery=null;revoke(account.id);}};
  try{const result=await call(api,null,{token:account.token,get:true,path:'/api/mobile/payroll?workspace=1'});assert.equal(result.status,403);assert.equal(result.body.data,undefined);assert.equal(result.body.employees,undefined);}finally{beforeQuery=null;}
 }
});

test('financial commit is blocked atomically if the session/sections are revoked during save',async()=>{
 const account=await create(['payroll']),current=await call(m.payrollApi,null,{token:account.token,get:true}),changed=structuredClone(current.body.data);changed.employees[0].name+=' No debe guardarse';
 beforeBatch=queries=>{if(queries.some(q=>q.text.startsWith('UPDATE payroll_state SET data = ?'))){beforeBatch=null;revoke(account.id);}};
 try{assert.equal((await call(m.payrollApi,{action:'save',data:changed,version:current.body.version},{token:account.token})).status,409);}finally{beforeBatch=null;}
 const stored=await m.readPayroll();assert.equal(stored.version,current.body.version);assert.deepEqual(stored.data,current.body.data);
});

test('CRM stored guard and financial guards deny custom non-admin accounts and revoked sessions',async()=>{
 const account=await create(['payroll','media']),user=await m.authenticatedSession(account.token);setHeaders(account.token);const guard=await m.payrollSectionGuard(user);assert.ok(await db.prepare('SELECT 1 AS ok WHERE '+guard.sql).bind(...guard.bindings).first());
 const crm=m.crmStoredGuard(m.tokenHash(account.token),account.id);assert.equal(await db.prepare('SELECT 1 AS ok WHERE '+crm.sql).bind(...crm.bindings).first(),null);revoke(account.id);assert.equal(await db.prepare('SELECT 1 AS ok WHERE '+guard.sql).bind(...guard.bindings).first(),null);assert.equal(externalCalls,0);
});
