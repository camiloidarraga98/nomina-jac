'use client';
import {useEffect,useRef,useState} from 'react';
import {FileDown,FileText} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {Input} from '@/components/ui/input';
import CopInput from './cop-input';
import {agendaDate} from '@/lib/calendar-core';
import {contractInput,contractMoney,contractMoneyWords,contractDate,contractFinalDate,contractFilename,type ContractInput} from '@/lib/contract-core';

export default function CrmContractForm(){
 const [form,setForm]=useState<ContractInput>({company:'',nit:'',representative:'',identity:'',eventDate:agendaDate(),venue:'',municipality:'',department:'',showTime:'23:00',price:0,deposited:0,halfDeadline:''}),[busy,setBusy]=useState(false),[error,setError]=useState(''),[document,setDocument]=useState<{url:string;name:string}|null>(null);
 const currentURL=useRef(''),alive=useRef(true);
 useEffect(()=>{alive.current=true;return()=>{alive.current=false;if(currentURL.current)URL.revokeObjectURL(currentURL.current);};},[]);
 function change<K extends keyof ContractInput>(key:K,value:ContractInput[K]){setForm(v=>({...v,[key]:value}));setError('');if(currentURL.current){URL.revokeObjectURL(currentURL.current);currentURL.current='';setDocument(null);}}
 async function generate(e:React.FormEvent){e.preventDefault();const parsed=contractInput.safeParse(form);if(!parsed.success){setError(parsed.error.issues[0]?.message||'Revisa el formulario.');return;}setBusy(true);setError('');
  try{const response=await fetch('/api/crm/contract',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify(parsed.data)});if(!response.ok){const data=await response.json() as {error?:string};if(response.status===401)location.assign('/acceso?returnTo='+encodeURIComponent('/crm?seccion=contratos'));throw Error(data.error||'No pudimos generar el contrato.');}
   const blob=await response.blob();if(!alive.current)return;if(blob.type!=='application/pdf')throw Error('No se recibió el PDF. Reintenta.');if(currentURL.current)URL.revokeObjectURL(currentURL.current);const url=URL.createObjectURL(blob),name=contractFilename(parsed.data);currentURL.current=url;setDocument({url,name});
   const link=window.document.createElement('a');link.href=url;link.download=name;link.click();
  }catch(e){if(alive.current)setError(e instanceof Error?e.message:'No pudimos generar el contrato.');}finally{if(alive.current)setBusy(false);}
 }
 function field(key:'company'|'nit'|'representative'|'identity'|'venue'|'municipality'|'department',label:string,maxLength:number,placeholder?:string){return <label className="field"><span>{label}</span><Input required maxLength={maxLength} value={form[key]} onChange={e=>change(key,e.target.value)} placeholder={placeholder}/></label>;}
 const finalDate=form.eventDate&&/^\d{4}-\d{2}-\d{2}$/.test(form.eventDate)?contractFinalDate(form.eventDate):'';
 return <div className="contract-layout">
  <form className="panel contract-form" onSubmit={generate}>
   <div className="contract-heading"><span className="contract-symbol"><FileText/></span><div><h2>Crear contrato</h2><p>Plantilla oficial JAC Music · cuatro páginas</p></div></div>
   <fieldset disabled={busy}><legend>Empresa contratante</legend><div className="contract-fields">{field('company','Razón social',100,'Nombre completo de la empresa')}{field('nit','NIT',25,'Con dígito de verificación')}{field('representative','Representante legal',90)}{field('identity','Cédula de ciudadanía',25)}</div></fieldset>
   <fieldset disabled={busy}><legend>Presentación</legend><div className="contract-fields"><label className="field"><span>Día del evento</span><Input required type="date" min="1900-01-01" max="2199-12-31" value={form.eventDate} onChange={e=>change('eventDate',e.target.value)}/></label><label className="field"><span>Hora del show</span><Input required type="time" value={form.showTime} onChange={e=>change('showTime',e.target.value)}/></label>{field('venue','Sitio exacto',100,'Parque principal, teatro…')}{field('municipality','Municipio',60)}{field('department','Departamento',40)}</div></fieldset>
   <fieldset disabled={busy}><legend>Precio y forma de pago</legend><div className="contract-fields"><label className="field"><span>Valor del contrato (COP)</span><CopInput label="Valor del contrato (COP)" value={form.price} onChange={value=>change('price',value)}/></label><label className="field"><span>Consignado a la fecha (COP)</span><CopInput label="Consignado a la fecha (COP)" value={form.deposited} onChange={value=>change('deposited',value)}/></label><label className="field"><span>Fecha para completar el 50%</span><Input required type="date" max={finalDate||undefined} min="1900-01-01" value={form.halfDeadline} onChange={e=>change('halfDeadline',e.target.value)}/></label></div></fieldset>
   {error&&<p role="alert" className="message error">{error}</p>}
   <div className="contract-actions"><Button type="submit" className="primary" disabled={busy}><FileDown/>{busy?'Preparando PDF…':'Generar y descargar PDF'}</Button>{document&&<a className="btn" href={document.url} target="_blank" rel="noreferrer">Ver PDF</a>}</div>
  </form>
  <aside className="contract-review"><section className="panel"><h3>Resumen del contrato</h3><div className="contract-review-body"><dl><div><dt>Municipio</dt><dd>{form.municipality||'Por completar'}{form.department?' · '+form.department:''}</dd></div><div><dt>Presentación</dt><dd>{form.eventDate?contractDate(form.eventDate):'Por completar'}</dd></div><div><dt>Valor total</dt><dd>$ {contractMoney(form.price)}</dd></div></dl><p className="contract-words">{contractMoneyWords(form.price)}</p><dl><div><dt>Consignado</dt><dd>$ {contractMoney(form.deposited)}</dd></div><div><dt>Falta para completar el 50%</dt><dd>$ {contractMoney(Math.max(0,form.price/2-form.deposited))}</dd></div><div className="contract-final"><dt>Pago final · 50%</dt><dd>$ {contractMoney(form.price/2)}</dd></div></dl><p className="contract-words">{contractMoneyWords(form.price/2)}</p><p>{finalDate?'Debe consignarse cinco días antes: '+contractDate(finalDate)+'.':'Cinco días antes de la presentación.'}</p><p className="muted">El PDF conserva las cláusulas, el diseño y la firma de JAC Music. Los datos del contratante se completan automáticamente. Generarlo no registra abonos ni crea eventos.</p></div></section>
   {document&&<section className="panel contract-ready"><FileText/><h3>Contrato listo</h3><p>{document.name}</p><a className="btn" href={document.url} download={document.name}><FileDown size={16}/>Descargar nuevamente</a></section>}
  </aside>
 </div>;
}
