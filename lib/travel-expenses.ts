import {z} from 'zod';
import {env} from 'cloudflare:workers';
import {database} from '@/db/raw';
import {hasSection,type AccessUser} from './payroll-permissions';
import {NoticeFailure} from './notifications-core';
import {manualNoticeSchema,decodeNoticeFiles} from './notice-files';
import {noticeOwner,purgeNoticeAttachments} from './notifications';
import {contentHash,stageTravelFiles,discardTravelFiles,uploadedGate,uploadedBindings} from './travel-files';
import {readPayroll,writePayroll} from './payroll-store';
import {stateSchema} from './payroll-schema';
const uuid=z.string().uuid(),date=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(s=>!Number.isNaN(Date.parse(s))&&new Date(s+'T12:00:00Z').toISOString().slice(0,10)===s);
const schema=z.object({id:uuid,concept:z.string().trim().min(2).max(120),amount:z.number().int().positive().max(1e9),expenseDate:date,note:z.string().trim().max(500),files:manualNoticeSchema.shape.files.min(1)}).strict();
type ExpenseRow={id:string;user_id:string;name:string;concept:string;amount:number;expense_date:string;note:string;hash:string;status:string;version:number;review_note:string;period_id:string;employee_id:string;created_at:string;reviewed_at:string};
export async function allowedExpense(u:AccessUser,id:string){
 if(!hasSection(u,'itineraries'))throw new NoticeFailure('Tu cuenta no tiene acceso a gastos de viaje.',403);if(!uuid.safeParse(id).success)throw new NoticeFailure('Gasto no disponible.',404);const row=await database().prepare('SELECT e.*,u.name FROM jac_travel_expenses e JOIN payroll_users u ON u.id=e.user_id WHERE e.id=? AND (e.user_id=? OR ?=1)').bind(id,u.id,noticeOwner(u)?1:0).first<ExpenseRow>();if(!row)throw new NoticeFailure('Gasto no disponible.',404);return row;}
