import {database} from '@/db/raw';
import {initialPayroll} from './payroll-seed';
import type {PayrollState,Period} from './payroll';
export async function readPayroll(){
 const db=database();
 // A batch gives a consistent revision and period set during simultaneous saves.
 let result=await db.batch([db.prepare('SELECT data,version FROM payroll_state WHERE id = ?').bind('jac'),db.prepare('SELECT data FROM payroll_periods ORDER BY start,id')]);
 let row=result[0].results[0] as {data:string;version:number}|undefined;
 if(!row){await db.prepare('INSERT OR IGNORE INTO payroll_state (id,data,version,updated_at,updated_by) VALUES (?,?,1,?,?)').bind('jac',JSON.stringify(initialPayroll()),new Date().toISOString(),'initialization').run();result=await db.batch([db.prepare('SELECT data,version FROM payroll_state WHERE id = ?').bind('jac'),db.prepare('SELECT data FROM payroll_periods ORDER BY start,id')]);row=result[0].results[0] as {data:string;version:number}|undefined;}
 if(!row)throw new Error('No se pudo cargar la nómina.');
 const data=JSON.parse(row.data) as PayrollState;
 if(result[1].results.length)data.periods=result[1].results.map(r=>JSON.parse(String((r as {data:string}).data)) as Period);
 return {data,version:row.version};
}
export async function writePayroll(data:PayrollState,version:number,actor:string,extras?:(db:D1Database,nonce:string)=>D1PreparedStatement[],deletingPeriodId?:string){
 const db=database(),nonce=crypto.randomUUID(),main={...data,periods:[]};
 // Every statement is guarded by this unique nonce. A stale revision cannot write any period.
 const sendCutoff=new Date(Date.now()-120000).toISOString();
 const sendGuard=deletingPeriodId?" AND NOT EXISTS (SELECT 1 FROM payroll_mail_jobs j JOIN payroll_mail_batches b ON b.id=j.batch_id WHERE b.period_id=? AND j.status='sending' AND (j.started_at IS NULL OR j.started_at>?))":'';
 const writes=[db.prepare('UPDATE payroll_state SET data = ?, version = version + 1, updated_at = ?, updated_by = ?, write_nonce = ? WHERE id = ? AND version = ?'+sendGuard).bind(JSON.stringify(main),new Date().toISOString(),actor,nonce,'jac',version,...(deletingPeriodId?[deletingPeriodId,sendCutoff]:[])),db.prepare('DELETE FROM payroll_periods WHERE EXISTS (SELECT 1 FROM payroll_state WHERE id = ? AND write_nonce = ?)').bind('jac',nonce)];
 for(const p of data.periods)writes.push(db.prepare('INSERT INTO payroll_periods (id,data,start) SELECT ?,?,? WHERE EXISTS (SELECT 1 FROM payroll_state WHERE id = ? AND write_nonce = ?)').bind(p.id,JSON.stringify(p),p.start,'jac',nonce));
 if(extras)writes.push(...extras(db,nonce));
 const result=await db.batch(writes);
 if(result[0].meta.changes!==1){const latest=await db.prepare('SELECT version FROM payroll_state WHERE id=?').bind('jac').first<{version:number}>();if(deletingPeriodId&&latest?.version===version)throw new Error('MAIL_SENDING');throw new Error('CONFLICT');}
 return {data,version:version+1};
}

export async function deletePayrollPeriod(data:PayrollState,version:number,periodId:string,actor:string){
 const next={...data,periods:data.periods.filter(p=>p.id!==periodId)};
 return writePayroll(next,version,actor,(db,nonce)=>[
  db.prepare('DELETE FROM payroll_mail_jobs WHERE batch_id IN (SELECT id FROM payroll_mail_batches WHERE period_id=?) AND EXISTS (SELECT 1 FROM payroll_state WHERE id=? AND write_nonce=?)').bind(periodId,'jac',nonce),
  db.prepare('DELETE FROM payroll_mail_batches WHERE period_id=? AND EXISTS (SELECT 1 FROM payroll_state WHERE id=? AND write_nonce=?)').bind(periodId,'jac',nonce),
 ],periodId);
}
