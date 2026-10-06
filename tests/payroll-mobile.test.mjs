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
const bundle=await build({stdin:{contents:"export * as api from './app/api/mobile/payroll/route';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-store';export * from './lib/payroll';export * from './lib/payroll-mobile';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'mobile-platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__mobileEnv;':'export const headers=async()=>globalThis.__mobileHeaders;',loader:'js'}));}}]});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
const base='https://mobile.example.invalid';
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
