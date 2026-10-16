import {waitUntil} from 'cloudflare:workers';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {noticeOwner,updateItinerary,publishManualNotice,dispatchPush} from '@/lib/notifications';
import {NoticeFailure} from '@/lib/notifications-core';
import {boundedNoticeJSON} from '@/lib/notice-files';
export const dynamic='force-dynamic';
export async function POST(req:Request){
 const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});
 const u=await payrollUser();if(!u||u.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);if(u.mediaOnly)return reply({error:'Tu cuenta solo tiene acceso a fotos y videos.'},403);
 if(req.headers.get('origin')!==new URL(req.url).origin||!noticeOwner(u))return reply({error:'Solo un administrador puede publicar alertas e itinerarios desde JAC.'},403);
 try{const input=await boundedNoticeJSON(req);const id=await (new URL(req.url).searchParams.has('update')?updateItinerary:publishManualNotice)(u,input,async()=>{const actor=await payrollUser();return !!actor&&actor.id===u.id&&noticeOwner(actor);});waitUntil(dispatchPush().catch(()=>{}));return reply({id});}catch(e){return reply({error:e instanceof NoticeFailure?e.message:'No se pudo guardar. Conserva el formulario e intenta de nuevo.'},e instanceof NoticeFailure?e.status:502);}
}
