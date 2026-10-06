import assert from 'node:assert/strict';
import test from 'node:test';
// This suite is only for the local production build; it never connects to Google.
const base=process.env.PAYROLL_MAIL_TEST_URL;
test('API protege la conexión de Gmail y conserva el cierre con correos pendientes',{skip:!base},async()=>{
 assert.match(new URL(base).hostname,/^(127\.0\.0\.1|localhost)$/);
 const owner='camilo@mac2you.co',assistant='info@jacmusic.co',accountant='contabilidad@jacmusic.co';
 const headers=email=>({'oai-authenticated-user-email':email,Origin:base,'Content-Type':'application/json'});
 const post=async(path,body,email=owner)=>{const r=await fetch(base+path,{method:'POST',headers:headers(email),body:JSON.stringify(body)});return {status:r.status,body:await r.json()};};
 const read=async(path,email=owner)=>{const r=await fetch(base+path,{headers:headers(email)});return {status:r.status,body:await r.json()};};
 assert.equal((await read('/api/payroll/email','intruder@example.invalid')).status,401);
 for(const user of [assistant,accountant])assert.equal((await post('/api/payroll/email',{action:'configure',clientId:'test.apps.googleusercontent.com',clientSecret:'mock-client-secret'},user)).status,403);
 assert.equal((await post('/api/payroll/gmail/start',{},assistant)).status,403);
 const config=await post('/api/payroll/email',{action:'configure',clientId:'test.apps.googleusercontent.com',clientSecret:'mock-client-secret'});assert.equal(config.status,200);
 const initial=await read('/api/payroll');let current=initial.body;const {data,version}=current;const p={id:crypto.randomUUID(),start:'2026-11-01',end:'2026-11-15',status:'abierta',shows:[],routes:[],hours:[],movements:[],excludedEmployees:[]};
 assert.ok(!data.periods.some(q=>q.start<=p.end&&q.end>=p.start),'Choose a free local test period before running again.');data.periods.push(p);const saved=await post('/api/payroll',{action:'save',data,version},assistant);assert.equal(saved.status,200);current=saved.body;
 const closed=await post('/api/payroll',{action:'close',periodId:p.id,version:current.version},assistant);assert.equal(closed.status,200);const final=closed.body.data.periods.find(q=>q.id===p.id);assert.equal(final.status,'cerrada');assert.match(closed.body.mailNotice,/Conecta/);
 for(const user of [owner,assistant,accountant]){const state=await read('/api/payroll/email?period='+p.id,user);assert.equal(state.status,200);assert.equal(state.body.prepared,true);assert.equal(state.body.connection.connected,false);assert.equal(state.body.jobs.length,new Set(final.snapshot.rows.map(r=>r.employeeId)).size);assert.ok(state.body.jobs.every(j=>['pending','missing'].includes(j.status)));assert.ok(!JSON.stringify(state.body).includes('mock-client-secret'));}
 assert.equal((await post('/api/payroll/email',{action:'send',periodId:p.id},accountant)).status,400);
 const start=await post('/api/payroll/gmail/start',{});assert.equal(start.status,200);const url=new URL(start.body.url);assert.equal(url.hostname,'accounts.google.com');assert.equal(url.searchParams.get('login_hint'),'jacmusicestudios@gmail.com');assert.ok(!url.searchParams.get('scope').includes('gmail.read'));
 const fakeCallback=await fetch(base+'/api/payroll/gmail/callback?code=mock&state=invalid',{headers:headers(owner),redirect:'manual'});assert.equal(fakeCallback.status,303);assert.equal(fakeCallback.headers.get('location'),'/?mail=error');const after=await read('/api/payroll');assert.deepEqual(after.body.data.periods.find(q=>q.id===p.id).snapshot,final.snapshot);
});
