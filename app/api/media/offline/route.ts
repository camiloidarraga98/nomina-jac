import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard,mediaGuardActive} from '@/lib/media-drive';
import {mediaCacheContext} from '@/lib/media-cache-context';
import {MediaFailure} from '@/lib/media-core';
export const dynamic='force-dynamic';
export async function GET(req:Request){
 const user=await payrollUser();
 if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers:payrollHeaders});
 try{
  const guard=mediaGuard(req,user),context=await mediaCacheContext(user);
  if(!context||!await mediaGuardActive(guard))throw new MediaFailure('Tu cuenta ya no tiene acceso a Fotografía.',403);
  return Response.json(context,{headers:payrollHeaders});
 }catch(e){return Response.json({error:'No se pudo validar el acceso a Fotografía.'},{status:e instanceof MediaFailure?e.status:503,headers:payrollHeaders});}
}
