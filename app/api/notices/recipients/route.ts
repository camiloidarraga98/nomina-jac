import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {noticeOwner,noticeRecipientRoster} from '@/lib/notifications';
import {NoticeFailure} from '@/lib/notifications-core';

export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});

// Reading the composer roster must not import Slack documents or send notices.
export async function GET(){
 const user=await payrollUser();
 if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);
 if(!noticeOwner(user))return reply({error:'Solo un administrador puede consultar destinatarios.'},403);
 const identity=JSON.stringify(user);
 try{
  const roster=await noticeRecipientRoster(user),current=await payrollUser();
  if(!current||current.legacy||!noticeOwner(current)||JSON.stringify(current)!==identity)return reply({error:'Tu sesión o permiso cambió. Inicia sesión de nuevo.'},403);
  return reply(roster);
 }catch(error){return reply({error:error instanceof NoticeFailure?error.message:'No se pudo actualizar la lista de destinatarios.'},error instanceof NoticeFailure?error.status:502);}
}
