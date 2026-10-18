import {agendaCacheContext} from '@/lib/agenda-cache-context';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {agendaConnection,readAgenda,availableAgendaCalendars,selectAgendaCalendar,disconnectAgenda,saveAgendaEvent,CalendarFailure} from '@/lib/calendar';
import {startCalendarOauth} from '@/lib/calendar-oauth';
import {hasSection} from '@/lib/payroll-permissions';
import {canEditAgenda} from '@/lib/calendar-permissions';
export const dynamic='force-dynamic';
const headers={...payrollHeaders,'Referrer-Policy':'no-referrer'};
const failure=(e:unknown)=>Response.json({...(e instanceof CalendarFailure&&e.discardCachedAgenda?{discardCachedAgenda:true}:{}),error:e instanceof CalendarFailure?e.message:'No pudimos completar la operación de Agenda. Tus datos siguen en el formulario; intenta de nuevo.'},{status:e instanceof CalendarFailure?e.status:502,headers});
export async function GET(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers});
 if(!hasSection(user,'calendar'))return Response.json({error:'Tu cuenta no tiene acceso a Agenda.'},{status:403,headers});
 const cacheContext=await agendaCacheContext(user);if(req.headers.has('X-JAC-Agenda-Scope')&&req.headers.get('X-JAC-Agenda-Scope')!==cacheContext?.scope)return Response.json({error:'La sesión cambió. Vuelve a entrar a Agenda.'},{status:401,headers});
 try{
  const url=new URL(req.url);
  if(url.searchParams.get('action')==='calendars'){
   if(!user.isOwner)return Response.json({error:'Solo un administrador puede elegir el calendario.'},{status:403,headers});
   return Response.json({calendars:await availableAgendaCalendars()},{headers});
  }
  const data=await readAgenda(url.searchParams.get('month')??undefined);
  const current=await payrollUser();if(!current||current.id!==user.id||JSON.stringify(current)!==JSON.stringify(user))return Response.json({error:'Tu sesión o permiso cambió. Inicia sesión de nuevo.'},{status:401,headers});
  return Response.json({...data,canEditEvents:data.canEditEvents&&canEditAgenda(current)},{headers:{...headers,...(cacheContext?{'X-JAC-Agenda-Scope':cacheContext.scope}:{})}});
 }catch(e){return failure(e);}
}
export async function POST(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers});
 if(!hasSection(user,'calendar'))return Response.json({error:'Tu cuenta no tiene acceso a Agenda.'},{status:403,headers});
 const cacheContext=await agendaCacheContext(user);if(req.headers.has('X-JAC-Agenda-Scope')&&req.headers.get('X-JAC-Agenda-Scope')!==cacheContext?.scope)return Response.json({error:'La sesión cambió. Vuelve a entrar a Agenda.'},{status:401,headers});
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Origen no autorizado.'},{status:403,headers});
 try{
  const body=await req.json() as Record<string,unknown>;
  if(!body||Array.isArray(body)||typeof body!=='object')throw new CalendarFailure('La operación no es válida.');
  const eventAction=body.action==='createEvent'||body.action==='updateEvent';
  if(eventAction?!canEditAgenda(user):!user.isOwner)return Response.json({error:eventAction?'Solo administradores, Luisa y Paula pueden editar eventos.':'Solo un administrador puede configurar Agenda.'},{status:403,headers});
  if(body.action==='connect'){
   const start=await startCalendarOauth(user,req.headers.get('cookie')||'',body.native===true);
   return Response.json({url:start.url,...('nonce' in start?{nonce:start.nonce}:{})},{headers:{...headers,...('cookie' in start?{'Set-Cookie':start.cookie}:{})}});
  }
  if(!Number.isSafeInteger(body.revision)||Number(body.revision)<0)throw new CalendarFailure('Actualiza Agenda antes de guardar.');
  if(body.action==='createEvent'||body.action==='updateEvent')return Response.json(await saveAgendaEvent(body.action,body,async()=>{const actor=await payrollUser();return !!actor&&actor.id===user.id&&canEditAgenda(actor);}),{headers});
  if(body.action==='select'&&typeof body.calendarId==='string'&&body.calendarId.length>0&&body.calendarId.length<=1024)await selectAgendaCalendar(body.calendarId,Number(body.revision));
  else if(body.action==='disconnect')await disconnectAgenda(Number(body.revision));
  else throw new CalendarFailure('La operación no es válida.');
  return Response.json({connection:await agendaConnection(),notice:body.action==='disconnect'?'Agenda desconectada.':'Calendario seleccionado.'},{headers});
 }catch(e){return failure(e);}
}
