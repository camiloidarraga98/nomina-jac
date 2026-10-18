import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {expenseFeed,submitExpense,reviewExpense} from '@/lib/travel-expenses';
import {hasSection} from '@/lib/payroll-permissions';
import {noticeOwner} from '@/lib/notifications';
import {NoticeFailure} from '@/lib/notifications-core';
import {boundedNoticeJSON} from '@/lib/notice-files';
export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});
const failure=(e:unknown)=>reply({error:e instanceof NoticeFailure?e.message:'No pudimos guardar. Conserva tus datos e intenta de nuevo.'},e instanceof NoticeFailure?e.status:502);
export async function GET(req:Request){const u=await payrollUser();if(!u||u.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);if(!hasSection(u,'itineraries'))return reply({error:'Tu cuenta no tiene acceso a gastos de viaje.'},403);try{const data=await expenseFeed(u,new URL(req.url).searchParams.get('cursor')??''),current=await payrollUser();if(!current||current.id!==u.id||!hasSection(current,'itineraries'))return reply({error:'Tu sesión o permiso cambió. Inicia sesión de nuevo.'},403);return reply(data);}catch(e){return failure(e);}}
export async function POST(req:Request){
 const u=await payrollUser();if(!u||u.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);if(!hasSection(u,'itineraries'))return reply({error:'Tu cuenta no tiene acceso a gastos de viaje.'},403);
 if(req.headers.get('origin')!==new URL(req.url).origin)return reply({error:'Origen no autorizado.'},403);
 try{const review=new URL(req.url).searchParams.has('review');if(review&&!noticeOwner(u))throw new NoticeFailure('Solo un administrador puede revisar gastos.',403);
 const input=await boundedNoticeJSON(req),authorize=async()=>{const actor=await payrollUser();return !!actor&&hasSection(actor,'itineraries')&&!actor.legacy&&actor.id===u.id&&(!review||noticeOwner(actor));};
 if(review){await reviewExpense(u,input,authorize);return reply({ok:true});}return reply({id:await submitExpense(u,input,authorize)});
 }catch(e){return failure(e);}
}
