'use client';
import {useState,useEffect,useCallback,useRef} from 'react';
import {ChevronLeft,ChevronRight,CalendarDays,RefreshCw,MapPin,Clock,ExternalLink,Settings2} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {Dialog,DialogContent,DialogTitle,DialogDescription} from '@/components/ui/dialog';
import {agendaDate,agendaMonth,agendaDayLabel,agendaEventOnDay,agendaEventTime,addAgendaDays,type AgendaData,type AgendaEvent,type AgendaCalendar} from '@/lib/calendar-core';

async function calendarRequest<T>(path:string,body?:unknown):Promise<T>{
 const response=await fetch(path,{cache:'no-store',...(body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{})});
 if(response.status===401){location.assign('/acceso');throw new Error('Tu sesión venció. Inicia sesión de nuevo.');}
 const result=await response.json() as T&{error?:string};if(!response.ok)throw new Error(result.error||'No pudimos consultar Agenda.');return result;
}
export default function AgendaPanel({isOwner,connectBlocked,onGoogleSetup}:{isOwner:boolean;connectBlocked:boolean;onGoogleSetup:()=>void}){
 const today=agendaDate();
 const [month,setMonth]=useState(today.slice(0,7)),[day,setDay]=useState(today),[data,setData]=useState<AgendaData|null>(null),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[settings,setSettings]=useState(false),[calendars,setCalendars]=useState<AgendaCalendar[]>([]),[calendarId,setCalendarId]=useState(''),[selected,setSelected]=useState<AgendaEvent|null>(null),[confirmDisconnect,setConfirmDisconnect]=useState(false);
 const [listing,setListing]=useState(false);
 const generation=useRef(0),lastRefresh=useRef(0),calendarRequestId=useRef(0);
 const refresh=useCallback(async()=>{
  const id=++generation.current;setLoading(true);setError('');lastRefresh.current=Date.now();
  try{const result=await calendarRequest<AgendaData>('/api/calendar?month='+encodeURIComponent(month));if(id===generation.current)setData(result);}
  catch(e){if(id===generation.current)setError(e instanceof Error?e.message:'No pudimos consultar Agenda.');}
  finally{if(id===generation.current)setLoading(false);}
 },[month]);
 useEffect(()=>{void refresh();return()=>{generation.current++;};},[refresh]);
 useEffect(()=>{
  const onFocus=()=>{if(document.visibilityState==='visible'&&Date.now()-lastRefresh.current>30000)void refresh();};
  window.addEventListener('focus',onFocus);document.addEventListener('visibilitychange',onFocus);
  return()=>{window.removeEventListener('focus',onFocus);document.removeEventListener('visibilitychange',onFocus);};
 },[refresh]);
 useEffect(()=>{
  if(!isOwner||!data?.connection.connected||(!settings&&data.connection.selected))return;
  const id=++calendarRequestId.current;
  setListing(true);setCalendars([]);setCalendarId('');
  void calendarRequest<{calendars:AgendaCalendar[]}>('/api/calendar?action=calendars').then(r=>{if(id===calendarRequestId.current){setCalendars(r.calendars);setCalendarId(data.connection.selected?.id||r.calendars[0]?.id||'');}}).catch(e=>{if(id===calendarRequestId.current)setError(e instanceof Error?e.message:'No pudimos listar los calendarios.');}).finally(()=>{if(id===calendarRequestId.current)setListing(false);});
  return()=>{calendarRequestId.current++;};
 },[isOwner,settings,data?.connection.connected,data?.connection.revision,data?.connection.selected?.id,data?.updatedAt]);
 const visible=data?.month===month?data:null,connection=data?.connection;
 const dayEvents=visible?.events.filter(e=>agendaEventOnDay(e,day))??[];
 const changeMonth=(offset:number)=>{
  const date=new Date(month+'-01T12:00:00Z');date.setUTCMonth(date.getUTCMonth()+offset);const next=date.toISOString().slice(0,7);
  try{agendaMonth(next);setMonth(next);setDay(next===today.slice(0,7)?today:next+'-01');}catch{setError('Ese mes está fuera del rango disponible.');}
 };
 async function connect(){
  setBusy(true);setError('');
  try{const start=await calendarRequest<{url:string}>('/api/calendar',{action:'connect'});const url=new URL(start.url);if(url.protocol!=='https:'||url.hostname!=='accounts.google.com')throw new Error('La autorización de Google no es válida.');location.assign(url.toString());}
  catch(e){setError(e instanceof Error?e.message:'No pudimos abrir Google.');setBusy(false);}
 }
 async function operation(action:'select'|'disconnect'){
  if(!connection)return;setBusy(true);setError('');setNotice('');
  try{const result=await calendarRequest<{notice:string}>('/api/calendar',{action,revision:connection.revision,...(action==='select'?{calendarId}:{})});setNotice(result.notice);setSettings(false);setConfirmDisconnect(false);await refresh();}
  catch(e){setError(e instanceof Error?e.message:'No pudimos guardar la conexión.');}
  finally{setBusy(false);}
 }
 const ready=!!connection?.connected&&!!connection.selected;
 return <div className="agenda">
  {error&&<div className="message error" role="alert">{error}<Button variant="outline" onClick={()=>void refresh()} disabled={loading}>Reintentar</Button></div>}
  {notice&&<div className="message success" role="status">{notice}</div>}
  <div className="agenda-status"><div><strong>{connection?.selected?.name||'Agenda de Jhon Alex'}</strong><small>{ready?'Google Calendar · Hora de Colombia':loading?'Consultando conexión…':'Conecta Google y elige el calendario de la agenda.'}</small></div><div className="actions"><Button variant="outline" aria-label="Actualizar agenda" onClick={()=>void refresh()} disabled={loading||busy}><RefreshCw size={16} className={loading?'agenda-spinning':''}/>Actualizar</Button>{isOwner&&<Button variant="outline" onClick={()=>setSettings(!settings)} disabled={busy}><Settings2 size={16}/>{settings?'Cerrar configuración':'Conexión'}</Button>}</div></div>
  {(!ready||settings)&&!loading&&<section className="panel agenda-connection"><div className="panel-title"><h2>{connection?.connected?'Elegir calendario':'Conectar Google Calendar'}</h2></div>
   <p className="panel-note">{isOwner?'Usa jacmusicestudios@gmail.com y selecciona el calendario de Jhon Alex. La agenda se comparte con los usuarios activos de JAC.':'Camilo prepara la conexión y selecciona el calendario que podrá consultar el equipo.'}</p>
   {isOwner&&<div className="agenda-setup">
    {!connection?.configured?<Button onClick={onGoogleSetup}>Preparar Google en Correos</Button>:<>
     <p>En el proyecto de Google que utilizas para JAC, activa <a href="https://console.cloud.google.com/apis/library/calendar-json.googleapis.com" target="_blank" rel="noreferrer">Google Calendar API <ExternalLink size={13}/></a>. Después autoriza la consulta de la agenda.</p>
     <Button className="primary" onClick={()=>void connect()} disabled={busy||connectBlocked}>{busy?'Preparando…':connection.connected?'Volver a autorizar Google':'Conectar Google'}</Button>
     {connectBlocked&&<p className="muted">Guarda o respalda los cambios pendientes de nómina antes de abrir Google.</p>}
    </>}
    {connection?.connected&&<>
     <label htmlFor="agenda-calendar">Calendario de la agenda</label><select id="agenda-calendar" className="agenda-picker" value={calendarId} onChange={e=>setCalendarId(e.target.value)} disabled={busy||listing||!calendars.length}>{!calendars.length&&<option value="">{listing?'Consultando calendarios…':'No hay calendarios disponibles'}</option>}{calendars.map(c=><option key={c.id} value={c.id}>{c.name}{c.primary?' · Principal':''}</option>)}</select>
     <div className="actions"><Button className="primary" onClick={()=>void operation('select')} disabled={busy||!calendarId}>Usar este calendario</Button><Button variant="outline" onClick={()=>setConfirmDisconnect(true)} disabled={busy}>Desconectar Agenda</Button></div>
    </>}
   </div>}
  </section>}
  {loading&&!visible?<section className="panel"><p className="panel-note" role="status">Consultando la agenda…</p></section>:ready&&visible&&<div className="agenda-layout">
   <div><section className="panel agenda-month"><div className="agenda-month-heading"><Button size="icon" variant="ghost" aria-label="Mes anterior" onClick={()=>changeMonth(-1)}><ChevronLeft/></Button><h2>{visible.monthLabel}</h2><Button size="icon" variant="ghost" aria-label="Mes siguiente" onClick={()=>changeMonth(1)}><ChevronRight/></Button><Button variant="outline" onClick={()=>{setMonth(today.slice(0,7));setDay(today);}}>Hoy</Button></div>
    <div className="agenda-weekdays" aria-hidden="true">{['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'].map(d=><span key={d}>{d}</span>)}</div>
    <div className="agenda-days" aria-label={visible.monthLabel}>{visible.days.map(date=>{const count=visible.events.filter(e=>agendaEventOnDay(e,date)).length;return <button key={date} className={['agenda-day',date.slice(0,7)!==month?'outside':'',date===day?'chosen':'',date===today?'today':''].join(' ')} aria-label={agendaDayLabel(date)+(count?`, ${count} ${count===1?'evento':'eventos'}`:', sin eventos')} aria-pressed={date===day} onClick={()=>setDay(date)}><span>{Number(date.slice(-2))}</span><span className="agenda-dots" aria-hidden="true">{Array.from({length:Math.min(count,3)},(_,i)=><i key={i}/>)}</span></button>;})}</div>
   </section><section className="panel agenda-day-events"><div className="panel-title"><h2>{agendaDayLabel(day)}</h2><small>{dayEvents.length} {dayEvents.length===1?'evento':'eventos'}</small></div>{dayEvents.length?dayEvents.map(e=><EventButton key={e.id} event={e} onClick={()=>setSelected(e)}/>):<div className="empty agenda-empty"><CalendarDays size={28}/><p>No hay eventos para este día.</p></div>}</section></div>
   <section className="panel agenda-upcoming"><div className="panel-title"><h2>Próximos eventos</h2></div><p className="panel-note">Los próximos 90 días · hasta {agendaDayLabel(visible.upcomingUntil)}</p>{visible.upcoming.length?visible.upcoming.map(e=><EventButton key={e.id} event={e} day={e.allDay?e.start:agendaDate(new Date(e.start))} onClick={()=>setSelected(e)}/>):<div className="empty agenda-empty"><CalendarDays size={28}/><p>No hay eventos programados en los próximos 90 días.</p></div>}<small className="agenda-updated">Actualizado {new Intl.DateTimeFormat('es-CO',{timeZone:'America/Bogota',hour:'numeric',minute:'2-digit'}).format(new Date(visible.updatedAt))}</small></section>
  </div>}
  <Dialog open={!!selected} onOpenChange={open=>{if(!open)setSelected(null);}}><DialogContent className="payroll-dialog agenda-detail"><DialogTitle>{selected?.title||'Evento'}</DialogTitle><DialogDescription>Agenda de Jhon Alex · Hora de Colombia</DialogDescription>{selected&&<div className="agenda-event-detail"><p><CalendarDays size={17}/>{agendaDayLabel(selected.allDay?selected.start:agendaDate(new Date(selected.start)))}</p><p><Clock size={17}/>{agendaEventTime(selected)}{selected.allDay&&selected.end!==addAgendaDays(selected.start,1)&&' · hasta '+agendaDayLabel(addAgendaDays(selected.end,-1))}</p>{selected.location&&<p><MapPin size={17}/>{selected.location}</p>}{selected.description&&<p className="agenda-description">{selected.description}</p>}{selected.url&&<a className="btn primary" href={selected.url} target="_blank" rel="noreferrer">Ver en Google Calendar <ExternalLink size={16}/></a>}</div>}</DialogContent></Dialog>
  <Dialog open={confirmDisconnect} onOpenChange={setConfirmDisconnect}><DialogContent className="payroll-dialog agenda-detail"><DialogTitle>Desconectar Agenda</DialogTitle><DialogDescription>El equipo dejará de consultar este calendario desde JAC. Los eventos continúan en Google Calendar.</DialogDescription><div className="actions"><Button variant="outline" onClick={()=>setConfirmDisconnect(false)} disabled={busy}>Cancelar</Button><Button className="primary" onClick={()=>void operation('disconnect')} disabled={busy}>Desconectar Agenda</Button></div></DialogContent></Dialog>
 </div>;
}
function EventButton({event,day,onClick}:{event:AgendaEvent;day?:string;onClick:()=>void}){
 return <button className="agenda-event" onClick={onClick}>{day&&<small className="agenda-event-date">{agendaDayLabel(day)}</small>}<strong>{event.title}</strong><span><Clock size={14}/>{agendaEventTime(event)}</span>{event.location&&<span><MapPin size={14}/>{event.location}</span>}</button>;
}
