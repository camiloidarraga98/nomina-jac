import {authenticatedSession} from './payroll-auth-store';
import {sessionToken} from './payroll-auth-crypto';
import {payrollHeaders} from './payroll-access';
import {canCrm,CrmFailure} from './crm-core';
import {crmGuard} from './crm-access';
import {reconciliationRequest} from './reconciliation-store';

const failure=(error:string,status:number)=>Response.json({error},{status,headers:payrollHeaders});

// Both the framework route and the Worker use this exact authentication path.
// Read only JAC's cookie from this request, never legacy identity or global headers.
export async function handleReconciliationHttp(req:Request){
 try{
  const url=new URL(req.url),secure=!/^(localhost|127\.0\.0\.1)$/.test(url.hostname);
  const user=await authenticatedSession(sessionToken(req.headers.get('cookie')||'',secure));
  if(!user)return failure('Inicia sesión con tu cuenta de JAC.',401);
  if(!canCrm(user))return failure('La conciliación está disponible solo para administradores del CRM.',403);
  if(req.method!=='GET'&&(req.headers.get('origin')!==url.origin||req.headers.get('sec-fetch-site')==='cross-site'))return failure('Origen no autorizado.',403);
  if(!['GET','POST','PATCH','DELETE'].includes(req.method))return failure('Método no permitido.',405);
  return await reconciliationRequest(req,user,crmGuard(req,user));
 }catch(error){return failure(error instanceof CrmFailure?error.message:'No pudimos completar la operación. Tus cambios guardados se conservan.',error instanceof CrmFailure?error.status:503);}
}
