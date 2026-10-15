'use client';
import {useRef,useState,useEffect,useId} from 'react';
import {UploadCloud,FileText,CheckCircle2,X,LoaderCircle} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {crmReceiptName} from '@/lib/crm-receipts';
import {prepareCrmFiles,type CrmFile} from './crm-files';
export default function CrmAttachments({files,onChange,title,next=1,disabled=false,onPreparing,label='Comprobantes del abono',saveHint,documents=false}:{files:CrmFile[];onChange:(f:CrmFile[])=>void;title:string;next?:number;disabled?:boolean;onPreparing:(v:boolean)=>void;label?:string;saveHint?:string;documents?:boolean}){
 const input=useRef<HTMLInputElement>(null),working=useRef(false),alive=useRef(true),depth=useRef(0),[dragging,setDragging]=useState(false),[reading,setReading]=useState(false),[error,setError]=useState(''),hint=useId();
 useEffect(()=>{alive.current=true;return()=>{alive.current=false;};},[]);
 const locked=disabled||reading;
 async function attach(incoming:File[]){
  if(disabled||working.current||!incoming.length)return;
  working.current=true;setReading(true);onPreparing(true);setError('');
  try{const ready=await prepareCrmFiles(files,incoming);if(alive.current)onChange(ready);}
  catch(e){if(alive.current)setError(e instanceof Error?e.message:'No pudimos leer el comprobante. Selecciónalo de nuevo.');}
  finally{working.current=false;if(alive.current){setReading(false);onPreparing(false);}}
 }
 return <section className="crm-attachments" aria-label={label}>
  <div className={'crm-dropzone'+(dragging?' dragging':'')+(locked?' disabled':'')} data-testid="crm-receipt-dropzone" aria-busy={reading} onDragEnter={e=>{e.preventDefault();if(!locked){depth.current++;setDragging(true);}}} onDragOver={e=>{e.preventDefault();e.dataTransfer.dropEffect=locked?'none':'copy';}} onDragLeave={e=>{e.preventDefault();if(--depth.current<=0){depth.current=0;setDragging(false);}}} onDrop={e=>{e.preventDefault();depth.current=0;setDragging(false);if(!locked)void attach(Array.from(e.dataTransfer.files));}}>
   {reading?<LoaderCircle className="agenda-spinning" size={30}/>:<UploadCloud size={30}/>}
   <strong>{reading?(documents?'Preparando documentos…':'Preparando comprobantes…'):(documents?'Arrastra aquí tus documentos':'Arrastra aquí tus comprobantes')}</strong>
   <span id={hint}>PDF, JPG o PNG · Hasta 5 archivos y 10 MB en total</span>
   <Button type="button" variant="outline" disabled={locked} onClick={()=>input.current?.click()}>Seleccionar archivos</Button>
   <input ref={input} type="file" aria-label={label} aria-describedby={hint} accept="application/pdf,image/jpeg,image/png" multiple hidden disabled={locked} onChange={e=>{const chosen=Array.from(e.target.files??[]);e.target.value='';void attach(chosen);}}/>
  </div>
  {error&&<p role="alert" className="message error">{error}</p>}
  {files.length>0&&<ul className="crm-pending-files" aria-label={documents?'Documentos adjuntados':'Comprobantes adjuntados'}>{files.map((f,i)=><li key={i}><FileText size={21}/><div><strong>{title.trim()?crmReceiptName(title,next+i,f.mimeType):f.filename}</strong><small>{f.filename} · {(f.size/1024).toFixed(0)} KB</small></div><CheckCircle2 className="crm-file-ready" size={18}/><Button type="button" variant="ghost" aria-label={'Quitar '+f.filename} disabled={locked} onClick={()=>{onChange(files.filter((_,index)=>index!==i));setError('');}}><X size={17}/></Button></li>)}</ul>}
  {files.length>0&&<p className="crm-upload-hint" role="status">{documents?(files.length===1?'Documento adjuntado.':'Documentos adjuntados.'):(files.length===1?'Comprobante adjuntado.':'Comprobantes adjuntados.')} {saveHint??'Se guardarán al confirmar el abono. El consecutivo definitivo se asigna al guardar.'}</p>}
 </section>;
}
