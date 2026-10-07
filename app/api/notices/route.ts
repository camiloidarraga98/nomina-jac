import {waitUntil} from 'cloudflare:workers';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {sessionToken} from '@/lib/payroll-auth-crypto';
import {noticeFeed,noticeItem,noticeOwner,saveManualNotice,deleteManualNotice,deleteItinerary,registerDevice,unregisterDevice,configureNotices,markNoticeRead,dispatchPush,importSlackFiles,retryImports,purgeNoticeAttachments} from '@/lib/notifications';
import {NoticeFailure} from '@/lib/notifications-core';
export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});
const failure=(e:unknown)=>reply({error:e instanceof NoticeFailure?e.message:'No pudimos completar la operación. Conserva tus datos e intenta de nuevo.'},e instanceof NoticeFailure?e.status:502);
export async function GET(req:Request){const u=await payrollUser();if(!u||u.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);try{const query=new URL(req.url).searchParams;if(query.has('item'))return reply({item:await noticeItem(u,query.get('item')??'')});const feed=await noticeFeed(u,query.get('cursor')??'');waitUntil(Promise.all([importSlackFiles(),purgeNoticeAttachments()]).catch(()=>{}));return reply(feed);}catch(e){return failure(e);}}
export async function POST(req:Request){
 const u=await payrollUser();if(!u||u.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);
 if(req.headers.get('origin')!==new URL(req.url).origin)return reply({error:'Origen no autorizado.'},403);
 try{
  const text=await req.text();if(text.length>16000)return reply({error:'Solicitud demasiado grande.'},413);const b=JSON.parse(text) as Record<string,unknown>;
  if(!b||Array.isArray(b)||typeof b!=='object')throw new NoticeFailure('Solicitud no válida.');
  const ownSession=async()=>{const actor=await payrollUser();return !!actor&&!actor.legacy&&actor.id===u.id;};
  if(b.action==='register'){await registerDevice(u,b,sessionToken(req.headers.get('cookie')??'',!/^(localhost|127\.0\.0\.1)$/.test(new URL(req.url).hostname)),ownSession);return reply({ok:true});}
  if(b.action==='unregister'){await unregisterDevice(u,b.id);return reply({ok:true});}
  if(b.action==='read'&&typeof b.id==='string'){await markNoticeRead(u,b.id);return reply({ok:true});}
  if(!noticeOwner(u))return reply({error:'Solo Camilo puede gestionar alertas, eliminar itinerarios y configurar la integración.'},403);
  const authorize=async()=>{const actor=await payrollUser();return !!actor&&actor.id===u.id&&noticeOwner(actor);};
  if(b.action==='deleteAlert'){await deleteManualNotice(u,b.id,b.confirmation,authorize);return reply({ok:true,notice:'Alerta eliminada.'});}
  if(b.action==='deleteItinerary'){await deleteItinerary(u,b.id,b.confirmation,authorize);return reply({ok:true,notice:'Itinerario eliminado.'});}
  if(b.action==='alert'){const id=await saveManualNotice(u,b.alert,authorize);waitUntil(dispatchPush().catch(()=>{}));return reply({id,notice:'Alerta guardada para los destinatarios elegidos.'});}
  if(b.action==='configure'&&typeof b.kind==='string')return reply({settings:await configureNotices(b.kind,b,authorize),notice:'Configuración guardada.'});
  if(b.action==='retry'){await retryImports();waitUntil(importSlackFiles().catch(()=>{}));return reply({notice:'Los PDF pendientes se volverán a procesar.'});}
  throw new NoticeFailure('La operación no es válida.');
 }catch(e){return failure(e);}
}
