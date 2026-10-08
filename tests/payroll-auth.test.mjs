import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir} from 'node:fs/promises';
const sql=new DatabaseSync(':memory:');for(const f of (await readdir('drizzle')).filter(f=>f.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+f,'utf8'));
class Query{constructor(text,args=[]){this.text=text;this.args=args;}bind(...args){return new Query(this.text,args);}execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};const out=q.run(...this.args);return {results:[],meta:{changes:Number(out.changes)}};}async run(){return this.execute();}async all(){return this.execute();}async first(){return sql.prepare(this.text).get(...this.args)||null;}}
const db={prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const r=qs.map(q=>q.execute());sql.exec('COMMIT');return r;}catch(e){sql.exec('ROLLBACK');throw e;}}};
globalThis.__authEnv={DB:db,PAYROLL_AUTH_KEY:'test-only-key-with-at-least-32-characters',PAYROLL_MAIL_KEY:'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'};globalThis.__authHeaders=new Headers();
const bundled=await build({stdin:{contents:"export * from './lib/payroll-auth-crypto';export * from './lib/payroll-auth-store';export * from './lib/payroll-access';export * from './lib/payroll-permissions';export * from './lib/payroll-store';export * from './lib/payroll';export * from './lib/payroll-schema';export * as authApi from './app/api/auth/route';export * as usersApi from './app/api/users/route';export * as payrollApi from './app/api/payroll/route';export * as exportApi from './app/api/payroll/export/route';export * as mailApi from './app/api/payroll/email/route';export * as gmailApi from './app/api/payroll/gmail/start/route';export * as mobileApi from './app/api/mobile/payroll/route';export * as calendarApi from './app/api/calendar/route';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'mock-platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers|next\/navigation)$/},args=>({path:args.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},args=>({contents:args.path==='cloudflare:workers'?'export const env=globalThis.__authEnv;export const waitUntil=()=>{};':args.path==='next/headers'?'export const headers=async()=>globalThis.__authHeaders;':'export const redirect=()=>{throw new Error("redirect");};',loader:'js'}));}}]});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundled.outputFiles[0].contents).toString('base64'));const base='https://payroll.example.invalid',owner='camilo@mac2you.co',password='12';
async function call(api,body,{cookie='',email='',origin=base,ip='192.0.2.1',get=false,path=''}={}){globalThis.__authHeaders=new Headers({host:'payroll.example.invalid',cookie,'oai-authenticated-user-email':email});const req=new Request(base+path,{method:get?'GET':'POST',headers:{cookie,origin,'Content-Type':'application/json','cf-connecting-ip':ip},...(get?{}:{body:JSON.stringify(body)})});const r=await (get?api.GET(req):api.POST(req));const out=await r.json();return {r,status:r.status,body:out,cookie:r.headers.get('set-cookie')?.split(';')[0]||''};}
let ownerCookie='',luisaCookie='',luisaId='';
test('activación administradora requiere identidad previa y no acepta suplantación después',async()=>{
 assert.equal((await call(m.authApi,{action:'bootstrap',username:'camilo',password},{email:'intruder@example.invalid'})).status,401);
 assert.equal((await call(m.authApi,{action:'bootstrap',username:'camilo',password},{email:owner,origin:'https://evil.example.invalid'})).status,403);
 const out=await call(m.authApi,{action:'bootstrap',username:'camilo',password},{email:owner});assert.equal(out.status,200);ownerCookie=out.cookie;assert.match(ownerCookie,/^__Host-jac_session=/);assert.match(out.r.headers.get('set-cookie'),/HttpOnly; Secure; SameSite=Lax/);assert.equal(await m.ownAuthReady(),true);
 assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_users').get().n,3);assert.match(sql.prepare('SELECT password_hash FROM payroll_users WHERE owner=1').get().password_hash,/^scrypt-v1:/);assert.notEqual(sql.prepare('SELECT password_hash FROM payroll_users WHERE owner=1').get().password_hash,password);
 assert.equal((await call(m.payrollApi,null,{email:owner,get:true})).status,401);assert.equal((await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).status,200);assert.equal((await call(m.authApi,{action:'bootstrap',username:'other',password},{cookie:ownerCookie})).status,403);
 const users=await call(m.usersApi,null,{cookie:ownerCookie,get:true});assert.equal(users.status,200);assert.ok(!JSON.stringify(users.body).includes('password_hash'));luisaId=users.body.users.find(u=>u.username==='luisa').id;assert.ok(users.body.users.filter(u=>!u.owner).every(u=>!u.permissions.includes('modifyClosed')));
});
test('contraseñas, enlaces de un solo uso y restricciones en servidor',async()=>{
 assert.equal((await call(m.authApi,{action:'login',username:'camilo',password:'incorrect'})).status,401);
 const first=await call(m.authApi,{action:'login',username:'CAMILO',password});assert.equal(first.status,200);
 let rows=(await call(m.usersApi,null,{cookie:ownerCookie,get:true})).body.users;let luisa=rows.find(u=>u.id===luisaId);
 const edit=await call(m.usersApi,{action:'update',id:luisaId,version:luisa.version,user:{...luisa,permissions:[]}},{cookie:ownerCookie});assert.equal(edit.status,200);
 const invite=await call(m.usersApi,{action:'invite',id:luisaId},{cookie:ownerCookie});assert.equal(invite.status,200);const token=invite.body.activationPath.split('=')[1];assert.ok(!sql.prepare('SELECT id FROM payroll_invitations').get().id.includes(token));
 const activation=await call(m.authApi,{action:'activate',token,password});assert.equal(activation.status,200);luisaCookie=activation.cookie;assert.equal((await call(m.authApi,{action:'activate',token,password})).status,400);
 const current=(await call(m.payrollApi,null,{cookie:luisaCookie,get:true})).body;assert.equal((await call(m.usersApi,null,{cookie:luisaCookie,get:true})).status,403);const next=structuredClone(current.data);next.employees[0].name+=' cambiado';assert.equal((await call(m.payrollApi,{action:'save',data:next,version:current.version},{cookie:luisaCookie})).status,403);
 assert.equal((await call(m.payrollApi,{action:'deleteEmployee',employeeId:next.employees[0].id,version:current.version},{cookie:luisaCookie})).status,403);
 assert.equal((await call(m.payrollApi,{action:'close',periodId:next.periods[0].id,version:current.version},{cookie:luisaCookie})).status,403);
 assert.equal((await call(m.exportApi,null,{cookie:luisaCookie,get:true})).status,403);assert.equal((await call(m.mailApi,{action:'send',periodId:next.periods[0].id},{cookie:luisaCookie})).status,403);assert.equal((await call(m.gmailApi,{},{cookie:luisaCookie})).status,403);
 assert.equal((await call(m.payrollApi,{action:'reopen',periodId:next.periods[0].id,version:current.version},{cookie:luisaCookie})).status,403);
 assert.equal((await call(m.usersApi,{action:'create',user:{username:'consulta',email:'read@example.invalid',name:'Consulta',active:true,permissions:[]}},{cookie:ownerCookie})).status,200);
});
test('solo Camilo concede y revoca corrección de cierres; protege historial y sesiones',async()=>{
 let current=(await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).body;
 const periodId=current.data.periods[0].id;
 const close=await call(m.payrollApi,{action:'close',periodId,version:current.version},{cookie:ownerCookie});assert.equal(close.status,200);current=close.body;
 const original=structuredClone(current.data.periods[0].snapshot);
 assert.equal((await call(m.payrollApi,{action:'reopen',periodId,version:current.version},{cookie:luisaCookie})).status,403);
 async function permissions(values){const row=(await call(m.usersApi,null,{cookie:ownerCookie,get:true})).body.users.find(u=>u.id===luisaId);const body={action:'update',id:row.id,version:row.version,user:{...row,permissions:values}};assert.equal((await call(m.usersApi,body,{cookie:luisaCookie})).status,403);assert.equal((await call(m.usersApi,body,{cookie:ownerCookie})).status,200);}
 await permissions(['modifyClosed']);assert.equal((await call(m.payrollApi,null,{cookie:luisaCookie,get:true})).status,401);
 luisaCookie=(await call(m.authApi,{action:'login',username:'luisa',password})).cookie;assert.ok(luisaCookie);
 const reopened=await call(m.payrollApi,{action:'reopen',periodId,version:current.version},{cookie:luisaCookie});assert.equal(reopened.status,200);current=reopened.body;
 assert.equal(current.data.periods[0].reopenedBy,'info@jacmusic.co');assert.deepEqual(current.data.periods[0].revisions[0],original);
 const changed=structuredClone(current.data);changed.periods[0].movements.push({id:'test-correction',employeeId:changed.employees[0].id,concept:'Corrección de ensayo',kind:'servicio',amount:80000,quantity:1,note:''});
 const tampered=structuredClone(changed);tampered.periods[0].revisions[0].total=0;assert.equal((await call(m.payrollApi,{action:'save',data:tampered,version:current.version},{cookie:luisaCookie})).status,400);
 const saved=await call(m.payrollApi,{action:'save',data:changed,version:current.version},{cookie:luisaCookie});assert.equal(saved.status,200);current=saved.body;
 const ordinary=structuredClone(current.data);ordinary.periods.push({...current.data.periods[0],id:'other',start:'2026-11-01',end:'2026-11-15',movements:[],ownerOnly:undefined,revisions:undefined,calculationBase:undefined,reopenedAt:undefined,reopenedBy:undefined});assert.equal((await call(m.payrollApi,{action:'save',data:ordinary,version:current.version},{cookie:luisaCookie})).status,403);
 // Revoking correction must block saving and closing even with ordinary payroll and close rights.
 const staleCookie=luisaCookie;await permissions(['payroll','close']);assert.equal((await call(m.payrollApi,{action:'close',periodId,version:current.version},{cookie:staleCookie})).status,401);
 luisaCookie=(await call(m.authApi,{action:'login',username:'luisa',password})).cookie;assert.ok(luisaCookie);
 const denied=structuredClone(current.data);denied.periods[0].movements[0].amount=90000;
 assert.equal((await call(m.payrollApi,{action:'save',data:denied,version:current.version},{cookie:luisaCookie})).status,403);assert.equal((await call(m.payrollApi,{action:'close',periodId,version:current.version},{cookie:luisaCookie})).status,403);
 await permissions(['modifyClosed']);luisaCookie=(await call(m.authApi,{action:'login',username:'luisa',password})).cookie;
 const corrected=await call(m.payrollApi,{action:'close',periodId,version:current.version},{cookie:luisaCookie});assert.equal(corrected.status,200);current=corrected.body;assert.equal(current.data.periods[0].snapshot.closedBy,'info@jacmusic.co');assert.deepEqual(current.data.periods[0].revisions[0],original);assert.ok(current.data.periods[0].snapshot.total>original.total);
 await permissions([]);luisaCookie=(await call(m.authApi,{action:'login',username:'luisa',password})).cookie;assert.equal((await call(m.payrollApi,{action:'reopen',periodId,version:current.version},{cookie:luisaCookie})).status,403);
});
test('cambio de permisos y desactivación revocan acceso; propietario protegido',async()=>{
 let rows=(await call(m.usersApi,null,{cookie:ownerCookie,get:true})).body.users;const luisa=rows.find(u=>u.id===luisaId),admin=rows.find(u=>u.owner);
 assert.equal((await call(m.usersApi,{action:'update',id:admin.id,version:admin.version,user:{...admin,active:false,permissions:[]}},{cookie:ownerCookie})).status,403);
 assert.equal((await call(m.usersApi,{action:'update',id:luisa.id,version:luisa.version,user:{...luisa,active:false}},{cookie:ownerCookie})).status,200);
 assert.equal((await call(m.payrollApi,null,{cookie:luisaCookie,get:true})).status,401);assert.equal((await call(m.authApi,{action:'login',username:'luisa',password})).status,401);
 assert.equal((await call(m.usersApi,{action:'invite',id:luisa.id},{cookie:ownerCookie})).status,400);
 const changed=await call(m.authApi,{action:'password',currentPassword:password,password:'7'.repeat(200)},{cookie:ownerCookie});assert.equal(changed.status,200);assert.equal((await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).status,401);ownerCookie=changed.cookie;assert.equal((await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).status,200);
 assert.equal((await call(m.authApi,{action:'login',username:'camilo',password:'7'.repeat(200)})).status,200);
 const short=await call(m.authApi,{action:'password',currentPassword:'7'.repeat(200),password:'2'},{cookie:ownerCookie});assert.equal(short.status,200);ownerCookie=short.cookie;assert.equal((await call(m.authApi,{action:'login',username:'camilo',password:'2'})).status,200);
 assert.equal((await call(m.authApi,{action:'logout'},{cookie:ownerCookie})).status,200);assert.equal((await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).status,401);
});
test('límite de intentos, expiración y matriz de permisos',async()=>{
 for(let n=0;n<10;n++)await m.rateLimit(new Request(base,{headers:{'cf-connecting-ip':'192.0.2.9'}}),'limited');await assert.rejects(()=>m.rateLimit(new Request(base,{headers:{'cf-connecting-ip':'192.0.2.9'}}),'limited'),/RATE_LIMIT/);
 assert.equal(await m.authenticatedSession('forged'),null);const row=sql.prepare('SELECT id FROM payroll_users WHERE owner=1').get();const token=await m.makeSession(row.id);sql.prepare('UPDATE payroll_sessions SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z',m.tokenHash(token));assert.equal(await m.authenticatedSession(token),null);
 const s={employees:[{name:'Original'}],settings:{},concepts:[],periods:[]},next=structuredClone(s),user={isOwner:false,permissions:['staff']};next.employees[0].name='Nuevo';assert.equal(m.savePermissionIssue(s,next,user),null);next.periods.push({id:'new'});assert.match(m.savePermissionIssue(s,next,user),/quincenas/);assert.equal(m.savePermissionIssue(s,next,{...user,isOwner:true}),null);
 const hash=m.hashPassword(password,globalThis.__authEnv.PAYROLL_AUTH_KEY);assert.equal(m.verifyPassword(password,hash,globalThis.__authEnv.PAYROLL_AUTH_KEY),true);assert.equal(m.verifyPassword(password+'x',hash,globalThis.__authEnv.PAYROLL_AUTH_KEY),false);
});
test('activaciones y restablecimientos simultáneos no invalidan el resultado ganador',async()=>{
 const id=sql.prepare('SELECT id FROM payroll_users WHERE username=?').get('consulta').id;
 const invites=await Promise.allSettled([m.inviteUser(id),m.inviteUser(id)]);assert.equal(invites.filter(r=>r.status==='fulfilled').length,1);const token=invites.find(r=>r.status==='fulfilled').value;assert.ok(await m.activationInfo(token));
 const activations=await Promise.allSettled([m.activateUser(token,password),m.activateUser(token,password+' otra')]);assert.equal(activations.filter(r=>r.status==='fulfilled').length,1);
 const session=await m.makeSession(id);assert.equal((await m.authenticatedSession(session)).id,id);assert.equal(await m.activationInfo(token),null);
});

test('contraseñas sin límites de longitud; el campo sigue siendo obligatorio',()=>{
 for(const value of ['2','12','7'.repeat(200)])assert.equal(m.passwordIssue(value),null);
 assert.equal(m.passwordIssue(''),'Ingresa una contraseña.');
 assert.throws(()=>m.hashPassword('',globalThis.__authEnv.PAYROLL_AUTH_KEY),/Ingresa una contraseña/);
});

test('eliminación exclusiva del propietario limpia cierres y envíos; admite recrear fechas y cero quincenas',async()=>{
 const ownerId=sql.prepare('SELECT id FROM payroll_users WHERE owner=1').get().id;ownerCookie='__Host-jac_session='+await m.makeSession(ownerId);
 const luisa=sql.prepare('SELECT * FROM payroll_users WHERE id=?').get(luisaId);assert.equal((await call(m.usersApi,{action:'update',id:luisa.id,version:luisa.version,user:{...m.publicUser(luisa),active:true,permissions:m.permissionKeys}},{cookie:ownerCookie})).status,200);luisaCookie='__Host-jac_session='+await m.makeSession(luisaId);
 let current=(await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).body;const period=current.data.periods[0];const periodId=period.id,removedDates=[period.start,period.end];
 const next=structuredClone(current.data);next.periods.push(m.newPeriod('2026-11-01','2026-11-15'));
 let result=await call(m.payrollApi,{action:'save',data:next,version:current.version},{cookie:ownerCookie});assert.equal(result.status,200);current=result.body;const otherId=current.data.periods[1].id;
 result=await call(m.payrollApi,{action:'close',periodId:otherId,version:current.version},{cookie:ownerCookie});assert.equal(result.status,200);current=result.body;
 const otherPeriod=structuredClone(current.data.periods[1]);const otherBatches=sql.prepare('SELECT * FROM payroll_mail_batches WHERE period_id=?').all(otherId);
 const deleteBody=()=>({action:'deletePeriod',periodId,confirmation:periodId,version:current.version});
 assert.equal((await call(m.payrollApi,deleteBody(),{cookie:luisaCookie})).status,403);
 assert.equal((await call(m.payrollApi,{...deleteBody(),confirmation:''},{cookie:ownerCookie})).status,400);
 assert.equal((await call(m.payrollApi,{...deleteBody(),periodId:'missing',confirmation:'missing'},{cookie:ownerCookie})).status,404);
 const without=structuredClone(current.data);without.periods=without.periods.filter(p=>p.id!==periodId);assert.equal((await call(m.payrollApi,{action:'save',data:without,version:current.version},{cookie:ownerCookie})).status,400);
 const jobs=sql.prepare('SELECT j.id FROM payroll_mail_jobs j JOIN payroll_mail_batches b ON b.id=j.batch_id WHERE b.period_id=?').all(periodId);assert.ok(jobs.length>0);assert.ok(sql.prepare('SELECT count(*) AS n FROM payroll_mail_batches WHERE period_id=?').get(periodId).n>1);
 await assert.rejects(()=>m.deletePayrollPeriod(current.data,current.version-1,periodId,owner),/CONFLICT/);assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs WHERE id=?').get(jobs[0].id).n,1);
 sql.prepare("UPDATE payroll_mail_jobs SET status='sending',started_at=? WHERE id=?").run(new Date().toISOString(),jobs[0].id);
 assert.equal((await call(m.payrollApi,deleteBody(),{cookie:ownerCookie})).status,409);assert.equal((await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).body.data.periods.length,2);
 sql.prepare("UPDATE payroll_mail_jobs SET status='sent' WHERE id=?").run(jobs[0].id);
 result=await call(m.payrollApi,deleteBody(),{cookie:ownerCookie});assert.equal(result.status,200);current=result.body;assert.equal(current.data.periods.length,1);assert.deepEqual(current.data.periods[0],otherPeriod);assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_batches WHERE period_id=?').get(periodId).n,0);for(const j of jobs)assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs WHERE id=?').get(j.id).n,0);assert.deepEqual(sql.prepare('SELECT * FROM payroll_mail_batches WHERE period_id=?').all(otherId),otherBatches);
 assert.equal((await call(m.exportApi,null,{cookie:ownerCookie,get:true,path:'?period='+periodId})).status,400);
 const recreated=m.newPeriod(...removedDates),again=structuredClone(current.data);again.periods.push(recreated);result=await call(m.payrollApi,{action:'save',data:again,version:current.version},{cookie:ownerCookie});assert.equal(result.status,200);current=result.body;assert.ok(current.data.periods.some(p=>p.id===recreated.id));assert.equal(recreated.snapshot,undefined);
 for(const id of [otherId,recreated.id]){result=await call(m.payrollApi,{action:'deletePeriod',periodId:id,confirmation:id,version:current.version},{cookie:ownerCookie});assert.equal(result.status,200);current=result.body;}
 const empty=(await call(m.payrollApi,null,{cookie:ownerCookie,get:true})).body;assert.deepEqual(empty.data.periods,[]);assert.equal(m.stateSchema.safeParse(empty.data).success,true);assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_periods').get().n,0);assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n,0);assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_batches').get().n,0);
 const fresh=structuredClone(empty.data);fresh.periods.push(m.newPeriod(...removedDates));assert.equal((await call(m.payrollApi,{action:'save',data:fresh,version:empty.version},{cookie:ownerCookie})).status,200);
});