export async function expenseFeed(u:AccessUser,cursor=''){
 if(!hasSection(u,'itineraries'))throw new NoticeFailure('Tu cuenta no tiene acceso a gastos de viaje.',403);
 if(cursor&&!/^\d{4}-\d{2}-\d{2}T[\d:.]+Z\|[a-f0-9-]{36}$/.test(cursor))throw new NoticeFailure('Actualiza el listado.');const [stamp,id]=cursor.split('|'),db=database();
 const all=(await db.prepare(`SELECT e.*,u.name FROM jac_travel_expenses e JOIN payroll_users u ON u.id=e.user_id WHERE (e.user_id=? OR ?=1) ${cursor?'AND (e.created_at<? OR (e.created_at=? AND e.id<?))':''} ORDER BY e.created_at DESC,e.id DESC LIMIT 41`).bind(u.id,noticeOwner(u)?1:0,...(cursor?[stamp,stamp,id]:[])).all<ExpenseRow>()).results,rows=all.slice(0,40);
 const attachments=rows.length?(await db.prepare(`SELECT id,notice_id,filename,mime_type,size FROM jac_notice_attachments WHERE state='ready' AND notice_id IN (${rows.map(()=>'?').join(',')}) ORDER BY id`).bind(...rows.map(x=>'expense:'+x.id)).all<{id:string;notice_id:string;filename:string;mime_type:string;size:number}>()).results:[];
 const payroll=noticeOwner(u)?await readPayroll():null,last=rows.at(-1);
 return {expenses:rows.map(r=>({id:r.id,userId:r.user_id,name:r.name,concept:r.concept,amount:r.amount,expenseDate:r.expense_date,note:r.note,status:r.status,version:r.version,reviewNote:r.review_note,periodId:r.period_id,employeeId:r.employee_id,createdAt:r.created_at,reviewedAt:r.reviewed_at,attachments:attachments.filter(a=>a.notice_id==='expense:'+r.id).map(a=>({id:a.id,filename:a.filename,mimeType:a.mime_type,size:a.size}))})),nextCursor:all.length>40&&last?last.created_at+'|'+last.id:'',reviewer:noticeOwner(u),employees:payroll?.data.employees.filter(e=>e.active&&!e.deleted).map(e=>({id:e.id,name:e.name}))??[],periods:payroll?.data.periods.filter(p=>p.status==='abierta'&&!p.ownerOnly).map(p=>({id:p.id,name:p.start+' — '+p.end}))??[]};
}
export async function submitExpense(u:AccessUser,input:unknown,authorize:()=>Promise<boolean>){
 if(!hasSection(u,'itineraries'))throw new NoticeFailure('Tu cuenta no tiene acceso a gastos de viaje.',403);
 const parsed=schema.safeParse(input);if(!parsed.success)throw new NoticeFailure('Revisa concepto, valor en pesos, fecha y comprobantes.');const p=parsed.data,files=decodeNoticeFiles(p.files),hash=await contentHash({...p,userId:u.id}),db=database();
 const prior=await db.prepare('SELECT user_id,hash FROM jac_travel_expenses WHERE id=?').bind(p.id).first<{user_id:string;hash:string}>();
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
 if(prior){if(prior.user_id!==u.id||prior.hash!==hash)throw new NoticeFailure('Esta solicitud ya guardó otro gasto. Abre un formulario nuevo.',409);return p.id;}
 const uploads=await stageTravelFiles(files),token=crypto.randomUUID();let committed=false;
 try{
  if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
  const gate='EXISTS(SELECT 1 FROM jac_travel_expenses WHERE id=? AND upload_token=?)';
  const result=await db.batch([
   db.prepare(`INSERT OR IGNORE INTO jac_travel_expenses(id,user_id,concept,amount,expense_date,note,hash,upload_token,created_at) SELECT ?,?,?,?,?,?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM jac_notices WHERE id=?)${uploadedGate(uploads)}`).bind(p.id,u.id,p.concept,p.amount,p.expenseDate,p.note,hash,token,new Date().toISOString(),p.id,...uploadedBindings(uploads)),
   ...uploads.map(f=>db.prepare(`UPDATE jac_notice_attachments SET state='ready',notice_id=? WHERE id=? AND state='staged' AND ${gate}`).bind('expense:'+p.id,f.id,p.id,token))
  ]);committed=result[0].meta.changes===1;
  const saved=await db.prepare('SELECT user_id,hash FROM jac_travel_expenses WHERE id=?').bind(p.id).first<{user_id:string;hash:string}>();if(saved?.hash!==hash||saved.user_id!==u.id)throw new NoticeFailure('No se pudo guardar el gasto. Conserva el formulario.',409);return p.id;
 }finally{if(!committed){await discardTravelFiles(uploads);await purgeNoticeAttachments();}}
}
const reviewSchema=z.object({id:uuid,version:z.number().int().positive(),decision:z.enum(['approve','reject']),reason:z.string().trim().max(500),employeeId:z.string().max(80),periodId:z.string().max(80)}).strict();
export async function reviewExpense(u:AccessUser,input:unknown,authorize:()=>Promise<boolean>){
 if(!noticeOwner(u))throw new NoticeFailure('Solo un administrador puede revisar gastos.',403);
 const parsed=reviewSchema.safeParse(input);if(!parsed.success)throw new NoticeFailure('Actualiza el gasto antes de revisarlo.');const p=parsed.data,item=await allowedExpense(u,p.id);
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
 // Exact retries return the same result, never insert a second reimbursement.
 if(item.status!=='pending'){
  if(item.status===(p.decision==='approve'?'approved':'rejected')&&item.review_note===p.reason&&(p.decision==='reject'||(item.employee_id===p.employeeId&&item.period_id===p.periodId)))return;
  throw new NoticeFailure('Este gasto ya fue revisado. Actualiza el listado.',409);
 }
 if(item.version!==p.version)throw new NoticeFailure('Este gasto cambió. Actualiza el listado.',409);
 const stamp=new Date().toISOString(),db=database();
 if(p.decision==='reject'){
  if(!p.reason)throw new NoticeFailure('Indica el motivo del rechazo.');
  const result=await db.prepare("UPDATE jac_travel_expenses SET status='rejected',version=version+1,review_note=?,reviewer_id=?,reviewed_at=? WHERE id=? AND version=? AND status='pending'").bind(p.reason,u.id,stamp,p.id,p.version).run();if(result.meta.changes!==1)throw new NoticeFailure('Este gasto ya fue revisado.',409);return;
 }
 const current=await readPayroll(),next=structuredClone(current.data),period=next.periods.find(p0=>p0.id===p.periodId),employee=next.employees.find(e=>e.id===p.employeeId&&e.active&&!e.deleted);
 if(!period||period.status!=='abierta'||period.ownerOnly||!employee||period.excludedEmployees.includes(employee.id))throw new NoticeFailure('Elige una persona activa y una quincena abierta sin correcciones de cierre.');
 if(period.movements.some(m=>m.id===item.id))throw new NoticeFailure('Este gasto ya figura en la nómina. Revisa la quincena.',409);
 period.movements.push({id:item.id,employeeId:employee.id,concept:item.concept,kind:'reintegro',quantity:1,amount:item.amount,note:('Gasto de viaje '+item.expense_date+' · '+item.name+(item.note?' · '+item.note:'')).slice(0,500)});
 if(!stateSchema.safeParse(next).success)throw new NoticeFailure('La quincena no admite este reintegro. Revisa sus datos.',409);
 if(!await authorize())throw new NoticeFailure('Tu sesión cambió.',403);
 try{await writePayroll(next,current.version,u.id,(db,nonce)=>[
  db.prepare("UPDATE jac_travel_expenses SET status='approved',version=version+1,review_note=?,reviewer_id=?,reviewed_at=?,employee_id=?,period_id=? WHERE id=? AND version=? AND status='pending' AND EXISTS(SELECT 1 FROM payroll_state WHERE id='jac' AND write_nonce=?)").bind(p.reason,u.id,stamp,p.employeeId,p.periodId,p.id,p.version,nonce)
 ],undefined,{sql:"EXISTS(SELECT 1 FROM jac_travel_expenses WHERE id=? AND version=? AND status='pending')",bindings:[p.id,p.version]});}catch(e){if(e instanceof Error&&e.message==='CONFLICT')throw new NoticeFailure('El gasto o la nómina cambió. Actualiza antes de reintentar.',409);throw e;}
}
export async function expenseAttachment(u:AccessUser,id:string,file:string){
 await allowedExpense(u,id);if(!uuid.safeParse(file).success)throw new NoticeFailure('Comprobante no disponible.',404);
 const get=()=>database().prepare("SELECT file_key,filename,mime_type FROM jac_notice_attachments WHERE id=? AND notice_id=? AND state='ready'").bind(file,'expense:'+id).first<{file_key:string;filename:string;mime_type:string}>();
 const row=await get();if(!row)throw new NoticeFailure('Comprobante no disponible.',404);const object=await env.BUCKET.get(row.file_key);if(!object)throw new NoticeFailure('Comprobante no disponible.',404);await allowedExpense(u,id);if(!await get())throw new NoticeFailure('Comprobante no disponible.',404);return {filename:row.filename,mimeType:row.mime_type,object};
}
