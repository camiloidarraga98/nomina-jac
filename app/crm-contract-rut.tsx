'use client';
import {useEffect,useRef,useState} from 'react';
import {FileUp,CheckCircle2,X} from 'lucide-react';
import {Button} from '@/components/ui/button';
import type {ContractInput} from '@/lib/contract-core';
import type {RutExtraction,RutRepresentative} from '@/lib/rut-extract';

export type ContractParty=Pick<ContractInput,'company'|'nit'|'representative'|'identity'>;
const citizen=(r:RutRepresentative)=>r.documentType==='Cédula de ciudadanía';
const identity=(r:RutRepresentative)=>citizen(r)?r.identity.replace(/\B(?=(\d{3})+(?!\d))/g,'.'):'';
export default function CrmContractRut({disabled,onReadState,onFill}:{disabled:boolean;onReadState:(reading:boolean)=>void;onFill:(party:Partial<ContractParty>)=>void}){
 const input=useRef<HTMLInputElement>(null),operation=useRef<AbortController|null>(null),alive=useRef(true);
 const [reading,setReading]=useState(false),[error,setError]=useState(''),[result,setResult]=useState<RutExtraction|null>(null),[selected,setSelected]=useState(''),[progress,setProgress]=useState('');
 useEffect(()=>{alive.current=true;return()=>{alive.current=false;operation.current?.abort();onReadState(false);};},[onReadState]);
 const principals=result?.representatives.filter(r=>r.kind==='principal')??[];
 function stop(){operation.current?.abort();operation.current=null;setReading(false);onReadState(false);setProgress('');}
 async function read(file:File){
  operation.current?.abort();const controller=new AbortController();operation.current=controller;setError('');setResult(null);setSelected('');setReading(true);onReadState(true);setProgress('Leyendo RUT…');
  try{const {readRutPDF}=await import('@/lib/rut-pdf-client');if(controller.signal.aborted)return;const extracted=await readRutPDF(file,controller.signal,(page,total)=>{if(alive.current&&operation.current===controller)setProgress(`Leyendo RUT · ${page} de ${total}`);});if(!alive.current||operation.current!==controller||controller.signal.aborted)return;
   const legal=extracted.representatives.filter(r=>r.kind==='principal'),candidate=legal.length===1?legal[0]:undefined;
   const representative=candidate&&citizen(candidate)&&candidate.name&&/^\d+$/.test(candidate.identity)&&!extracted.warnings.some(w=>/nombre o identificación incompletos/.test(w))?candidate:undefined;
   setResult(extracted);setSelected(representative?'0':'');
   // A new RUT replaces all four party fields together, avoiding mixed identities.
   onFill({company:extracted.company??'',nit:extracted.nit??'',representative:representative?.name??'',identity:representative?identity(representative):''});
  }catch(e){if(alive.current&&operation.current===controller&&!controller.signal.aborted)setError(e instanceof Error?e.message:'No pudimos leer el RUT. Puedes completar los datos manualmente.');}
  finally{if(alive.current&&operation.current===controller){setReading(false);onReadState(false);setProgress('');operation.current=null;}}
 }
 return <section className="contract-rut" aria-label="Completar datos desde RUT">
  <div className="contract-rut-heading"><div><h3>¿Tienes el RUT?</h3><p>Súbelo para completar los datos de la empresa. También puedes escribirlos abajo.</p></div><div className="contract-rut-buttons"><Button type="button" className="primary" disabled={disabled||reading} onClick={()=>input.current?.click()}><FileUp size={18}/>{reading?'Leyendo RUT…':'Subir RUT'}</Button>{reading&&<Button type="button" variant="outline" onClick={stop}><X size={16}/>Cancelar</Button>}</div></div>
  <input ref={input} type="file" accept="application/pdf,.pdf" aria-label="Seleccionar RUT en PDF" className="sr-only" disabled={disabled||reading} onChange={e=>{const file=e.currentTarget.files?.[0];e.currentTarget.value='';if(file)void read(file);}}/>
  <small>El archivo se lee en tu navegador y no se guarda en el sitio.</small>
  {reading&&<p className="contract-rut-status" role="status">{progress}</p>}
  {error&&<p className="message error" role="alert">{error}</p>}
  {result&&<><p className="contract-rut-status" role="status"><CheckCircle2 size={16}/>Datos del RUT cargados. Puedes revisarlos y modificarlos abajo.</p>
   {principals.length>1&&<label className="field"><span>Representante que firmará</span><select value={selected} disabled={disabled} onChange={e=>{const value=e.currentTarget.value;setSelected(value);const r=principals[Number(value)];onFill({representative:value&&r?r.name:'',identity:value&&r?identity(r):''});}}><option value="">Selecciona el representante principal</option>{principals.map((r,i)=><option key={i} value={String(i)}>{r.name} · {r.documentType} {r.identity}</option>)}</select></label>}
   {!!result.warnings.length&&<ul className="contract-rut-warnings">{result.warnings.map((warning,i)=><li key={i}>{warning}</li>)}</ul>}
  </>}
 </section>;
}