test('Solo itinerarios: cuenta limitada no obtiene nómina, correos, exportaciones ni Agenda por API',async()=>{
 const create=await call(m.usersApi,{action:'create',user:{name:'Alex ficticio',username:'alex-scope-fixture',email:'alex-scope@example.invalid',active:true,itinerariesOnly:true,permissions:['export','payroll']}},{cookie:ownerCookie});assert.equal(create.status,200);
 let row=sql.prepare("SELECT * FROM payroll_users WHERE username='alex-scope-fixture'").get();assert.equal(row.itineraries_only,1);assert.deepEqual(JSON.parse(row.permissions),[]);
 sql.prepare('UPDATE payroll_users SET password_hash=? WHERE id=?').run(m.hashPassword('fixture-password',globalThis.__authEnv.PAYROLL_AUTH_KEY),row.id);const cookie='__Host-jac_session='+await m.makeSession(row.id);
 globalThis.__authHeaders=new Headers({host:'payroll.example.invalid',cookie});const identity=await m.payrollUser();assert.equal(identity.itinerariesOnly,true);assert.equal(m.can(identity,'export'),false);
 for(const api of [m.payrollApi,m.mailApi,m.exportApi,m.calendarApi])assert.equal((await call(api,null,{cookie,get:true})).status,403);
 for(const api of [m.payrollApi,m.mailApi,m.mobileApi,m.calendarApi])assert.equal((await call(api,{action:'anything'},{cookie})).status,403);
 const workspace=await call(m.mobileApi,null,{cookie,get:true,path:'/api/mobile/payroll?workspace=1'});assert.equal(workspace.status,200);assert.deepEqual(workspace.body.data.employees,[]);assert.deepEqual(workspace.body.data.periods,[]);assert.equal(workspace.body.user.itinerariesOnly,true);assert.deepEqual(workspace.body.employees,[]);
 assert.equal((await call(m.mobileApi,null,{cookie,get:true,path:'/api/mobile/payroll?period=known'})).status,403);
 let pub=(await call(m.usersApi,null,{cookie:ownerCookie,get:true})).body.users.find(u=>u.id===row.id);assert.equal(pub.itinerariesOnly,true);
 const oldClient={...pub};delete oldClient.itinerariesOnly;assert.equal((await call(m.usersApi,{action:'update',id:row.id,version:pub.version,user:oldClient},{cookie:ownerCookie})).status,200);assert.equal(sql.prepare('SELECT itineraries_only FROM payroll_users WHERE id=?').get(row.id).itineraries_only,1,'Un cliente antiguo no puede quitar la restricción al guardar');assert.equal((await call(m.payrollApi,null,{cookie,get:true})).status,401,'El cambio de permisos revoca la sesión anterior');
});
