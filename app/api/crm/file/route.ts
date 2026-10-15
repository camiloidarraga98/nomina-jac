import {crmContactFile} from '@/lib/crm-workspace';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {crmGuard} from '@/lib/crm-access';
import {canCrm,CrmFailure} from '@/lib/crm-core';
import {crmReceipt} from '@/lib/crm-store';
export const dynamic='force-dynamic';
export async function GET(req:Request){const u=await payrollUser();if((!u||u.legacy)&&req.headers.get('sec-fetch-mode')==='navigate'){const q=new URL(req.url).searchParams,returnTo='/api/crm/file?'+new URLSearchParams({id:q.get('id')??'',...(q.has('file')?{file:q.get('file')!}:{}),...(q.has('contact')?{contact:q.get('contact')!}:{})});return new Response(null,{status:303,headers:{...payrollHeaders,Location:'/acceso?returnTo='+encodeURIComponent(returnTo)}});}if(!u||u.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers:payrollHeaders});if(!canCrm(u))return Response.json({error:'Comprobante no disponible.'},{status:403,headers:payrollHeaders});
 try{const q=new URL(req.url).searchParams,{object,filename,mimeType}=q.has('contact')?await crmContactFile(u,q.get('contact')??'',q.get('file')??'',crmGuard(req,u)):await crmReceipt(u,q.get('id')??'',q.get('file')??'',crmGuard(req,u));return new Response(object.body,{headers:{...payrollHeaders,'Content-Type':mimeType,'Content-Disposition':"inline; filename*=UTF-8''"+encodeURIComponent(filename),'Content-Security-Policy':"default-src 'none'; sandbox"}});}catch(e){return Response.json({error:e instanceof CrmFailure?e.message:'No pudimos abrir el comprobante.'},{status:e instanceof CrmFailure?e.status:502,headers:payrollHeaders});}
}
