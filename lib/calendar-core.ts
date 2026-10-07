export const AGENDA_TIME_ZONE = 'America/Bogota';
export const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.events';
export const CALENDAR_LIST_SCOPE = 'https://www.googleapis.com/auth/calendar.calendarlist.readonly';
export const CALENDAR_ACCOUNT = 'jacmusicestudios@gmail.com';
export type AgendaCalendar = {id:string;name:string;timeZone:string;primary:boolean;writable?:boolean};
export type AgendaConnection = {configured:boolean;connected:boolean;email:string;selected:AgendaCalendar|null;revision:number;writeAuthorized:boolean};
export type AgendaEvent = {id:string;title:string;start:string;end:string;allDay:boolean;location:string;description:string;url:string;etag:string;editable:boolean;recurring:boolean};
export type AgendaEventDraft = Pick<AgendaEvent,'title'|'start'|'end'|'allDay'|'location'|'description'>;
export type AgendaData = {connection:AgendaConnection;canEditEvents:boolean;month:string;monthLabel:string;days:string[];today:string;events:AgendaEvent[];upcoming:AgendaEvent[];upcomingUntil:string;updatedAt:string;timeZone:string};

export function agendaDate(date = new Date()) {
 const parts = new Intl.DateTimeFormat('en-CA',{timeZone:AGENDA_TIME_ZONE,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);
 const part = (key:string) => parts.find(p=>p.type===key)!.value;
 return `${part('year')}-${part('month')}-${part('day')}`;
}
export function validAgendaDate(value:unknown):value is string {
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;
 const date=new Date(value+'T12:00:00Z');return Number.isFinite(date.getTime())&&date.toISOString().slice(0,10)===value;
}
export function addAgendaDays(day:string,count:number) {
 const date=new Date(day+'T12:00:00Z');date.setUTCDate(date.getUTCDate()+count);return date.toISOString().slice(0,10);
}
export function agendaMonth(month=agendaDate().slice(0,7)) {
 if(!/^(19|20|21)\d\d-(0[1-9]|1[0-2])$/.test(month))throw new Error('Selecciona un mes válido.');
 const first=month+'-01',weekday=new Date(first+'T12:00:00Z').getUTCDay();
 const start=addAgendaDays(first,-((weekday+6)%7));
 return {month,monthLabel:new Intl.DateTimeFormat('es-CO',{month:'long',year:'numeric',timeZone:'UTC'}).format(new Date(first+'T12:00:00Z')),days:Array.from({length:42},(_,i)=>addAgendaDays(start,i)),from:start+'T00:00:00-05:00',to:addAgendaDays(start,42)+'T00:00:00-05:00'};
}
export function agendaGoogleLink(value:unknown) {
 if(typeof value!=='string'||value.length>4096)return '';
 try {const url=new URL(value);return url.protocol==='https:'&&!url.username&&!url.password&&!url.port&&['calendar.google.com','www.google.com'].includes(url.hostname)&&url.pathname.startsWith('/calendar/')?url.toString():'';}catch{return '';}
}
function plainDescription(value:string) {
 return value.replace(/<br\s*\/?\s*>/gi,'\n').replace(/<\/p\s*>/gi,'\n').replace(/<[^>]*>/g,'').replace(/&nbsp;/g,' ').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,'&').trim().slice(0,8192);
}
export function normalizeAgendaEvent(input:unknown):AgendaEvent|null {
 if(!input||typeof input!=='object')return null;
 const e=input as Record<string,unknown>,start=e.start as {date?:string;dateTime?:string}|undefined,end=e.end as {date?:string;dateTime?:string}|undefined;
 if(e.status==='cancelled'||typeof e.id!=='string'||!e.id||e.id.length>1024||!start||!end)return null;
 const allDay=typeof start.date==='string';let from:string,to:string;
 if(allDay){if(!validAgendaDate(start.date)||!validAgendaDate(end.date)||end.date<=start.date)return null;from=start.date;to=end.date;}
 else {
  const valid=(date:unknown):date is string=>typeof date==='string'&&/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(date)&&validAgendaDate(date.slice(0,10))&&Number.isFinite(Date.parse(date));
  if(!valid(start.dateTime)||!valid(end.dateTime)||Date.parse(end.dateTime)<=Date.parse(start.dateTime))return null;
  from=new Date(start.dateTime).toISOString();to=new Date(end.dateTime).toISOString();
 }
 const text=(key:string,max:number)=>typeof e[key]==='string'?(e[key] as string).slice(0,max):'';
 const etag=text('etag',1024);
 return {id:e.id,title:text('summary',300)||'Evento sin título',start:from,end:to,allDay,location:text('location',1024),description:plainDescription(text('description',20000)),url:agendaGoogleLink(e.htmlLink),etag,editable:!!etag&&!/[\r\n]/.test(etag)&&(!e.eventType||e.eventType==='default'),recurring:typeof e.recurringEventId==='string'};
}
export function agendaEventOnDay(event:AgendaEvent,day:string) {
 if(event.allDay)return event.start<=day&&event.end>day;
 return Date.parse(event.start)<Date.parse(addAgendaDays(day,1)+'T00:00:00-05:00')&&Date.parse(event.end)>Date.parse(day+'T00:00:00-05:00');
}
export function agendaDayLabel(day:string) {return new Intl.DateTimeFormat('es-CO',{weekday:'long',day:'numeric',month:'long',timeZone:'UTC'}).format(new Date(day+'T12:00:00Z'));}
export function agendaEventTime(event:AgendaEvent) {
 if(event.allDay)return 'Todo el día';
 const formatter=new Intl.DateTimeFormat('es-CO',{timeZone:AGENDA_TIME_ZONE,hour:'numeric',minute:'2-digit'});
 const start=new Date(event.start),end=new Date(event.end);
 return formatter.format(start)+' – '+(agendaDate(start)!==agendaDate(end)?agendaDayLabel(agendaDate(end))+', ':'')+formatter.format(end);
}
