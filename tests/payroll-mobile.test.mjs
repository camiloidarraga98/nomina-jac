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
globalThis.__mobileEnv={DB:{prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const out=qs.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(e){sql.exec('ROLLBACK');throw e;}}},PAYROLL_AUTH_KEY:'independent-mobile-test-key-at-least-32-characters'};
globalThis.__mobileHeaders=new Headers();
const bundle=await build({stdin:{contents:"export * as api from './app/api/mobile/payroll/route';export * as webApi from './app/api/payroll/route';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-store';export * from './lib/payroll';export * from './lib/payroll-mobile';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'mobile-platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__mobileEnv;export const waitUntil=p=>p.catch(()=>{});':'export const headers=async()=>globalThis.__mobileHeaders;',loader:'js'}));}}]});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
const base='https://mobile.example.invalid';
globalThis.fetch=async()=>{throw new Error('Las pruebas móviles no permiten red ni correos reales.');};
async function get(path='',token='',email=''){
 globalThis.__mobileHeaders=new Headers({host:'mobile.example.invalid',cookie:token?'__Host-jac_session='+token:'','oai-authenticated-user-email':email});
 const response=await m.api.GET(new Request(base+'/api/mobile/payroll'+path));
 return {status:response.status,body:await response.json(),headers:response.headers};
}

test('API nativa requiere sesión real, usa snapshots y conserva controles de acceso',async()=>{
 assert.equal((await get()).status,401);
 assert.equal((await get('','','camilo@mac2you.co')).status,401,'No admite el acceso legacy ni identidad suministrada por el cliente');
 const owner=await m.bootstrapOwner('native-owner','1');
 const token=await m.makeSession(owner);
 const initial=await m.readPayroll();
 const list=await get('',token);
 assert.equal(list.status,200);assert.equal(list.body.version,initial.version);
 assert.equal(list.body.user.isOwner,true);
 assert.equal(list.headers.get('cache-control'),'private, no-store, max-age=0');
 assert.equal(list.headers.get('vary'),'Cookie');
 assert.ok(!JSON.stringify(list.body).includes('password_hash'));
 assert.ok(!JSON.stringify(list.body).includes(token));
 const p=initial.data.periods[0];
 const opened=await get('?period='+encodeURIComponent(p.id),token);
 assert.deepEqual(opened.body.calculation,m.calculate(initial.data,p));
 assert.deepEqual(opened.body.closeIssues,m.closeIssues(initial.data,p));
 assert.equal((await get('?period=missing',token)).status,404);
 assert.equal((await get('?period=',token)).status,400);
 assert.equal((await get('?period='+('a'.repeat(81)),token)).status,400);
 p.snapshot={...m.calculate(initial.data,p),employees:structuredClone(initial.data.employees),closedAt:'2026-10-06T20:00:00Z',closedBy:'owner@example.invalid'};p.status='cerrada';
 const historical=structuredClone(p.snapshot);
 initial.data.employees.forEach(e=>{e.salary=999999999;e.name='Condición actual distinta';});
 const saved=await m.writePayroll(initial.data,initial.version,'mobile-test');
 const closed=await get('?period='+encodeURIComponent(p.id),token);
 assert.deepEqual(closed.body.calculation,historical);
 assert.deepEqual(closed.body.employees,historical.employees);
 assert.deepEqual(closed.body.closeIssues,[]);
 assert.equal(closed.body.version,saved.version);
 assert.equal((await m.readPayroll()).version,saved.version,'Las consultas no cambian la revisión');
 sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(owner);
 assert.equal((await get('',token)).status,401,'Cambiar permisos/version invalida también el acceso móvil');
 const renewed=await m.makeSession(owner);
 sql.prepare('UPDATE payroll_sessions SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z',m.tokenHash(renewed));
 assert.equal((await get('',renewed)).status,401);
});

test('estado vacío e identidades sin permiso de modificación conservan lectura autorizada',async()=>{
 const now='2026-10-06T20:00:00Z',id='mobile-reader';
 sql.prepare('INSERT INTO payroll_users (id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run(id,'reader','reader@example.invalid','Lector de prueba',m.hashPassword('x',globalThis.__mobileEnv.PAYROLL_AUTH_KEY),'[]',now,now);
 const token=await m.makeSession(id),current=await m.readPayroll();
 const next={...current.data,periods:[]};await m.writePayroll(next,current.version,'test-only');
 const response=await get('',token);
 assert.equal(response.status,200);assert.deepEqual(response.body.periods,[]);assert.equal(response.body.user.isOwner,false);assert.deepEqual(response.body.user.permissions,[]);
 sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(id);
 assert.equal((await get('',token)).status,401,'La desactivación se aplica a la app y a la web');
});

async function post(body,token,origin=base){
 globalThis.__mobileHeaders=new Headers({host:'mobile.example.invalid',cookie:token?'__Host-jac_session='+token:''});
 const response=await m.api.POST(new Request(base+'/api/mobile/payroll',{method:'POST',headers:{origin,cookie:token?'__Host-jac_session='+token:'','content-type':'application/json'},body:JSON.stringify(body)}));
 return {status:response.status,body:await response.json()};
}
async function actor(id,permissions=[]){
 const now=new Date().toISOString();
 sql.prepare('INSERT INTO payroll_users (id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run(id,id,id+'@example.invalid','Cuenta simulada',m.hashPassword('x',globalThis.__mobileEnv.PAYROLL_AUTH_KEY),JSON.stringify(permissions),now,now);
 return m.makeSession(id);
}
async function ownerSession(){return m.makeSession(sql.prepare('SELECT id FROM payroll_users WHERE owner=1').get().id);}
async function edit(token,kind,record,periodId,action='edit',version){
 return post({action,version:version??(await m.readPayroll()).version,edit:{kind,record,periodId}},token);
}
async function command(token,action,extra={}){return post({action,version:(await m.readPayroll()).version,...extra},token);}
async function fakePayroll(){
 const current=await m.readPayroll(),prototype=current.data.employees[0];
 const person=(id,category,values={})=>({...prototype,id,name:'Persona simulada '+id,document:'TEST-'+id,email:id+'@example.invalid',role:'Prueba',category,active:true,deleted:false,showRate:750000,kmRate:0,fixedService:0,withholding:.095,ica:0,salary:0,transport:0,cycle:'quincenal',monthlyHalf:2,nonSalary:0,contributionBase:1,incomeTax:0,solidarity:0,...values});
 const data={employees:[person('musica','musicos'),person('conductor-a','conductores',{kmRate:1000}),person('conductor-b','conductores',{kmRate:1250}),person('dependiente','administracion',{salary:1500000,transport:200000,pension:false}),person('sin-registros','tecnica',{showRate:300000})],concepts:[{id:'ensayo',name:'Ensayo simulado',kind:'servicio',amount:80000}],settings:{...current.data.settings,company:'Empresa simulada'},periods:[]};
 // A fresh, in-memory database only; replaces seeded data to make every write fictitious.
 sql.prepare('DELETE FROM payroll_mail_jobs').run();sql.prepare('DELETE FROM payroll_mail_batches').run();
 // Existing people cannot be removed through ordinary save, so reset this test-only state directly.
 sql.prepare('DELETE FROM payroll_periods').run();sql.prepare('UPDATE payroll_state SET data=? WHERE id=?').run(JSON.stringify(data),'jac');
 return m.readPayroll();
}

test('crear, previsualizar, editar y eliminar actividades reutiliza validación, cálculos y CAS',async()=>{
 await fakePayroll();const owner=await ownerSession(),reader=await actor('mobile-read-only'),writer=await actor('mobile-writer',['payroll']);
 const p={id:'native-period',start:'2027-02-01',end:'2027-02-15'};
 assert.equal((await edit(reader,'period',p)).status,403);
 assert.equal((await post({action:'edit',version:1,edit:{kind:'period',record:p}},'')).status,401);
 assert.equal((await post({action:'edit',version:1,edit:{kind:'period',record:p}},writer,'https://other.example.invalid')).status,403);
 const before=await m.readPayroll(),preview=await edit(writer,'period',p,undefined,'previewEdit');
 assert.equal(preview.status,200);assert.equal((await m.readPayroll()).version,before.version);assert.equal((await m.readPayroll()).data.periods.length,0);
 assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n,0,'La vista previa nunca prepara correo');
 assert.deepEqual(preview.body.detail.calculation,m.calculate(preview.body.data,preview.body.data.periods[0]));
 const created=await edit(writer,'period',p);assert.equal(created.status,200);
 assert.deepEqual(created.body.data.periods[0].shows,[]);assert.deepEqual(created.body.data.periods[0].excludedEmployees,[]);
 assert.equal((await edit(writer,'period',{...p,id:'overlap'})).status,400);
 assert.equal((await edit(writer,'period',{id:'invalid-date',start:'2027-02-30',end:'2027-02-31'})).status,400);
 assert.equal((await edit(writer,'period',{id:'stale',start:'2027-03-01',end:'2027-03-15'},undefined,'edit',before.version)).status,409);
 const show={id:'native-show',date:p.start,name:'Evento simulado',sale:1000000,participants:[{employeeId:'musica',amount:725000}]};
 assert.equal((await edit(writer,'show',show,p.id)).status,200);
 const route={id:'native-route',showId:show.id,date:show.date,name:show.name,km:120,drivers:[{employeeId:'conductor-a',rate:1000},{employeeId:'conductor-b',rate:1250}]};
 assert.equal((await edit(writer,'route',route,p.id)).status,200);
 const updated=await edit(writer,'show',{...show,name:'Evento renombrado',date:'2027-02-02'},p.id);assert.equal(updated.status,200);
 assert.equal(updated.body.data.periods[0].routes[0].name,'Evento renombrado');assert.equal(updated.body.data.periods[0].routes[0].date,'2027-02-02');
 const extra={id:'extra-route',kind:'extra',date:p.start,name:'Recorrido extra',km:10,drivers:route.drivers};
 assert.equal((await edit(writer,'route',extra,p.id)).status,200);
 const movement={id:'native-movement',employeeId:'musica',concept:'Comisión manual simulada',kind:'servicio',quantity:2,amount:80000,note:'Prueba sin producción'};
 assert.equal((await edit(writer,'movement',movement,p.id)).status,200);
 assert.equal((await edit(writer,'movement',{...movement,quantity:-1},p.id)).status,400);
 assert.equal((await edit(writer,'hours',{employeeId:'dependiente',counts:[1,2,3,4,5,6,7],days:12,vacations:50000,note:''},p.id)).status,200);
 const current=await m.readPayroll(),detail=await get('?period='+p.id,writer);
 assert.deepEqual(detail.body.calculation,m.calculate(current.data,current.data.periods[0]));
 const drivers=detail.body.calculation.rows.filter(r=>r.category==='conductores');
 assert.equal(drivers.find(r=>r.employeeId==='conductor-a').gross,130000);assert.equal(drivers.find(r=>r.employeeId==='conductor-b').gross,162500);
 const full=await get('?workspace=1',reader);assert.equal(full.status,200);assert.deepEqual(full.body.data,current.data);
 const remove=await post({action:'remove',version:current.version,edit:{kind:'show',periodId:p.id,id:show.id}},writer);
 assert.equal(remove.status,200);assert.equal(remove.body.data.periods[0].shows.length,0);
 assert.deepEqual(remove.body.data.periods[0].routes.map(r=>r.id),[extra.id],'Eliminar show elimina solo su recorrido compartido');
 for(const [kind,id] of [['movement',movement.id],['route',extra.id]])assert.equal((await post({action:'remove',version:(await m.readPayroll()).version,edit:{kind,periodId:p.id,id}},writer)).status,200);
 assert.equal((await edit(writer,'settings',current.data.settings)).status,200,'Sin diferencias no se exige permiso de reglas, igual que en la API compartida');
 assert.equal((await edit(writer,'settings',{...current.data.settings,hourDivisor:200})).status,403);
 assert.equal((await edit(writer,'employee',{...current.data.employees[0],showRate:500000})).status,403);
 assert.equal((await command(writer,'close',{periodId:p.id})).status,403);
 assert.equal((await command(writer,'deletePeriod',{periodId:p.id,confirmation:p.id})).status,403);
 assert.equal((await command(owner,'close',{periodId:p.id})).status,200);
 assert.ok(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n>0,'El cierre sigue preparando sus registros idempotentes');
});

test('cierres, condiciones históricas y permisos independientes siguen protegidos desde la app',async()=>{
 const owner=await ownerSession(),staff=await actor('mobile-staff',['staff']),rules=await actor('mobile-rules',['rules']),corrector=await actor('mobile-corrector',['modifyClosed']),ordinary=await actor('mobile-ordinary',['payroll','staff','rules','close']);
 let current=await m.readPayroll(),p=current.data.periods[0],snapshot=structuredClone(p.snapshot);
 assert.equal((await edit(ordinary,'movement',{id:'closed-edit',employeeId:'musica',concept:'No permitido',kind:'servicio',quantity:1,amount:1,note:''},p.id)).status,400);
 const employee=current.data.employees.find(e=>e.id==='dependiente');
 assert.equal((await edit(staff,'employee',{...employee,salary:9000000})).status,200);
 assert.equal((await edit(rules,'concept',{id:'native-concept',name:'Concepto nuevo',kind:'reintegro',amount:18000})).status,200);
 assert.equal((await edit(rules,'settings',{...current.data.settings,hourDivisor:200})).status,200);
 assert.deepEqual((await get('?period='+p.id,ordinary)).body.calculation,snapshot,'Cambiar tarifas vigentes no cambia cierres');
 assert.equal((await command(ordinary,'reopen',{periodId:p.id})).status,403);
 const reopened=await command(corrector,'reopen',{periodId:p.id});assert.equal(reopened.status,200);
 p=reopened.body.data.periods[0];assert.deepEqual(p.revisions,[snapshot]);assert.deepEqual(p.calculationBase.employees,snapshot.employees);assert.equal(p.ownerOnly,true);
 const historical=p.calculationBase.employees.find(e=>e.id==='dependiente');
 assert.equal((await edit(ordinary,'periodEmployee',{...historical,salary:1800000},p.id)).status,403);
 assert.equal((await edit(corrector,'periodEmployee',{...historical,salary:1800000},p.id)).status,200);
 assert.equal((await edit(corrector,'periodSettings',{...p.calculationBase.settings,hourDivisor:190},p.id)).status,200);
 current=await m.readPayroll();assert.equal(current.data.employees.find(e=>e.id==='dependiente').salary,9000000);assert.equal(current.data.settings.hourDivisor,200);
 assert.deepEqual(current.data.periods[0].revisions,[snapshot]);assert.equal(current.data.periods[0].calculationBase.settings.hourDivisor,190);
 assert.equal((await command(ordinary,'close',{periodId:p.id})).status,403);
 const closed=await command(corrector,'close',{periodId:p.id});assert.equal(closed.status,200);
 assert.deepEqual(closed.body.data.periods[0].revisions,[snapshot]);assert.equal(closed.body.data.periods[0].snapshot.employees.find(e=>e.id==='dependiente').salary,1800000);
 assert.equal((await command(staff,'deleteEmployee',{employeeId:'dependiente'})).status,200,'Eliminar personal vigente conserva su historia cerrada');
 assert.deepEqual((await get('?period='+p.id,owner)).body.calculation,closed.body.data.periods[0].snapshot);
 assert.equal((await command(staff,'restoreEmployee',{employeeId:'dependiente'})).status,200);
 assert.equal((await m.readPayroll()).data.employees.find(e=>e.id==='dependiente').active,false);
});

test('borrado móvil exige propietario, confirmación, revisión y protección de envíos; permite cero cortes',async()=>{
 const owner=await ownerSession(),current=await m.readPayroll(),p=current.data.periods[0];
 assert.equal((await command(owner,'deletePeriod',{periodId:p.id})).status,400);
 assert.equal((await post({action:'deletePeriod',periodId:p.id,confirmation:p.id,version:current.version-1},owner)).status,409);
 const job=sql.prepare('SELECT id FROM payroll_mail_jobs LIMIT 1').get();
 sql.prepare("UPDATE payroll_mail_jobs SET status='sending',started_at=? WHERE id=?").run(new Date().toISOString(),job.id);
 assert.equal((await command(owner,'deletePeriod',{periodId:p.id,confirmation:p.id})).status,409);
 assert.equal((await m.readPayroll()).data.periods.length,1);
 sql.prepare("UPDATE payroll_mail_jobs SET status='error' WHERE id=?").run(job.id);
 assert.equal((await command(owner,'deletePeriod',{periodId:p.id,confirmation:p.id})).status,200);
 assert.equal((await m.readPayroll()).data.periods.length,0);
 assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_batches').get().n,0);assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n,0);
 assert.equal((await edit(owner,'period',{id:'same-dates',start:p.start,end:p.end})).status,200);
});


test('ensayos antiguos bloqueados se consultan y cierran como honorarios; consultas no escriben ni envían',async()=>{
 const current=await fakePayroll(),owner=await ownerSession(),reader=await actor('ensayo-reader'),writer=await actor('ensayo-writer',['payroll']);
 const p=m.newPeriod('2027-04-01','2027-04-15');p.movements.push({id:'old-ensayo',employeeId:'musica',concept:'Ensayo',kind:'salarial',quantity:2,amount:87500,note:'Dato simulado anterior'});
 // Simulates a previously saved mistake, only in the disposable in-memory D1.
 await m.writePayroll({...current.data,periods:[p]},current.version,'fixture-only');
 const before=await m.readPayroll(),detail=await get('?period='+p.id,reader),row=detail.body.calculation.rows.find(r=>r.employeeId==='musica');
 assert.equal(detail.status,200);assert.equal(row.gross,175000);assert.equal(row.deductions,16625);assert.equal(row.net,158375);assert.equal(detail.body.period.movements[0].kind,'servicio');assert.deepEqual(detail.body.closeIssues,[]);
 assert.deepEqual(await m.readPayroll(),before,'Leer la proyección no cambia datos ni revisión');assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n,0);
 assert.equal((await command(writer,'close',{periodId:p.id})).status,403);assert.deepEqual(await m.readPayroll(),before);
 const snapshotText=JSON.stringify(p.movements);globalThis.__mobileHeaders=new Headers({host:'mobile.example.invalid',cookie:'__Host-jac_session='+owner});
 const response=await m.webApi.POST(new Request(base+'/api/payroll',{method:'POST',headers:{origin:base,cookie:'__Host-jac_session='+owner,'content-type':'application/json'},body:JSON.stringify({action:'close',periodId:p.id,version:before.version})}));
 assert.equal(response.status,200);const closed=await response.json(),stored=closed.data.periods[0];
 assert.equal(stored.status,'cerrada');assert.equal(stored.movements[0].kind,'servicio');assert.equal(stored.movements[0].amount,87500);assert.equal(stored.movements[0].quantity,2);assert.equal(stored.movements[0].note,'Dato simulado anterior');assert.equal(JSON.stringify(p.movements),snapshotText);
 assert.equal(stored.snapshot.rows.find(r=>r.employeeId==='musica').gross,175000);const jobs=sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n;assert.ok(jobs>0);
 assert.equal((await post({action:'close',periodId:p.id,version:before.version},owner)).status,409);assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n,jobs,'El reintento no duplica correos');
 const readClosed=await get('?period='+p.id,reader);assert.deepEqual(readClosed.body.calculation,stored.snapshot);
});

test('API web e iPhone impiden ensayos a salario fijo y normalizan solo la novedad editada',async()=>{
 const current=await fakePayroll(),writer=await actor('ensayo-editor',['payroll']),p=m.newPeriod('2027-05-01','2027-05-15');
 await m.writePayroll({...current.data,periods:[p]},current.version,'fixture-only');
 const movement={id:'new-ensayo',employeeId:'musica',concept:'ENSAYO',kind:'salarial',quantity:1,amount:80000,note:''};
 const before=await m.readPayroll(),preview=await edit(writer,'movement',movement,p.id,'previewEdit');assert.equal(preview.status,200);assert.equal(preview.body.detail.period.movements[0].kind,'servicio');assert.deepEqual(await m.readPayroll(),before);
 const saved=await edit(writer,'movement',movement,p.id);assert.equal(saved.status,200);assert.equal(saved.body.data.periods[0].movements[0].kind,'servicio');
 for(const kind of ['salarial','servicio','reintegro']){
  const latest=await m.readPayroll(),invalid={...movement,id:'invalid',employeeId:'dependiente',kind};
  const mobile=await edit(writer,'movement',invalid,p.id);assert.equal(mobile.status,400);assert.match(mobile.body.error,/salario fijo/);assert.deepEqual(await m.readPayroll(),latest);
  const data=structuredClone(latest.data);data.periods[0].movements.push(invalid);globalThis.__mobileHeaders=new Headers({host:'mobile.example.invalid',cookie:'__Host-jac_session='+writer});
  const response=await m.webApi.POST(new Request(base+'/api/payroll',{method:'POST',headers:{origin:base,cookie:'__Host-jac_session='+writer,'content-type':'application/json'},body:JSON.stringify({action:'save',version:latest.version,data})}));assert.equal(response.status,400);assert.match((await response.json()).error,/salario fijo/);assert.deepEqual(await m.readPayroll(),latest);
 }
 assert.equal(sql.prepare('SELECT count(*) AS n FROM payroll_mail_jobs').get().n,0);
});
