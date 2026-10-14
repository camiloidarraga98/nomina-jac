import {importCrmPeriods,crmLinkIssue,crmPayrollGuard} from '@/lib/crm-payroll';
import {waitUntil} from 'cloudflare:workers';
import {planMail} from '@/lib/payroll-mail-core';
import {mailWrites,drainMail} from '@/lib/payroll-mail';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {readPayroll,writePayroll,deletePayrollPeriod} from '@/lib/payroll-store';
import {stateSchema} from '@/lib/payroll-schema';
import {calculate,closeIssues,normalizeRehearsalMovements} from '@/lib/payroll';
import {reopenPeriod,deleteEmployee,validateSave} from '@/lib/payroll-policy';
import {can,savePermissionIssue} from '@/lib/payroll-permissions';
export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});
export async function GET(){const actor=await payrollUser();if(!actor)return reply({error:'Acceso no autorizado.'},401);if(actor.itinerariesOnly)return reply({error:'Tu cuenta no tiene acceso a nómina.'},403);try{return reply(await readPayroll());}catch(e){console.error('Payroll load failed',e);return reply({error:'No se pudo cargar la nómina. Intenta de nuevo.'},503);}}
export async function POST(req:Request){
 const user=await payrollUser();if(!user)return reply({error:'Acceso no autorizado.'},401);if(user.itinerariesOnly)return reply({error:'Tu cuenta no tiene acceso a nómina.'},403);
 const origin=req.headers.get('origin');if(origin!==new URL(req.url).origin)return reply({error:'Origen no autorizado.'},403);
 try{
  if(Number(req.headers.get('content-length')||0)>8_000_000)return reply({error:'La solicitud es demasiado grande.'},413);
  const text=await req.text();if(text.length>8_000_000)return reply({error:'La solicitud es demasiado grande.'},413);const body=JSON.parse(text);
  const current=await readPayroll();if(!Number.isInteger(body.version)||body.version!==current.version)return reply({error:'Otra persona actualizó la nómina. Tus cambios se conservan en pantalla. Recarga antes de volver a guardar.'},409);
  if(body.action==='deletePeriod'){
   if(!user.isOwner)return reply({error:'Solo un administrador puede eliminar una quincena.'},403);
   if(body.confirmation!==body.periodId||typeof body.periodId!=='string')return reply({error:'Confirma la eliminación de la quincena seleccionada.'},400);
   if(!current.data.periods.some(p=>p.id===body.periodId))return reply({error:'La quincena no existe.'},404);
   return reply(await deletePayrollPeriod(current.data,body.version,body.periodId,user.email));
  }
  if(body.action==='reopen'){
   if(!can(user,'modifyClosed'))return reply({error:'No tienes permiso para modificar cierres de quincena.'},403);
   const p=current.data.periods.find(p=>p.id===body.periodId);if(!p)return reply({error:'La quincena no existe.'},404);
   try{reopenPeriod(p,user.email,can(user,'modifyClosed'));}catch(e){return reply({error:(e as Error).message},400);}
   return reply(await writePayroll(current.data,body.version,user.email));
  }
  if(body.action==='deleteEmployee'||body.action==='restoreEmployee'){
   if(!can(user,'staff'))return reply({error:'No tienes permiso para modificar personal.'},403);
   try{if(body.action==='deleteEmployee')deleteEmployee(current.data,body.employeeId);else{const e=current.data.employees.find(e=>e.id===body.employeeId&&e.deleted);if(!e)throw new Error('La persona no está eliminada.');e.deleted=false;e.active=false;}}catch(e){return reply({error:(e as Error).message},400);}
   return reply(await writePayroll(current.data,body.version,user.email));
  }
  if(body.action==='close'){
   const p=current.data.periods.find(p=>p.id===body.periodId);if(!p||p.status!=='abierta')return reply({error:'La quincena ya está cerrada o no existe.'},400);
   if(!can(user,p.ownerOnly?'modifyClosed':'close'))return reply({error:p.ownerOnly?'No tienes permiso para modificar cierres de quincena.':'No tienes permiso para cerrar quincenas.'},403);
   p.movements=normalizeRehearsalMovements(p).movements;
   const issues=closeIssues(current.data,p);if(issues.length)return reply({error:issues.join(' ')},400);
   p.snapshot={...calculate(current.data,p),employees:structuredClone(p.calculationBase?.employees||current.data.employees),closedAt:new Date().toISOString(),closedBy:user.email};p.status='cerrada';
   const plan=planMail(p,current.data.employees);const saved=await writePayroll(current.data,body.version,user.email,(db,nonce)=>mailWrites(db,plan,{nonce}));
   let mailNotice='Consulta el estado de los desprendibles en Correos.';
   try{const sending=drainMail(plan.id);waitUntil(sending);mailNotice=(await sending).notice;}catch{console.error('Mail processing interrupted');}
   return reply({...saved,mailNotice});
  }
  if(body.action!=='save')return reply({error:'Acción inválida.'},400);
  const parsed=stateSchema.safeParse(body.data);if(!parsed.success)return reply({error:parsed.error.issues[0].message},400);
  const linkIssue=crmLinkIssue(current.data,parsed.data);if(linkIssue)return reply({error:linkIssue},400);
  const permissionIssue=savePermissionIssue(current.data,parsed.data,user);if(permissionIssue)return reply({error:permissionIssue},403);
  await importCrmPeriods(current.data,parsed.data);const complete=stateSchema.safeParse(parsed.data);if(!complete.success)return reply({error:complete.error.issues[0].message},400);
  const issue=validateSave(current.data,parsed.data,user.email,can(user,'modifyClosed'));if(issue)return reply({error:issue},400);
  return reply(await writePayroll(parsed.data,body.version,user.email,undefined,undefined,crmPayrollGuard(current.data,parsed.data)));
 }catch(e){if(e instanceof Error&&e.message==='MAIL_SENDING')return reply({error:'Hay desprendibles enviándose para esta quincena. Espera un momento y vuelve a intentar eliminarla.'},409);if(e instanceof Error&&e.message==='CONFLICT')return reply({error:'La nómina cambió mientras guardabas. Recarga y revisa tus cambios.'},409);console.error('Payroll save failed',e);return reply({error:'No se pudo guardar. Tus cambios siguen en pantalla.'},500);}
}
