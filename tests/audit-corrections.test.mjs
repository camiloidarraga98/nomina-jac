import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir} from 'node:fs/promises';
import {build} from 'esbuild';
const migrations=(await readdir('drizzle')).filter(file=>file.endsWith('.sql')).sort();
const sql=new DatabaseSync(':memory:');for(const file of migrations)sql.exec(await readFile('drizzle/'+file,'utf8'));
let batches=[],reads=[];
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const query=sql.prepare(this.text);return query.columns().length?{results:query.all(...this.args),meta:{changes:0}}:{results:[],meta:{changes:Number(query.run(...this.args).changes)}};}
 async first(){reads.push(this.text);return sql.prepare(this.text).get(...this.args)||null;}
 async all(){reads.push(this.text);return this.execute();}
 async run(){return this.execute();}
}
globalThis.__auditDB={prepare:text=>new Query(text),batch:async queries=>{batches.push(queries.map(q=>q.text));sql.exec('BEGIN');try{const out=queries.map(q=>q.execute());sql.exec('COMMIT');return out;}catch(error){sql.exec('ROLLBACK');throw error;}}};
const compiled=await build({stdin:{contents:"export * from './lib/payroll-store';export * from './lib/payroll-seed';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'isolated-db',setup(b){b.onResolve({filter:/^@\/db\/raw$/},()=>({path:'db',namespace:'fake'}));b.onLoad({filter:/.*/,namespace:'fake'},()=>({contents:'export const database=()=>globalThis.__auditDB;'}));}}]});
const m=await import('data:text/javascript;base64,'+Buffer.from(compiled.outputFiles[0].contents).toString('base64'));
test('editing one of 240 periods changes only that period and preserves closed bytes; stale writes remain atomic',async()=>{
 const current=await m.readPayroll(),data=current.data,template=data.periods[0];
 data.periods=Array.from({length:240},(_,i)=>({...structuredClone(template),id:'audit-'+i,status:i===239?'cerrada':'abierta',snapshot:i===239?{closedAt:'2026-10-01T00:00:00Z',opaque:'immutable historical snapshot'}:undefined}));
 const saved=await m.writePayroll(data,current.version,'fixture@example.invalid'),old=await m.readPayroll(),fresh=await m.readPayroll();
 const frozen=sql.prepare('SELECT data FROM payroll_periods WHERE id=?').get('audit-239').data;
 fresh.data.periods[0].title='One changed field';batches=[];reads=[];
 await m.writePayroll(fresh.data,fresh.version,'fixture@example.invalid');
 assert.equal(batches.at(-1).length,2,'one CAS and one period write');assert(!reads.some(q=>q==='SELECT id,data FROM payroll_periods'));
 assert.equal(sql.prepare('SELECT data FROM payroll_periods WHERE id=?').get('audit-239').data,frozen);
 old.data.periods[1].title='stale';await assert.rejects(()=>m.writePayroll(old.data,old.version,'fixture@example.invalid'),/CONFLICT/);
 assert.notEqual(JSON.parse(sql.prepare('SELECT data FROM payroll_periods WHERE id=?').get('audit-1').data).title,'stale');assert.equal(saved.version+1,(await m.readPayroll()).version);
});
test('individual reads avoid the history; weekly cost reads retain expenses outside the linked show periods',async()=>{
 let current=await m.readPayroll();current.data.periods[0].shows=[{id:'payroll-show',crmShowId:'crm-fixture'}];current.data.periods.find(p=>p.id==='audit-230').showExpenses=[{id:'expense',date:'2026-10-20',amount:999,showId:'unrelated'}];await m.writePayroll(current.data,current.version,'fixture@example.invalid');
 batches=[];const detail=await m.readPayrollPeriod('audit-0');assert.equal(detail.data.periods.length,1);assert(batches.flat().some(q=>q==='SELECT data FROM payroll_periods WHERE id=?'));
 const weekly=await m.readPayrollForShows(['crm-fixture'],{from:'2026-10-19',to:'2026-10-25'});assert.deepEqual(weekly.data.periods.map(p=>p.id).sort(),['audit-0','audit-230']);assert.equal(weekly.data.periods[1].showExpenses[0].amount,999);
});
test('fresh and incremental migrations preserve existing data and agree with the schema journal and snapshot',async()=>{
 const upgraded=new DatabaseSync(':memory:');for(const file of migrations.filter(f=>f<'0026'))upgraded.exec(await readFile('drizzle/'+file,'utf8'));
 upgraded.prepare("INSERT INTO payroll_periods(id,data,start) VALUES('retained','{\"snapshot\":\"unchanged\"}','2026-10-01')").run();
 for(const file of migrations.filter(f=>f>='0026'))upgraded.exec(await readFile('drizzle/'+file,'utf8'));
 assert.equal(upgraded.prepare("SELECT data FROM payroll_periods WHERE id='retained'").get().data,'{"snapshot":"unchanged"}');
 const journal=JSON.parse(await readFile('drizzle/meta/_journal.json','utf8'));assert.deepEqual(journal.entries.map(entry=>entry.tag+'.sql'),migrations);
 const snapshotIndex=String(journal.entries.at(-1).idx).padStart(4,'0');
 const snapshot=JSON.parse(await readFile('drizzle/meta/'+snapshotIndex+'_snapshot.json','utf8'));
 const tables=sql.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all().map(row=>row.name).sort();assert.deepEqual(Object.keys(snapshot.tables).sort(),tables);
 for(const table of tables){assert.deepEqual(upgraded.prepare('PRAGMA table_info('+table+')').all(),sql.prepare('PRAGMA table_info('+table+')').all());assert.deepEqual(Object.keys(snapshot.tables[table].columns).sort(),sql.prepare('PRAGMA table_info('+table+')').all().map(c=>c.name).sort());}
 assert(sql.prepare("EXPLAIN QUERY PLAN SELECT id FROM jac_media_r2_entries WHERE parent_id='root' ORDER BY (mime_type='application/vnd.google-apps.folder') DESC,created_at DESC,name,id LIMIT 101").all().every(row=>!row.detail.includes('TEMP B-TREE')));
 upgraded.close();
});
