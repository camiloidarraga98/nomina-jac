'use client';
import {useState} from 'react';
import {Button} from '@/components/ui/button';
import {Input} from '@/components/ui/input';
import {Label} from '@/components/ui/label';
import {addAgendaDays,agendaDate,type AgendaEvent,type AgendaEventDraft} from '@/lib/calendar-core';

const localTime=(iso:string)=>{const d=new Date(iso);return agendaDate(d)+'T'+new Intl.DateTimeFormat('en-GB',{timeZone:'America/Bogota',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(d);};
export default function AgendaEventEditor({event,day,save,onBusy}:{event?:AgendaEvent;day:string;save:(event:AgendaEventDraft,requestId:string)=>Promise<void>;onBusy:(busy:boolean)=>void}){
 const [title,setTitle]=useState(event?.title??''),[location,setLocation]=useState(event?.location??''),[description,setDescription]=useState(event?.description??''),[allDay,setAllDay]=useState(event?.allDay??false);
 const [start,setStart]=useState(event?(event.allDay?event.start:localTime(event.start)):day+'T19:00'),[end,setEnd]=useState(event?(event.allDay?addAgendaDays(event.end,-1):localTime(event.end)):day+'T21:00');
 const [requestId]=useState(()=>crypto.randomUUID()),[busy,setBusy]=useState(false),[error,setError]=useState('');
 function toggle(checked:boolean){setAllDay(checked);setStart(checked?start.slice(0,10):start+'T19:00');setEnd(checked?end.slice(0,10):end+'T21:00');}
 async function submit(e:React.FormEvent){
  e.preventDefault();if(busy)return;setError('');
  const from=allDay?start:event&&!event.allDay&&start===localTime(event.start)?event.start:start+':00-05:00',to=allDay?addAgendaDays(end,1):event&&!event.allDay&&end===localTime(event.end)?event.end:end+':00-05:00';
  if(!title.trim()||(!allDay&&Date.parse(to)<=Date.parse(from))||(allDay&&end<start)){setError('Revisa el título y que el fin sea posterior al inicio.');return;}
  setBusy(true);onBusy(true);
  try{await save({title:title.trim(),location,description,allDay,start:from,end:to},requestId);}
  catch(e){setError(e instanceof Error?e.message:'No pudimos guardar el evento. Tus datos siguen en el formulario.');}
  finally{setBusy(false);onBusy(false);}
 }
 return <form className="editor agenda-editor" onSubmit={e=>void submit(e)}>
  {error&&<p className="message error" role="alert">{error}</p>}
  {event?.recurring&&<p className="panel-note">Editarás solo esta ocurrencia. Los demás eventos de la serie se conservan.</p>}
  <Label className="field">Título<Input aria-label="Título del evento" value={title} onChange={e=>setTitle(e.target.value)} required maxLength={300} disabled={busy}/></Label>
  <label className="agenda-all-day"><input type="checkbox" checked={allDay} onChange={e=>toggle(e.target.checked)} disabled={busy}/>Todo el día</label>
  <div className="form-grid"><Label className="field">Inicio<Input aria-label="Inicio del evento" type={allDay?'date':'datetime-local'} value={start} onChange={e=>setStart(e.target.value)} required disabled={busy}/></Label><Label className="field">{allDay?'Último día':'Fin'}<Input aria-label="Fin del evento" type={allDay?'date':'datetime-local'} value={end} onChange={e=>setEnd(e.target.value)} required disabled={busy}/></Label></div>
  <p className="muted">Hora de Colombia. Se guardará en el calendario seleccionado de Google.</p>
  <Label className="field">Lugar<Input aria-label="Lugar del evento" value={location} onChange={e=>setLocation(e.target.value)} maxLength={1024} disabled={busy}/></Label>
  <Label className="field">Descripción<textarea aria-label="Descripción del evento" value={description} onChange={e=>setDescription(e.target.value)} maxLength={8192} rows={4} disabled={busy}/></Label>
  <Button className="primary" type="submit" disabled={busy}>{busy?'Guardando…':event?'Guardar evento':'Crear evento'}</Button>
 </form>;
}
