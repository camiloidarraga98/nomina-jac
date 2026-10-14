'use client';
import {useState} from 'react';
import {Button} from '@/components/ui/button';
import {Input} from '@/components/ui/input';
import CopInput from './cop-input';
import {crmFilePayload,type CrmFile} from './crm-files';
import CrmAttachments from './crm-attachments';
import {agendaDate,addAgendaDays} from '@/lib/calendar-core';
export type CrmCalendar={ready:boolean;revision:number;name:string};
export default function CrmCreateForm({calendar,save,onBusy}:{calendar?:CrmCalendar;save:(record:unknown)=>Promise<void>;onBusy:(v:boolean)=>void}){
 const [id]=useState(()=>crypto.randomUUID()),[title,setTitle]=useState(''),[startDate,setStartDate]=useState(agendaDate()),[allDay,setAllDay]=useState(true),[startTime,setStartTime]=useState('19:00'),[endTime,setEndTime]=useState('21:00'),[location,setLocation]=useState(''),[description,setDescription]=useState('');
 const [sale,setSale]=useState(0),[entrepreneur,setEntrepreneur]=useState(''),[note,setNote]=useState(''),[promotional,setPromotional]=useState(false),[withPayment,setWithPayment]=useState(false),[amount,setAmount]=useState(0),[paymentDate,setPaymentDate]=useState(agendaDate()),[paymentNote,setPaymentNote]=useState(''),[files,setFiles]=useState<CrmFile[]>([]),[preparing,setPreparing]=useState(false),[busy,setBusy]=useState(false),[attempt,setAttempt]=useState<unknown>(null),[error,setError]=useState('');
 const locked=busy||!!attempt;
 return <form className="editor crm-create-form" onSubmit={async e=>{
  e.preventDefault();if(busy||preparing)return;setError('');setBusy(true);onBusy(true);
  try{
   if(!attempt&&(!calendar?.ready||!title.trim()))throw Error('Conecta Agenda y completa el nombre del show.');
   if(!attempt&&withPayment&&(amount<=0||!files.length||files.length>5||files.reduce((v,f)=>v+f.size,0)>10*1024*1024))throw Error('El primer abono requiere valor positivo y hasta cinco PDF, JPG o PNG (10 MB en total).');
   const start=allDay?startDate:new Date(startDate+'T'+startTime+':00-05:00').toISOString(),end=allDay?addAgendaDays(startDate,1):new Date(startDate+'T'+endTime+':00-05:00').toISOString();
   if(!attempt&&(end<=start||startDate<agendaDate()))throw Error('Elige una fecha de hoy en adelante y una hora de fin posterior al inicio en el mismo día.');
   const record=attempt??{id,revision:calendar!.revision,event:{title:title.trim(),start,end,allDay,location,description},sale,entrepreneur,note,promotional,...(withPayment?{firstPayment:{amount,paymentDate,note:paymentNote,files:crmFilePayload(files)}}:{})};
   setAttempt(record);await save(record);
  }catch(e){if(e instanceof Error&&'status' in e&&e.status===400)setAttempt(null);setError(e instanceof Error?e.message:'No se confirmó el resultado. Reintenta este mismo formulario.');}
  finally{setBusy(false);onBusy(false);}
 }}>
  {!calendar?.ready&&<p className="message error">Agenda debe estar conectada con permiso para crear eventos. Revisa Servicios conectados antes de guardar.</p>}
  <section className="crm-form-section"><h3>Evento compartido en Agenda</h3><p className="muted">Se guardará en {calendar?.name||'el calendario compartido de JAC'} y aparecerá en la web, el iPhone y Google Calendar.</p>
   <label className="field">Nombre del show o municipio<Input aria-label="Nombre del nuevo show" required maxLength={300} value={title} onChange={e=>setTitle(e.target.value)} disabled={locked}/></label>
   <label className="field">Fecha del evento<Input aria-label="Fecha del evento" type="date" required min={agendaDate()} value={startDate} disabled={locked} onChange={e=>setStartDate(e.target.value)}/></label>
   <label className="toggle"><input type="checkbox" checked={allDay} onChange={e=>setAllDay(e.target.checked)} disabled={locked}/>Todo el día</label>
   {!allDay&&<div className="form-grid"><label className="field">Hora de inicio (Colombia)<Input aria-label="Hora de inicio del show" type="time" required value={startTime} onChange={e=>setStartTime(e.target.value)} disabled={locked}/></label><label className="field">Hora de fin (Colombia)<Input aria-label="Hora de fin del show" type="time" required value={endTime} onChange={e=>setEndTime(e.target.value)} disabled={locked}/></label></div>}
   <label className="field">Lugar<Input aria-label="Lugar del show" value={location} maxLength={1024} onChange={e=>setLocation(e.target.value)} disabled={locked}/></label>
   <label className="field">Descripción compartida<textarea aria-label="Descripción compartida del show" value={description} maxLength={8192} onChange={e=>setDescription(e.target.value)} disabled={locked}/></label>
  </section>
  <section className="crm-form-section"><h3>Datos privados del CRM</h3><p className="muted">El precio, los abonos y sus comprobantes son solo para Camilo y jac. No se envían a Calendar.</p>
   <div className="form-grid"><div className="field"><span>Valor de venta (COP)</span><CopInput label="Valor de venta del nuevo show (COP)" value={sale} onChange={setSale} disabled={locked}/></div><label className="field">Empresario<Input aria-label="Empresario del nuevo show" value={entrepreneur} maxLength={200} onChange={e=>setEntrepreneur(e.target.value)} disabled={locked}/></label></div>
   <label className="field">Observaciones internas<Input aria-label="Observaciones privadas del nuevo show" value={note} maxLength={1000} onChange={e=>setNote(e.target.value)} disabled={locked}/></label><label className="toggle"><input type="checkbox" checked={promotional} onChange={e=>setPromotional(e.target.checked)} disabled={locked}/>Show promocional</label>
  </section>
  <section className="crm-form-section"><label className="toggle"><input type="checkbox" checked={withPayment} onChange={e=>setWithPayment(e.target.checked)} disabled={locked||preparing}/>Registrar primer abono</label>
   {withPayment&&<><div className="form-grid"><div className="field"><span>Primer abono (COP)</span><CopInput label="Valor del primer abono (COP)" value={amount} onChange={setAmount} disabled={locked}/></div><label className="field">Fecha del abono<Input aria-label="Fecha del primer abono" type="date" required value={paymentDate} onChange={e=>setPaymentDate(e.target.value)} disabled={locked}/></label></div><label className="field">Observación del abono<Input aria-label="Observación del primer abono" value={paymentNote} maxLength={1000} onChange={e=>setPaymentNote(e.target.value)} disabled={locked}/></label><CrmAttachments files={files} onChange={setFiles} title={title} disabled={locked} onPreparing={setPreparing} label="Comprobantes del primer abono"/></>}
  </section>
  {error&&<p role="alert" className="message error">{error}</p>}{!!attempt&&error&&<p className="muted">Conservamos el mismo evento y abono para reintentar sin duplicarlos.</p>}
  <Button className="primary" type="submit" disabled={busy||preparing||!calendar?.ready}>{busy?'Guardando…':attempt?'Reintentar creación':'Crear show y sincronizar'}</Button>
 </form>;
}
