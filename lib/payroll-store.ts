import {database} from '@/db/raw';
import {initialPayroll} from './payroll-seed';
import type {PayrollState,Period} from './payroll';
// Immutable bytes observed by each read, even if its caller edits that object.
// A WeakMap is request-local ownership, not a cross-user response cache.
const observedPeriods=new WeakMap<PayrollState,{version:number;periods:Map<string,string>}>();
export async function readPayroll(){
 const db=database();
 // A batch gives a consistent revision and period set during simultaneous saves.
 let result=await db.batch([db.prepare('SELECT data,version FROM payroll_state WHERE id = ?').bind('jac'),db.prepare('SELECT id,data FROM payroll_periods ORDER BY start,id')]);
 let row=result[0].results[0] as {data:string;version:number}|undefined;
 if(!row){await db.prepare('INSERT OR IGNORE INTO payroll_state (id,data,version,updated_at,updated_by) VALUES (?,?,1,?,?)').bind('jac',JSON.stringify(initialPayroll()),new Date().toISOString(),'initialization').run();result=await db.batch([db.prepare('SELECT data,version FROM payroll_state WHERE id = ?').bind('jac'),db.prepare('SELECT id,data FROM payroll_periods ORDER BY start,id')]);row=result[0].results[0] as {data:string;version:number}|undefined;}
 if(!row)throw new Error('No se pudo cargar la nómina.');
 const data=JSON.parse(row.data) as PayrollState;
 if(result[1].results.length)data.periods=result[1].results.map(r=>JSON.parse(String((r as {data:string}).data)) as Period);
 observedPeriods.set(data,{version:row.version,periods:new Map(result[1].results.map(r=>{const record=r as {id:string;data:string};return [record.id,record.data];}))});
 return {data,version:row.version};
}
export async function readPayrollPeriod(id:string){
 const db=database(),rows=await db.batch([db.prepare('SELECT data,version FROM payroll_state WHERE id=?').bind('jac'),db.prepare('SELECT data FROM payroll_periods WHERE id=?').bind(id)]);
 const state=rows[0].results[0] as {data:string;version:number}|undefined;
 if(!state){const initial=await readPayroll();return {...initial,data:{...initial.data,periods:initial.data.periods.filter(p=>p.id===id)}};}
 const data=JSON.parse(state.data) as PayrollState,period=rows[1].results[0] as {data:string}|undefined;
 data.periods=period?[JSON.parse(period.data) as Period]:(data.periods??[]).filter(p=>p.id===id);
 return {data,version:state.version};
}
// Weekly CRM summaries need costs, not the entire editing catalogue. Keep one
// consistent state revision and load only periods linked to the requested shows.
export async function readPayrollForShows(ids:string[],range?:{from:string;to:string}){
 const db=database(),wanted=JSON.stringify(ids);
 const rows=await db.batch([db.prepare("SELECT data,version FROM payroll_state WHERE id='jac'"),db.prepare(`SELECT data FROM payroll_periods p WHERE EXISTS(SELECT 1 FROM json_each(p.data,'$.shows') s JOIN json_each(?) wanted ON json_extract(s.value,'$.crmShowId')=wanted.value) OR p.id IN (SELECT l.period_id FROM jac_crm_payroll_links l JOIN json_each(?) wanted ON wanted.value=l.show_id) OR EXISTS(SELECT 1 FROM json_each(p.data,'$.showExpenses') e WHERE json_extract(e.value,'$.date') BETWEEN ? AND ?) ORDER BY start,id`).bind(wanted,wanted,range?.from??'',range?.to??'')]);
 const row=rows[0].results[0] as {data:string;version:number}|undefined;if(!row)return {data:null,version:0};
 const data=JSON.parse(row.data) as PayrollState;
 data.periods=rows[1].results.length?rows[1].results.map(r=>JSON.parse((r as {data:string}).data)):(data.periods??[]).filter(p=>p.shows.some(show=>ids.includes(show.crmShowId||''))||!!range&&p.showExpenses?.some(e=>e.date>=range.from&&e.date<=range.to));
 return {data,version:row.version};
}
export async function writePayroll(data:PayrollState,version:number,actor:string,extras?:(db:D1Database,nonce:string)=>D1PreparedStatement[],deletingPeriodId?:string,guard?:{sql:string;bindings:(string|number)[]},source?:PayrollState){
 const db=database(),nonce=crypto.randomUUID(),main={...data,periods:[]};
 const observed=observedPeriods.get(source??data);
 const previous=observed?.version===version?observed.periods:new Map((await db.prepare('SELECT id,data FROM payroll_periods').all<{id:string;data:string}>()).results.map(r=>[r.id,r.data]));
 // Every statement is guarded by this unique nonce. A stale revision cannot write any period.
 const sendCutoff=new Date(Date.now()-120000).toISOString();
 const sendGuard=deletingPeriodId?" AND NOT EXISTS (SELECT 1 FROM payroll_mail_jobs j JOIN payroll_mail_batches b ON b.id=j.batch_id WHERE b.period_id=? AND j.status='sending' AND (j.started_at IS NULL OR j.started_at>?))":'';
 const writes=[db.prepare('UPDATE payroll_state SET data = ?, version = version + 1, updated_at = ?, updated_by = ?, write_nonce = ? WHERE id = ? AND version = ?'+sendGuard+(guard?' AND ('+guard.sql+')':'')).bind(JSON.stringify(main),new Date().toISOString(),actor,nonce,'jac',version,...(deletingPeriodId?[deletingPeriodId,sendCutoff]:[]),...(guard?.bindings??[]))];
 const retained=new Set(data.periods.map(p=>p.id));
 for(const id of previous.keys())if(!retained.has(id))writes.push(db.prepare('DELETE FROM payroll_periods WHERE id=? AND EXISTS(SELECT 1 FROM payroll_state WHERE id=? AND write_nonce=?)').bind(id,'jac',nonce));
 for(const p of data.periods){const bytes=JSON.stringify(p);if(previous.get(p.id)===bytes)continue;writes.push(db.prepare('INSERT INTO payroll_periods (id,data,start) SELECT ?,?,? WHERE EXISTS (SELECT 1 FROM payroll_state WHERE id = ? AND write_nonce = ?) ON CONFLICT(id) DO UPDATE SET data=excluded.data,start=excluded.start').bind(p.id,bytes,p.start,'jac',nonce));}
 if(extras)writes.push(...extras(db,nonce));
 const result=await db.batch(writes);
 if(result[0].meta.changes!==1){const latest=await db.prepare('SELECT version FROM payroll_state WHERE id=?').bind('jac').first<{version:number}>();if(deletingPeriodId&&latest?.version===version)throw new Error('MAIL_SENDING');throw new Error('CONFLICT');}
 observedPeriods.set(data,{version:version+1,periods:new Map(data.periods.map(p=>[p.id,JSON.stringify(p)]))});
 return {data,version:version+1};
}

export async function deletePayrollPeriod(data:PayrollState,version:number,periodId:string,actor:string,guard?:{sql:string;bindings:(string|number)[]}){
 const next={...data,periods:data.periods.filter(p=>p.id!==periodId)};
 return writePayroll(next,version,actor,(db,nonce)=>[
  db.prepare('DELETE FROM payroll_mail_jobs WHERE batch_id IN (SELECT id FROM payroll_mail_batches WHERE period_id=?) AND EXISTS (SELECT 1 FROM payroll_state WHERE id=? AND write_nonce=?)').bind(periodId,'jac',nonce),
  db.prepare('DELETE FROM payroll_mail_batches WHERE period_id=? AND EXISTS (SELECT 1 FROM payroll_state WHERE id=? AND write_nonce=?)').bind(periodId,'jac',nonce),
 ],periodId,guard,data);
}
