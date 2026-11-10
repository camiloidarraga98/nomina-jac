import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {canCrm,CrmFailure} from '@/lib/crm-core';
import {crmGuard} from '@/lib/crm-access';
import {reconciliationRequest} from '@/lib/reconciliation-store';

export const dynamic='force-dynamic';
const failure=(error:string,status:number)=>Response.json({error},{status,headers:payrollHeaders});
async function handle(req:Request){
 const user=await payrollUser();
 if(!user||user.legacy)return failure('Inicia sesión con tu cuenta de JAC.',401);
 if(!canCrm(user))return failure('La conciliación está disponible solo para administradores del CRM.',403);
 if(req.method!=='GET'&&(req.headers.get('origin')!==new URL(req.url).origin||req.headers.get('sec-fetch-site')==='cross-site'))return failure('Origen no autorizado.',403);
 try{return await reconciliationRequest(req,user,crmGuard(req,user));}
 catch(error){return failure(error instanceof CrmFailure?error.message:'No pudimos completar la operación. Tus cambios guardados se conservan.',error instanceof CrmFailure?error.status:503);}
}
export const GET=handle;
export const POST=handle;
export const PATCH=handle;
export const DELETE=handle;
