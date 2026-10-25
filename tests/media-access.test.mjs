import assert from 'node:assert/strict';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir} from 'node:fs/promises';
import {build} from 'esbuild';

// Every account and service in this suite is fictitious. No external requests.
const sql=new DatabaseSync(':memory:');
for(const file of (await readdir('drizzle')).filter(f=>f.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+file,'utf8'));
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};return {results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async run(){return this.execute();}async all(){return this.execute();}async first(){return sql.prepare(this.text).get(...this.args)||null;}
}
const db={prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const r=qs.map(q=>q.execute());sql.exec('COMMIT');return r;}catch(e){sql.exec('ROLLBACK');throw e;}}};
globalThis.__mediaAccessEnv={DB:db,PAYROLL_AUTH_KEY:'media-access-independent-fixture-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,7).toString('base64url'),BUCKET:{get:async()=>{throw new Error('The restricted role must not reach R2.');},put:async()=>{throw new Error('The restricted role must not write R2.');}}};
globalThis.__mediaAccessHeaders=new Headers();
let externalCalls=0;
globalThis.fetch=async()=>{externalCalls++;throw new Error('External services are blocked in media permission tests.');};
const exports=[
 "export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-permissions';export * from './lib/notifications';export * from './lib/travel-expenses';export * from './lib/crm-core';export * from './lib/calendar-permissions';export * from './lib/crm-access';",
 ...Object.entries({users:'users',auth:'auth',payroll:'payroll',mobile:'mobile/payroll',mail:'payroll/email',export:'payroll/export',gmail:'payroll/gmail/start',mobileGmail:'mobile/gmail',calendar:'calendar',notices:'notices',noticePdf:'notices/pdf',noticeFile:'notices/file',publish:'notices/publish',expenses:'expenses',expenseFile:'expenses/file',crm:'crm',crmFile:'crm/file'}).map(([name,path])=>`export * as ${name}Api from './app/api/${path}/route';`),
].join('');
const bundle=await build({stdin:{contents:exports,resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'test-platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers|next\/navigation)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__mediaAccessEnv;export const waitUntil=()=>{};':a.path==='next/headers'?'export const headers=async()=>globalThis.__mediaAccessHeaders;':'export const redirect=()=>{throw new Error("redirect");};',loader:'js'}));}}]});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
const base='https://gallery-access.example.invalid',ownerID=await m.bootstrapOwner('fixture-owner','fixture'),ownerToken=await m.makeSession(ownerID);
async function call(api,body,{token=ownerToken,get=false,path='/api/test'}={}){
 const cookie=token?'__Host-jac_session='+token:'';globalThis.__mediaAccessHeaders=new Headers({host:'gallery-access.example.invalid',cookie});
 const response=await api[get?'GET':'POST'](new Request(base+path,{method:get?'GET':'POST',headers:{cookie,origin:base,'Content-Type':'application/json'},...(get?{}:{body:JSON.stringify(body??{})})}));
 return {status:response.status,body:await response.json()};
}
let photoID,photoToken;
test('photographer role is explicit, isolated, and compatible with older clients',async()=>{
 const record={username:'anderson-fixture',name:'Fotógrafo ficticio',email:'anderson@example.invalid',active:true,mediaOnly:true,permissions:['export','payroll']};
 assert.equal((await call(m.usersApi,{action:'create',user:{...record,administrator:true}})).status,400);
 assert.equal((await call(m.usersApi,{action:'create',user:record})).status,200);
 let row=sql.prepare('SELECT * FROM payroll_users WHERE username=?').get(record.username);photoID=row.id;
 assert.equal(row.media_only,1);assert.equal(row.itineraries_only,0);assert.deepEqual(JSON.parse(row.permissions),[]);
 const invite=await call(m.usersApi,{action:'invite',id:photoID});assert.equal(invite.status,200);
 await m.activateUser(invite.body.activationPath.split('=')[1],'fixture-photo');photoToken=await m.makeSession(photoID);
 const user=await m.authenticatedSession(photoToken);assert.equal(user.mediaOnly,true);assert.equal(user.itinerariesOnly,true);assert.equal(user.isOwner,false);assert.deepEqual(user.permissions,[]);
 const inconsistent={...user,isOwner:true,permissions:[...m.permissionKeys],itinerariesOnly:false};
 assert.ok(m.permissionKeys.every(p=>!m.can(inconsistent,p)));assert.equal(m.canCrm(inconsistent),false);assert.equal(m.canEditAgenda(inconsistent),false);assert.equal(m.noticeOwner(inconsistent),false);
 row=sql.prepare('SELECT * FROM payroll_users WHERE id=?').get(photoID);
 assert.equal(m.accountAdministrator({...row,permissions:JSON.stringify(['administrator']),owner:1,email:m.OWNER_EMAIL}),false);
});
test('photographer receives an empty mobile workspace and no financial data',async()=>{
 const r=await call(m.mobileApi,null,{token:photoToken,get:true,path:'/api/mobile/payroll?workspace=1'});assert.equal(r.status,200);
 assert.equal(r.body.user.mediaOnly,true);assert.equal(r.body.user.itinerariesOnly,true);assert.deepEqual(r.body.employees,[]);assert.deepEqual(r.body.periods,[]);assert.deepEqual(r.body.data.employees,[]);assert.deepEqual(r.body.data.periods,[]);assert.equal(r.body.version,0);
 assert.equal((await call(m.mobileApi,null,{token:photoToken,get:true,path:'/api/mobile/payroll?period=known-period'})).status,403);
});
test('direct requests to team, files, financial, administrative and integration APIs are denied before side effects',async()=>{
 const getApis=[m.usersApi,m.payrollApi,m.mailApi,m.exportApi,m.calendarApi,m.noticesApi,m.noticePdfApi,m.noticeFileApi,m.expensesApi,m.expenseFileApi,m.crmApi,m.crmFileApi];
 for(const api of getApis)assert.equal((await call(api,null,{token:photoToken,get:true,path:'/api/test?id=00000000-0000-4000-8000-000000000000&file=00000000-0000-4000-8000-000000000001'})).status,403);
 for(const api of [m.usersApi,m.payrollApi,m.mailApi,m.mobileApi,m.gmailApi,m.mobileGmailApi,m.calendarApi,m.noticesApi,m.publishApi,m.expensesApi,m.crmApi])assert.equal((await call(api,{action:'anything'},{token:photoToken})).status,403);
 const user=await m.authenticatedSession(photoToken);
 for(const read of [()=>m.noticeFeed(user),()=>m.boardingFeed(user),()=>m.allowedNotice(user,crypto.randomUUID()),()=>m.expenseFeed(user),()=>m.allowedExpense(user,crypto.randomUUID()),()=>m.submitExpense(user,{},async()=>true)])await assert.rejects(read,e=>e.status===403);
 // Folder notifications allow a photographer to register a device, but this
 // invalid request must reach validation without creating devices or deliveries.
 const devices=sql.prepare('SELECT count(*) n FROM jac_push_devices').get().n,deliveries=sql.prepare('SELECT count(*) n FROM jac_push_deliveries').get().n;
 assert.equal((await call(m.noticesApi,{action:'register'},{token:photoToken,path:'/api/notices'})).status,400);
 await assert.rejects(()=>m.registerDevice(user,{},'token',async()=>true),e=>e.status===400);
 const calendarOnly={...user,mediaOnly:false,sections:['calendar']};
 await assert.rejects(()=>m.registerDevice(calendarOnly,{},'token',async()=>true),e=>e.status===403);
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_push_devices').get().n,devices);
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_push_deliveries').get().n,deliveries);
 assert.equal(externalCalls,0);
});
test('photographer is excluded from alert targets, boarding targets and itinerary push dispatch',async()=>{
 const owner=await m.authenticatedSession(ownerToken),feed=await m.noticeFeed(owner);
 assert.ok(!feed.users.some(u=>u.id===photoID));assert.ok(!feed.boardingUsers.some(u=>u.id===photoID));
 await assert.rejects(()=>m.saveManualNotice(owner,{id:crypto.randomUUID(),title:'Ficticio',body:'Solo prueba',recipients:[photoID]},async()=>true),e=>e.status===409);
 const auto=crypto.randomUUID();await m.publishManualNotice(owner,{id:auto,kind:'itinerary',title:'Itinerario automático ficticio',body:'',recipients:[],files:[]},async()=>true);assert.equal(sql.prepare('SELECT count(*) AS n FROM jac_notice_recipients WHERE notice_id=? AND user_id=?').get(auto,photoID).n,0);assert.equal(sql.prepare('SELECT count(*) AS n FROM jac_notice_recipients WHERE notice_id=? AND user_id=?').get(auto,ownerID).n,1);
 const notice=crypto.randomUUID(),device=crypto.randomUUID(),stamp=new Date().toISOString(),row=sql.prepare('SELECT version FROM payroll_users WHERE id=?').get(photoID);
 sql.prepare("INSERT INTO jac_notices(id,kind,title,created_at) VALUES (?,'itinerary','Ficticio',?)").run(notice,stamp);
 sql.prepare('INSERT INTO jac_notice_recipients(id,notice_id,user_id) VALUES (?,?,?)').run(notice+'|'+photoID,notice,photoID);
 sql.prepare("INSERT INTO jac_push_devices(id,user_id,user_version,platform,data,session_id,updated_at) VALUES (?,?,?,'ios','fixture',?,?)").run(device,photoID,row.version,m.tokenHash(photoToken),stamp);
 await m.queuePush(notice);assert.equal(sql.prepare('SELECT count(*) n FROM jac_push_deliveries WHERE device_id=?').get(device).n,0);
 sql.prepare("INSERT INTO jac_push_deliveries(id,notice_id,device_id,updated_at) VALUES (?,?,?,?)").run(notice+'|'+device,notice,device,stamp);
 await m.dispatchPush();assert.equal(externalCalls,0);assert.equal(sql.prepare('SELECT status FROM jac_push_deliveries WHERE device_id=?').get(device).status,'pending');
});
test('older account editors preserve restricted role; CAS and account changes revoke sessions',async()=>{
 let row=sql.prepare('SELECT * FROM payroll_users WHERE id=?').get(photoID),pub=m.publicUser(row),oldClient={...pub,permissions:['payroll','export']};delete oldClient.mediaOnly;delete oldClient.itinerariesOnly;delete oldClient.administrator;
 assert.equal((await call(m.usersApi,{action:'update',id:photoID,version:row.version,user:oldClient})).status,200);
 assert.equal(await m.authenticatedSession(photoToken),null);row=sql.prepare('SELECT * FROM payroll_users WHERE id=?').get(photoID);assert.equal(row.media_only,1);assert.deepEqual(JSON.parse(row.permissions),[]);
 assert.equal((await call(m.usersApi,{action:'update',id:photoID,version:row.version-1,user:oldClient})).status,409);
 assert.equal((await call(m.usersApi,{action:'update',id:photoID,version:row.version,user:{...oldClient,administrator:true}})).status,400);
 const fresh=await m.makeSession(photoID),identity=await m.authenticatedSession(fresh);assert.equal(identity.mediaOnly,true);assert.equal(identity.isOwner,false);
 const guard=m.crmStoredGuard(m.tokenHash(fresh),photoID);assert.equal((await db.prepare('SELECT 1 AS allowed WHERE '+guard.sql).bind(...guard.bindings).first()),null);
});
