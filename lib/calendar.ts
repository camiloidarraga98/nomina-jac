import {database} from '@/db/raw';
import {mailKey} from './payroll-mail';
import {decryptMail,encryptMail} from './payroll-mail-core';
import {z} from 'zod';
import {AGENDA_TIME_ZONE,CALENDAR_ACCOUNT,CALENDAR_SCOPE,agendaMonth,agendaDate,addAgendaDays,validAgendaDate,normalizeAgendaEvent,type AgendaCalendar,type AgendaConnection,type AgendaEvent,type AgendaEventDraft} from './calendar-core';

export type CalendarCredentials={clientId:string;clientSecret:string;refreshToken:string;scopes?:string[]};
export type CalendarConfig={credentials:string;connected_email:string;calendar_id:string;calendar_name:string;timezone:string;version:number};
type GoogleOAuthError='invalid_grant'|'invalid_client'|'unauthorized_client'|'invalid_scope'|'access_denied';
export class CalendarFailure extends Error {constructor(message:string,public status=400,public googleError?:GoogleOAuthError,public discardCachedAgenda=false){super(message);}}
export async function calendarConfig(){return database().prepare('SELECT credentials,connected_email,calendar_id,calendar_name,timezone,version FROM payroll_calendar WHERE id=?').bind('jac').first<CalendarConfig>();}
export async function calendarClientCredentials(){
 const row=await database().prepare('SELECT credentials FROM payroll_gmail WHERE id=?').bind('jac').first<{credentials:string}>();
 if(!row)throw new CalendarFailure('Prepara primero la conexión de Google desde Correos.');
 const c=await decryptMail<CalendarCredentials>(row.credentials,mailKey());
 return {clientId:c.clientId,clientSecret:c.clientSecret};
}
export async function agendaConnection():Promise<AgendaConnection>{
 const [c,gmail]=await Promise.all([calendarConfig(),database().prepare('SELECT id FROM payroll_gmail WHERE id=?').bind('jac').first()]);
 const writeAuthorized=!!c?.credentials&&(await decryptMail<CalendarCredentials>(c.credentials,mailKey())).scopes?.includes(CALENDAR_SCOPE)===true;
 return {configured:!!gmail,connected:!!c?.credentials&&c.connected_email===CALENDAR_ACCOUNT,email:CALENDAR_ACCOUNT,selected:c?.calendar_id?{id:c.calendar_id,name:c.calendar_name,timeZone:c.timezone,primary:false}:null,revision:c?.version??0,writeAuthorized};
}
export async function ensureCalendarConfig(){await database().prepare('INSERT OR IGNORE INTO payroll_calendar (id,updated_at) VALUES (?,?)').bind('jac',new Date().toISOString()).run();return (await calendarConfig())!;}
export async function storeCalendarCredentials(credentials:CalendarCredentials,version:number){
 const encrypted=await encryptMail(credentials,mailKey());
 // Renewing the grant keeps the selected calendar; the verified Google account is unchanged.
 const changed=await database().prepare('UPDATE payroll_calendar SET credentials=?,connected_email=?,version=version+1,updated_at=? WHERE id=? AND version=?').bind(encrypted,CALENDAR_ACCOUNT,new Date().toISOString(),'jac',version).run();
 if(changed.meta.changes!==1)throw new CalendarFailure('La conexión de Agenda cambió. Actualiza y vuelve a autorizar.',409);
}
async function googleResponse(response:Response) {
 const body=await response.json().catch(()=>({})) as Record<string,unknown>;
 if(!response.ok){
  const e=body.error as {errors?:{reason?:string}[];status?:string}|string|undefined;
  const reason=typeof e==='object'?e.errors?.[0]?.reason:'';
  const disabled=['accessNotConfigured','serviceDisabled'].includes(reason||'');
  const oauthError=typeof e==='string'&&['invalid_grant','invalid_client','unauthorized_client','invalid_scope','access_denied'].includes(e)?e as GoogleOAuthError:undefined;
  if(response.status===412)throw new CalendarFailure('Otra persona modificó este evento. Cierra el formulario, actualiza Agenda y abre la versión actual antes de guardar.',409);
  if(response.status===404||response.status===410)throw new CalendarFailure('El evento ya no está disponible. Actualiza Agenda.',404,undefined,true);
  throw new CalendarFailure(disabled?'Activa Google Calendar API en el proyecto de Google utilizado por JAC.':response.status===401||e==='invalid_grant'?'Google requiere que vuelvas a conectar Agenda.':response.status===403?'Google no concedió acceso al calendario. Revisa la autorización y activa Google Calendar API.':response.status===429?'Google limitó las consultas. Espera un momento y actualiza.':'No pudimos consultar Google Calendar. Intenta actualizar.',502,oauthError,response.status===401||response.status===403||!!oauthError);
 }
 return body;
}
export async function calendarGoogleFetch(url:string|URL,options:RequestInit={}){
 // Workerd supports manual/follow, not redirect:error. Reject redirects without forwarding credentials.
 const response=await fetch(url,{...options,redirect:'manual',signal:AbortSignal.timeout(15000)});
 if(response.status>=300&&response.status<400)throw new CalendarFailure('Google devolvió una redirección inesperada. Vuelve a intentar la conexión de Agenda.',502);
 return response;
}
export async function calendarGooglePost(data:Record<string,string>){return googleResponse(await calendarGoogleFetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(data)}));}
async function accessToken(c:CalendarConfig) {
 if(!c.credentials||c.connected_email!==CALENDAR_ACCOUNT)throw new CalendarFailure('Conecta la cuenta de Google para consultar Agenda.');
 const secret=await decryptMail<CalendarCredentials>(c.credentials,mailKey());
 const response=await calendarGooglePost({client_id:secret.clientId,client_secret:secret.clientSecret,refresh_token:secret.refreshToken,grant_type:'refresh_token'});
 if(typeof response.access_token!=='string')throw new CalendarFailure('Google no confirmó la autorización. Vuelve a conectar Agenda.',502);
 return response.access_token;
}
async function googleGet(path:string,token:string,params:Record<string,string>={}) {
 const url=new URL('https://www.googleapis.com/calendar/v3/'+path);url.search=new URLSearchParams(params).toString();
 return googleResponse(await calendarGoogleFetch(url,{headers:{Authorization:'Bearer '+token}}));
}
async function listCalendars(token:string):Promise<AgendaCalendar[]> {
 const calendars:AgendaCalendar[]=[];let page='';
 for(let i=0;i<10;i++){
  const r=await googleGet('users/me/calendarList',token,{minAccessRole:'reader',maxResults:'100',fields:'nextPageToken,items(id,summary,timeZone,primary,accessRole)',...(page?{pageToken:page}:{})});
  for(const item of Array.isArray(r.items)?r.items:[]){
   const c=item as Record<string,unknown>;
   if(typeof c.id==='string'&&c.id.length<=1024&&typeof c.summary==='string'&&['reader','writer','owner'].includes(String(c.accessRole)))calendars.push({id:c.id,name:c.summary.slice(0,300),timeZone:typeof c.timeZone==='string'?c.timeZone:AGENDA_TIME_ZONE,primary:c.primary===true,writable:['writer','owner'].includes(String(c.accessRole))});
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
  const r=await googleGet('calendars/'+encodeURIComponent(c.calendar_id)+'/events',token,{timeMin:from,timeMax:to,timeZone:AGENDA_TIME_ZONE,singleEvents:'true',orderBy:'startTime',showDeleted:'false',maxResults:'100',fields:'nextPageToken,items(id,etag,status,eventType,recurringEventId,summary,start,end,location,description,htmlLink)',...(page?{pageToken:page}:{})});
  for(const item of Array.isArray(r.items)?r.items:[]){const event=normalizeAgendaEvent(item);if(event)found.set(event.id,event);}
  page=typeof r.nextPageToken==='string'?r.nextPageToken:'';if(!page)return [...found.values()];
 }
 throw new CalendarFailure('Este período tiene demasiados eventos. Revisa el calendario en Google.',502);
}
export async function readAgenda(month?:string){
 if(month!==undefined&&!/^(19|20|21)\d\d-(0[1-9]|1[0-2])$/.test(month))throw new CalendarFailure('Selecciona un mes válido.');
 const grid=agendaMonth(month),today=agendaDate(),until=addAgendaDays(today,90),connection=await agendaConnection(),c=await calendarConfig();
 if((c?.version??0)!==connection.revision)throw new CalendarFailure('La conexión cambió. Actualiza Agenda.',409);
 let monthEvents:AgendaEvent[]=[],upcoming:AgendaEvent[]=[],canEditEvents=false;
 if(connection.connected&&connection.selected&&c){
  const token=await accessToken(c);
  [monthEvents,upcoming]=await Promise.all([events(c,token,grid.from,grid.to),events(c,token,new Date().toISOString(),until+'T00:00:00-05:00')]);
  if(connection.writeAuthorized)canEditEvents=(await selectedCalendarAccess(c,token));
  const current=await calendarConfig();if(!current||current.version!==c.version||current.credentials!==c.credentials)throw new CalendarFailure('La selección del calendario cambió. Actualiza Agenda.',409);
 }
 return {connection,canEditEvents,month:grid.month,monthLabel:grid.monthLabel,days:grid.days,today,events:monthEvents,upcoming,upcomingUntil:until,updatedAt:new Date().toISOString(),timeZone:AGENDA_TIME_ZONE};
}

async function selectedCalendarAccess(c:CalendarConfig,token:string){
 const calendar=await googleGet('users/me/calendarList/'+encodeURIComponent(c.calendar_id),token,{fields:'id,accessRole'});
 return calendar.id===c.calendar_id&&['owner','writer'].includes(String(calendar.accessRole));
}
const draftSchema=z.object({title:z.string().trim().min(1).max(300),location:z.string().max(1024),description:z.string().max(8192),allDay:z.boolean(),start:z.string().max(40),end:z.string().max(40)}).strict();
export function validateAgendaDraft(value:unknown):AgendaEventDraft{
 const result=draftSchema.safeParse(value);if(!result.success)throw new CalendarFailure('Revisa el título, las fechas, el lugar y la descripción del evento.');
 const draft=result.data;
 const date=(v:string)=>validAgendaDate(v)&&/^(19|20|21)\d\d-/.test(v);
 const instant=(v:string)=>/^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,3})?)?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$/.test(v)&&date(v.slice(0,10))&&Number.isFinite(Date.parse(v));
 if(draft.allDay?(!date(draft.start)||!date(draft.end)||draft.end<=draft.start):(!instant(draft.start)||!instant(draft.end)||Date.parse(draft.end)<=Date.parse(draft.start)))throw new CalendarFailure('La fecha de fin debe ser posterior al inicio. Usa fechas y horas válidas.');
 return draft.allDay?draft:{...draft,start:new Date(draft.start).toISOString(),end:new Date(draft.end).toISOString()};
}
const eventPath=(c:CalendarConfig,id?:string)=>'calendars/'+encodeURIComponent(c.calendar_id)+'/events'+(id?'/'+encodeURIComponent(id):'');
// An empty month is not evidence of deletion: events may have moved. Verify
// each missing ID against the same accessible calendar before reconciling CRM.
export async function inspectAgendaEvents(calendarId:string,revision:number,ids:string[]){
 const c=await calendarConfig();if(!c||c.calendar_id!==calendarId||c.version!==revision)throw new CalendarFailure('El calendario cambió. Actualiza antes de continuar.',409);
 const token=await accessToken(c),access=await googleGet('users/me/calendarList/'+encodeURIComponent(c.calendar_id),token,{fields:'id,accessRole'});
 if(access.id!==calendarId||!['reader','writer','owner'].includes(String(access.accessRole)))throw new CalendarFailure('Google no confirmó el acceso al calendario.',403);
 const found=new Map<string,AgendaEvent|null>();
 for(let offset=0;offset<ids.length;offset+=5)await Promise.all(ids.slice(offset,offset+5).map(async id=>{
  const response=await calendarGoogleFetch('https://www.googleapis.com/calendar/v3/'+eventPath(c,id),{headers:{Authorization:'Bearer '+token}});
  if(response.status===404||response.status===410){found.set(id,null);return;}
  const raw=await googleResponse(response),event=normalizeAgendaEvent(raw);
  if(raw.status==='cancelled'&&raw.id===id)found.set(id,null);
  else if(event?.id===id)found.set(id,event);
  else throw new CalendarFailure('Google no confirmó el estado del evento. Intenta actualizar.',502);
 }));
 const current=await calendarConfig();if(!current||current.version!==c.version||current.calendar_id!==c.calendar_id||current.credentials!==c.credentials)throw new CalendarFailure('El calendario cambió. Actualiza antes de continuar.',409);
 return found;
}
export async function deleteAgendaEvent(calendarId:string,revision:number,eventId:string,etag:string,authorize:()=>Promise<boolean>){
 if(!eventId||eventId.length>1024||!etag||etag.length>1024||/[\r\n]/.test(etag))throw new CalendarFailure('Actualiza el evento antes de eliminarlo.');
 const c=await calendarConfig();if(!c||c.calendar_id!==calendarId||c.version!==revision)throw new CalendarFailure('El calendario cambió. Actualiza antes de eliminar.',409);
 const secret=await decryptMail<CalendarCredentials>(c.credentials,mailKey());if(!secret.scopes?.includes(CALENDAR_SCOPE))throw new CalendarFailure('Agenda requiere permiso para editar eventos.',403);
 const token=await accessToken(c);if(!await selectedCalendarAccess(c,token))throw new CalendarFailure('Este calendario solo permite consultar.',403);
 const url=new URL('https://www.googleapis.com/calendar/v3/'+eventPath(c,eventId));
 const response=await calendarGoogleFetch(url,{headers:{Authorization:'Bearer '+token}});
 const absent=response.status===404||response.status===410,raw=absent?null:await googleResponse(response),event=raw?normalizeAgendaEvent(raw):null,cancelled=raw?.status==='cancelled'&&raw.id===eventId;
 if(!absent&&!cancelled&&(!event||event.id!==eventId||!event.editable))throw new CalendarFailure('Este evento se debe eliminar desde Google Calendar.',409);
 if(event&&event.etag!==etag)throw new CalendarFailure('El evento cambió en Calendar. Actualiza y confirma su nueva versión antes de eliminar.',409);
 const current=await calendarConfig();if(!current||current.version!==c.version||current.credentials!==c.credentials||current.calendar_id!==calendarId)throw new CalendarFailure('El calendario cambió. Actualiza antes de eliminar.',409);
 if(!await authorize())throw new CalendarFailure('Tu sesión o el show cambió. Actualiza antes de eliminar.',403);
 if(absent||cancelled)return;
 url.searchParams.set('sendUpdates','none');
 const removed=await calendarGoogleFetch(url,{method:'DELETE',headers:{Authorization:'Bearer '+token,'If-Match':etag}});
 if(removed.status!==204&&removed.status!==404&&removed.status!==410)await googleResponse(removed);
}
export async function saveAgendaEvent(action:'createEvent'|'updateEvent',input:Record<string,unknown>,authorize:()=>Promise<boolean>){
 const draft=validateAgendaDraft(input.event),revision=Number(input.revision),c=await calendarConfig();
 if(!c||!c.calendar_id||c.version!==revision)throw new CalendarFailure('La conexión o el calendario cambió. Actualiza Agenda antes de guardar.',409);
 const secret=await decryptMail<CalendarCredentials>(c.credentials,mailKey());
 if(!secret.scopes?.includes(CALENDAR_SCOPE))throw new CalendarFailure('Camilo debe volver a autorizar Google desde Conexión y conceder el permiso para editar eventos.',403);
 const token=await accessToken(c);if(!await selectedCalendarAccess(c,token))throw new CalendarFailure('Este calendario solo permite consultar. Camilo debe elegir uno con permiso de edición.',403);
 let id:string,patch:Record<string,unknown>,etag:string|undefined;
 const dates={start:draft.allDay?{date:draft.start}:{dateTime:draft.start,timeZone:AGENDA_TIME_ZONE},end:draft.allDay?{date:draft.end}:{dateTime:draft.end,timeZone:AGENDA_TIME_ZONE}};
 const payloadHash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(draft)))),x=>x.toString(16).padStart(2,'0')).join('');
 if(action==='createEvent'){
  if(typeof input.requestId!=='string'||! /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(input.requestId))throw new CalendarFailure('Vuelve a abrir el formulario para crear el evento.');
  id='jac'+input.requestId.replaceAll('-','');patch={id,summary:draft.title,location:draft.location,description:draft.description,...dates,extendedProperties:{private:{jacRequest:input.requestId,jacPayload:payloadHash}}};
 }else{
  if(typeof input.eventId!=='string'||!input.eventId||input.eventId.length>1024||typeof input.etag!=='string'||!input.etag||input.etag.length>1024||/[\r\n]/.test(input.etag))throw new CalendarFailure('Actualiza Agenda y abre de nuevo el evento antes de editar.');
  id=input.eventId;const raw=await googleGet(eventPath(c,id),token),existing=normalizeAgendaEvent(raw);
  if(!existing||!existing.editable)throw new CalendarFailure('Este tipo de evento se debe modificar en Google Calendar.');
  if(existing.etag!==input.etag)throw new CalendarFailure('Otra persona modificó este evento. Cierra el formulario, actualiza Agenda y abre la versión actual antes de guardar.',409);
  etag=input.etag;patch={};
  for(const [field,key] of [['title','summary'],['location','location'],['description','description']] as const)if(draft[field]!==existing[field])patch[key]=draft[field];
  if(draft.allDay!==existing.allDay||draft.start!==existing.start||draft.end!==existing.end)Object.assign(patch,{start:{...dates.start,...(draft.allDay?{dateTime:null,timeZone:null}:{date:null})},end:{...dates.end,...(draft.allDay?{dateTime:null,timeZone:null}:{date:null})}});
 }
 // Recheck the active actor and selected connection immediately before any Google write.
 const current=await calendarConfig();if(!current||current.version!==c.version||current.credentials!==c.credentials||current.calendar_id!==c.calendar_id)throw new CalendarFailure('El calendario cambió. Actualiza Agenda antes de guardar.',409);
 if(!await authorize())throw new CalendarFailure('Tu sesión o permiso cambió. Inicia sesión de nuevo.',403);
 const url=new URL('https://www.googleapis.com/calendar/v3/'+eventPath(c,action==='updateEvent'?id:undefined));url.searchParams.set('sendUpdates','none');
 const response=await calendarGoogleFetch(url,{method:action==='createEvent'?'POST':'PATCH',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json',...(etag?{'If-Match':etag}:{})},body:JSON.stringify(patch)});
 let raw:Record<string,unknown>;
 if(action==='createEvent'&&response.status===409){
  raw=await googleGet(eventPath(c,id),token);const marker=(raw.extendedProperties as {private?:{jacRequest?:string;jacPayload?:string}}|undefined)?.private;
  if(marker?.jacRequest!==input.requestId||marker?.jacPayload!==payloadHash)throw new CalendarFailure('Esta solicitud ya se utilizó con otros datos. Reabre el formulario para crear otro evento.',409);
 }else raw=await googleResponse(response);
 const event=normalizeAgendaEvent(raw);if(!event)throw new CalendarFailure('Google no confirmó el evento. Actualiza Agenda antes de volver a intentarlo.',502);
 return {event,notice:action==='createEvent'?'Evento creado en Google Calendar.':'Evento actualizado en Google Calendar.'};
}
