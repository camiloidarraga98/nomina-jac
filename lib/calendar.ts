import {database} from '@/db/raw';
import {mailKey} from './payroll-mail';
import {decryptMail,encryptMail} from './payroll-mail-core';
import {AGENDA_TIME_ZONE,CALENDAR_ACCOUNT,agendaMonth,agendaDate,addAgendaDays,normalizeAgendaEvent,type AgendaCalendar,type AgendaConnection,type AgendaEvent} from './calendar-core';

export type CalendarCredentials={clientId:string;clientSecret:string;refreshToken:string};
export type CalendarConfig={credentials:string;connected_email:string;calendar_id:string;calendar_name:string;timezone:string;version:number};
export class CalendarFailure extends Error {constructor(message:string,public status=400){super(message);}}
export async function calendarConfig(){return database().prepare('SELECT credentials,connected_email,calendar_id,calendar_name,timezone,version FROM payroll_calendar WHERE id=?').bind('jac').first<CalendarConfig>();}
export async function calendarClientCredentials(){
 const row=await database().prepare('SELECT credentials FROM payroll_gmail WHERE id=?').bind('jac').first<{credentials:string}>();
 if(!row)throw new CalendarFailure('Prepara primero la conexión de Google desde Correos.');
 const c=await decryptMail<CalendarCredentials>(row.credentials,mailKey());
 return {clientId:c.clientId,clientSecret:c.clientSecret};
}
export async function agendaConnection():Promise<AgendaConnection>{
 const [c,gmail]=await Promise.all([calendarConfig(),database().prepare('SELECT id FROM payroll_gmail WHERE id=?').bind('jac').first()]);
 return {configured:!!gmail,connected:!!c?.credentials&&c.connected_email===CALENDAR_ACCOUNT,email:CALENDAR_ACCOUNT,selected:c?.calendar_id?{id:c.calendar_id,name:c.calendar_name,timeZone:c.timezone,primary:false}:null,revision:c?.version??0};
}
export async function ensureCalendarConfig(){await database().prepare('INSERT OR IGNORE INTO payroll_calendar (id,updated_at) VALUES (?,?)').bind('jac',new Date().toISOString()).run();return (await calendarConfig())!;}
export async function storeCalendarCredentials(credentials:CalendarCredentials,version:number){
 const encrypted=await encryptMail(credentials,mailKey());
 const changed=await database().prepare('UPDATE payroll_calendar SET credentials=?,connected_email=?,calendar_id=?,calendar_name=?,timezone=?,version=version+1,updated_at=? WHERE id=? AND version=?').bind(encrypted,CALENDAR_ACCOUNT,'','','America/Bogota',new Date().toISOString(),'jac',version).run();
 if(changed.meta.changes!==1)throw new CalendarFailure('La conexión de Agenda cambió. Actualiza y vuelve a autorizar.',409);
}
async function googleResponse(response:Response) {
 const body=await response.json() as Record<string,unknown>;
 if(!response.ok){
  const e=body.error as {errors?:{reason?:string}[];status?:string}|string|undefined;
  const reason=typeof e==='object'?e.errors?.[0]?.reason:'';
  const disabled=['accessNotConfigured','serviceDisabled'].includes(reason||'');
  throw new CalendarFailure(disabled?'Activa Google Calendar API en el proyecto de Google utilizado por JAC.':response.status===401||e==='invalid_grant'?'Google requiere que vuelvas a conectar Agenda.':response.status===403?'Google no concedió acceso al calendario. Revisa la autorización y activa Google Calendar API.':response.status===429?'Google limitó las consultas. Espera un momento y actualiza.':'No pudimos consultar Google Calendar. Intenta actualizar.',502);
 }
 return body;
}
export async function calendarGooglePost(data:Record<string,string>){return googleResponse(await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(data),redirect:'error',signal:AbortSignal.timeout(15000)}));}
async function accessToken(c:CalendarConfig) {
 if(!c.credentials||c.connected_email!==CALENDAR_ACCOUNT)throw new CalendarFailure('Conecta la cuenta de Google para consultar Agenda.');
 const secret=await decryptMail<CalendarCredentials>(c.credentials,mailKey());
 const response=await calendarGooglePost({client_id:secret.clientId,client_secret:secret.clientSecret,refresh_token:secret.refreshToken,grant_type:'refresh_token'});
 if(typeof response.access_token!=='string')throw new CalendarFailure('Google no confirmó la autorización. Vuelve a conectar Agenda.',502);
 return response.access_token;
}
async function googleGet(path:string,token:string,params:Record<string,string>={}) {
 const url=new URL('https://www.googleapis.com/calendar/v3/'+path);url.search=new URLSearchParams(params).toString();
 return googleResponse(await fetch(url,{headers:{Authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)}));
}
async function listCalendars(token:string):Promise<AgendaCalendar[]> {
 const calendars:AgendaCalendar[]=[];let page='';
 for(let i=0;i<10;i++){
  const r=await googleGet('users/me/calendarList',token,{minAccessRole:'reader',maxResults:'100',fields:'nextPageToken,items(id,summary,timeZone,primary,accessRole)',...(page?{pageToken:page}:{})});
  for(const item of Array.isArray(r.items)?r.items:[]){
   const c=item as Record<string,unknown>;
   if(typeof c.id==='string'&&c.id.length<=1024&&typeof c.summary==='string'&&['reader','writer','owner'].includes(String(c.accessRole)))calendars.push({id:c.id,name:c.summary.slice(0,300),timeZone:typeof c.timeZone==='string'?c.timeZone:AGENDA_TIME_ZONE,primary:c.primary===true});
  }
  page=typeof r.nextPageToken==='string'?r.nextPageToken:'';if(!page)return calendars.sort((a,b)=>Number(b.primary)-Number(a.primary)||a.name.localeCompare(b.name,'es'));
 }
 throw new CalendarFailure('Hay demasiados calendarios para consultar. Revisa la cuenta de Google.',502);
}
export async function availableAgendaCalendars(){const c=await calendarConfig();if(!c)throw new CalendarFailure('Conecta Agenda primero.');return listCalendars(await accessToken(c));}
export async function selectAgendaCalendar(id:string,revision:number){
 const c=await calendarConfig();if(!c||c.version!==revision)throw new CalendarFailure('La conexión cambió. Actualiza Agenda antes de seleccionar.',409);
 const selected=(await listCalendars(await accessToken(c))).find(x=>x.id===id);
 if(!selected)throw new CalendarFailure('Ese calendario no está disponible en la cuenta de Google.');
 const result=await database().prepare('UPDATE payroll_calendar SET calendar_id=?,calendar_name=?,timezone=?,version=version+1,updated_at=? WHERE id=? AND version=? AND credentials=?').bind(selected.id,selected.name,selected.timeZone,new Date().toISOString(),'jac',revision,c.credentials).run();
 if(result.meta.changes!==1)throw new CalendarFailure('La conexión cambió. Actualiza Agenda antes de seleccionar.',409);
}
export async function disconnectAgenda(revision:number){
 const result=await database().prepare('UPDATE payroll_calendar SET credentials=?,connected_email=?,calendar_id=?,calendar_name=?,version=version+1,updated_at=? WHERE id=? AND version=?').bind('','','','',new Date().toISOString(),'jac',revision).run();
 if(result.meta.changes!==1)throw new CalendarFailure('La conexión cambió. Actualiza Agenda antes de desconectar.',409);
 // Do not revoke the Google grant: doing so could also invalidate Gmail.
}
async function events(c:CalendarConfig,token:string,from:string,to:string):Promise<AgendaEvent[]> {
 const found=new Map<string,AgendaEvent>();let page='';
 for(let i=0;i<10;i++){
  const r=await googleGet('calendars/'+encodeURIComponent(c.calendar_id)+'/events',token,{timeMin:from,timeMax:to,timeZone:AGENDA_TIME_ZONE,singleEvents:'true',orderBy:'startTime',showDeleted:'false',maxResults:'100',fields:'nextPageToken,items(id,status,summary,start,end,location,description,htmlLink)',...(page?{pageToken:page}:{})});
  for(const item of Array.isArray(r.items)?r.items:[]){const event=normalizeAgendaEvent(item);if(event)found.set(event.id,event);}
  page=typeof r.nextPageToken==='string'?r.nextPageToken:'';if(!page)return [...found.values()];
 }
 throw new CalendarFailure('Este período tiene demasiados eventos. Revisa el calendario en Google.',502);
}
export async function readAgenda(month?:string){
 if(month!==undefined&&!/^(19|20|21)\d\d-(0[1-9]|1[0-2])$/.test(month))throw new CalendarFailure('Selecciona un mes válido.');
 const grid=agendaMonth(month),today=agendaDate(),until=addAgendaDays(today,90),connection=await agendaConnection(),c=await calendarConfig();
 if((c?.version??0)!==connection.revision)throw new CalendarFailure('La conexión cambió. Actualiza Agenda.',409);
 let monthEvents:AgendaEvent[]=[],upcoming:AgendaEvent[]=[];
 if(connection.connected&&connection.selected&&c){
  const token=await accessToken(c);
  [monthEvents,upcoming]=await Promise.all([events(c,token,grid.from,grid.to),events(c,token,new Date().toISOString(),until+'T00:00:00-05:00')]);
  const current=await calendarConfig();if(!current||current.version!==c.version||current.credentials!==c.credentials)throw new CalendarFailure('La selección del calendario cambió. Actualiza Agenda.',409);
 }
 return {connection,month:grid.month,monthLabel:grid.monthLabel,days:grid.days,today,events:monthEvents,upcoming,upcomingUntil:until,updatedAt:new Date().toISOString(),timeZone:AGENDA_TIME_ZONE};
}
