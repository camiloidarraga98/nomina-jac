import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {agendaConnection,readAgenda,availableAgendaCalendars,selectAgendaCalendar,disconnectAgenda,CalendarFailure} from '@/lib/calendar';
import {startCalendarOauth} from '@/lib/calendar-oauth';
import {isOwnerEmail} from '@/lib/payroll-policy';
export const dynamic='force-dynamic';
const headers={...payrollHeaders,'Referrer-Policy':'no-referrer'};
const failure=(e:unknown)=>Response.json({error:e instanceof Error?e.message:'No pudimos consultar Agenda.'},{status:e instanceof CalendarFailure?e.status:502,headers});
export async function GET(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers});
 try{
  const url=new URL(req.url);
  if(url.searchParams.get('action')==='calendars'){
   if(!user.isOwner||!isOwnerEmail(user.email))return Response.json({error:'Solo Camilo puede elegir el calendario.'},{status:403,headers});
   return Response.json({calendars:await availableAgendaCalendars()},{headers});
  }
  return Response.json(await readAgenda(url.searchParams.get('month')??undefined),{headers});
 }catch(e){return failure(e);}
}
export async function POST(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers});
 if(!user.isOwner||!isOwnerEmail(user.email))return Response.json({error:'Solo Camilo puede configurar Agenda.'},{status:403,headers});
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Origen no autorizado.'},{status:403,headers});
 try{
  const body=await req.json() as Record<string,unknown>;
  if(!body||Array.isArray(body)||typeof body!=='object')throw new CalendarFailure('La operación no es válida.');
  if(body.action==='connect'){
   const start=await startCalendarOauth(user,req.headers.get('cookie')||'',body.native===true);
   return Response.json({url:start.url,...('nonce' in start?{nonce:start.nonce}:{})},{headers:{...headers,...('cookie' in start?{'Set-Cookie':start.cookie}:{})}});
  }
  if(!Number.isSafeInteger(body.revision)||Number(body.revision)<0)throw new CalendarFailure('Actualiza Agenda antes de guardar.');
  if(body.action==='select'&&typeof body.calendarId==='string'&&body.calendarId.length>0&&body.calendarId.length<=1024)await selectAgendaCalendar(body.calendarId,Number(body.revision));
  else if(body.action==='disconnect')await disconnectAgenda(Number(body.revision));
  else throw new CalendarFailure('La operación no es válida.');
  return Response.json({connection:await agendaConnection(),notice:body.action==='disconnect'?'Agenda desconectada.':'Calendario seleccionado.'},{headers});
 }catch(e){return failure(e);}
}
