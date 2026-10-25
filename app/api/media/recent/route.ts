import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard} from '@/lib/media-drive';
import {r2RecentPhotos} from '@/lib/media-r2-gallery';
import {MediaFailure} from '@/lib/media-core';

export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});

export async function GET(req:Request){
 const user=await payrollUser();
 if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);
 try{
  const identity=JSON.stringify(user),result=await r2RecentPhotos(mediaGuard(req,user));
  const current=await payrollUser();
  if(!current||current.legacy||JSON.stringify(current)!==identity)throw new MediaFailure('Tu sesión o permiso cambió. Inicia sesión de nuevo.',403);
  return reply(result);
 }catch(error){return reply({error:error instanceof MediaFailure?error.message:'No pudimos consultar las fotos recientes. Intenta de nuevo.'},error instanceof MediaFailure?error.status:503);}
}
