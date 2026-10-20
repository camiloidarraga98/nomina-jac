import {importCrmPeriods,crmLinkIssue} from '@/lib/crm-payroll';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {itineraryWorkspace} from '@/lib/itineraries-access';
import {readPayroll,readPayrollPeriod} from '@/lib/payroll-store';
import {mobileOverview,mobilePeriod} from '@/lib/payroll-mobile';
import {POST as payrollPost} from '@/app/api/payroll/route';
import {stateSchema} from '@/lib/payroll-schema';
import {savePermissionIssue} from '@/lib/payroll-permissions';
import {validateSave} from '@/lib/payroll-policy';
import {can,hasSection} from '@/lib/payroll-permissions';
import {payrollReadAuthorized} from '@/lib/payroll-section-guard';
import {applyMobileEdit,MobileEditError,type MobileEdit} from '@/lib/payroll-mobile-edits';

export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});

export async function GET(req:Request){
 const user=await payrollUser();
 // The native app requires a real account session. Never expose the development/legacy bootstrap.
 if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de nómina.'},401);
 const id=new URL(req.url).searchParams.get('period');
 if(!hasSection(user,'payroll')){if(id!==null)return reply({error:'Tu cuenta no tiene acceso a nómina.'},403);const data=itineraryWorkspace();return reply({...mobileOverview(data,0),user,...(new URL(req.url).searchParams.get('workspace')==='1'?{data}:{})});}
 if(id!==null&&(!id||id.length>80))return reply({error:'Selecciona una quincena válida.'},400);
 try{
  const {data,version}=await (id===null?readPayroll():readPayrollPeriod(id));
  if(!await payrollReadAuthorized(user))return reply({error:'Tu sesión o permiso cambió. Inicia sesión de nuevo.'},403);
  if(id!==null){
   const p=data.periods.find(p=>p.id===id);
   if(!p)return reply({error:'La quincena no existe. Actualiza el listado.'},404);
   return reply(mobilePeriod(data,p,version));
  }
  return reply({...mobileOverview(data,version),user,...(new URL(req.url).searchParams.get('workspace')==='1'?{data}:{})});
 }catch{
  console.error('Mobile payroll load failed');
  return reply({error:'No se pudo consultar la nómina. Intenta de nuevo.'},503);
 }
}

export async function POST(req:Request){
 const user=await payrollUser();
 if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de nómina.'},401);
 if(!hasSection(user,'payroll'))return reply({error:'Tu cuenta no tiene acceso a nómina.'},403);
 if(req.headers.get('origin')!==new URL(req.url).origin)return reply({error:'Origen no autorizado.'},403);
 try{
  if(Number(req.headers.get('content-length')||0)>8_000_000)return reply({error:'La solicitud es demasiado grande.'},413);
  const text=await req.text();if(text.length>8_000_000)return reply({error:'La solicitud es demasiado grande.'},413);
  const body=JSON.parse(text);
  if(!body||typeof body!=='object')return reply({error:'Solicitud inválida.'},400);
  if(['edit','remove','previewEdit'].includes(body.action)){
   const current=await readPayroll();
   if(!Number.isInteger(body.version)||body.version!==current.version)return reply({error:'Otra persona actualizó la nómina. Conserva tu formulario y actualiza antes de volver a guardar.'},409);
   if(!body.edit||typeof body.edit!=='object')return reply({error:'Revisa el formulario.'},400);
   const next=applyMobileEdit(current.data,body.edit as MobileEdit,body.action==='remove');
   const parsed=stateSchema.safeParse(next);if(!parsed.success)return reply({error:parsed.error.issues[0].message},400);
   const permissionIssue=savePermissionIssue(current.data,parsed.data,user);if(permissionIssue)return reply({error:permissionIssue},403);
   const linkIssue=crmLinkIssue(current.data,parsed.data);if(linkIssue)return reply({error:linkIssue},400);
   if(body.action==='previewEdit'){await importCrmPeriods(current.data,parsed.data);const complete=stateSchema.safeParse(parsed.data);if(!complete.success)return reply({error:complete.error.issues[0].message},400);}
   const issue=validateSave(current.data,parsed.data,user.email,can(user,'modifyClosed'));if(issue)return reply({error:issue},400);
   if(body.action==='previewEdit'){
    if(!await payrollReadAuthorized(user))return reply({error:'Tu sesión o permiso cambió. Inicia sesión de nuevo.'},403);
    const id=body.edit.periodId??(body.edit.kind==='period'?body.edit.record?.id:undefined),p=parsed.data.periods.find(p=>p.id===id);
    return reply({data:parsed.data,version:current.version,detail:p?mobilePeriod(parsed.data,p,current.version):null});
   }
   // The shared endpoint performs the final CAS, validation and guarded writes.
   return payrollPost(sharedRequest(req,{action:'save',version:body.version,data:parsed.data}));
  }
  if(!['close','reopen','deletePeriod','deleteEmployee','restoreEmployee'].includes(body.action))return reply({error:'Acción inválida.'},400);
  return payrollPost(sharedRequest(req,body));
 }catch(e){
  if(e instanceof MobileEditError||e instanceof SyntaxError||e instanceof TypeError)return reply({error:e instanceof MobileEditError?e.message:'Revisa los datos del formulario.'},400);
  console.error('Mobile payroll operation failed');return reply({error:'No se pudo completar la operación. Conserva tus cambios e intenta de nuevo.'},503);
 }
}

function sharedRequest(req:Request,body:unknown){
 const url=new URL(req.url);url.pathname='/api/payroll';url.search='';
 const headers=new Headers(req.headers);headers.delete('content-length');headers.set('content-type','application/json');
 return new Request(url,{method:'POST',headers,body:JSON.stringify(body)});
}
