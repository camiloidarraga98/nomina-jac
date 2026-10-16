import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {noticeAttachment,allowedNotice} from '@/lib/notifications';
import {NoticeFailure} from '@/lib/notifications-core';
export const dynamic='force-dynamic';
export async function GET(req:Request){
 const u=await payrollUser();if(!u||u.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers:payrollHeaders});if(u.mediaOnly)return Response.json({error:'Tu cuenta solo tiene acceso a fotos y videos.'},{status:403,headers:payrollHeaders});
 try{const q=new URL(req.url).searchParams,{filename,mimeType,object}=await noticeAttachment(u,q.get('id')??'',q.get('file')??'');const actor=await payrollUser();if(!actor||actor.legacy||actor.mediaOnly||actor.id!==u.id)return Response.json({error:'Tu sesión cambió. Inicia sesión de nuevo.'},{status:401,headers:payrollHeaders});await allowedNotice(actor,q.get('id')??'');return new Response(object.body,{headers:{...payrollHeaders,'Content-Type':mimeType,'Content-Disposition':"inline; filename*=UTF-8''"+encodeURIComponent(filename),'X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; sandbox"}});}catch(e){return Response.json({error:e instanceof NoticeFailure?e.message:'No se pudo abrir el archivo.'},{status:e instanceof NoticeFailure?e.status:502,headers:payrollHeaders});}
}
