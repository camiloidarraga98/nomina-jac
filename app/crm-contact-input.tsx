'use client';
import {useId,useState} from 'react';
import {Check,UserRound} from 'lucide-react';
import {Input} from '@/components/ui/input';
import type {CrmContactChoice} from './crm-workspace';

const normalize=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('es').trim();

// Radix handles Escape at document capture, before the input's React handler.
export function protectCrmContactSuggestions(event:KeyboardEvent){
 if(event.target instanceof Element&&event.target.hasAttribute('data-crm-contact')&&event.target.getAttribute('aria-expanded')==='true')event.preventDefault();
}

export default function CrmContactInput({contacts,name,contactId,onChange,disabled=false,label}:{contacts:CrmContactChoice[];name:string;contactId:string;onChange:(name:string,id:string)=>void;disabled?:boolean;label:string}){
 const id=useId(),[open,setOpen]=useState(false),[active,setActive]=useState(-1);
 const query=normalize(name),matches=contacts.filter(c=>normalize(c.name+' '+c.company).includes(query)).slice(0,8),selected=contacts.find(c=>c.id===contactId),expanded=open&&!disabled;
 function choose(c:CrmContactChoice){onChange(c.name,c.id);setOpen(false);setActive(-1);}
 return <div className="field crm-contact-field" onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget)){setOpen(false);setActive(-1);}}}>
  <label htmlFor={id}>Empresario</label>
  <div className="crm-contact-control">
   <Input id={id} data-crm-contact aria-label={label} role="combobox" aria-autocomplete="list" aria-expanded={expanded} aria-controls={expanded?id+'-list':undefined} aria-activedescendant={expanded&&active>=0&&matches[active]?id+'-option-'+active:undefined} autoComplete="off" placeholder="Escribe el nombre del empresario" value={name} maxLength={200} disabled={disabled} onFocus={()=>{setOpen(true);setActive(-1);}} onChange={e=>{onChange(e.target.value,'');setOpen(true);setActive(-1);}} onKeyDown={e=>{
    if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);setActive(i=>matches.length?(e.key==='ArrowDown'?(i+1)%matches.length:(i<=0?matches.length-1:i-1)):-1);}
    else if(e.key==='Enter'&&expanded&&active>=0&&matches[active]){e.preventDefault();choose(matches[active]);}
    else if(e.key==='Escape'&&expanded){e.preventDefault();e.stopPropagation();setOpen(false);setActive(-1);}
   }}/>
   {expanded&&<div className="crm-contact-menu"><ul id={id+'-list'} role="listbox" aria-label="Empresarios guardados">
    {matches.map((c,i)=><li key={c.id} role="presentation"><button type="button" role="option" id={id+'-option-'+i} aria-selected={active===i} tabIndex={-1} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(c)} className={active===i?'active':''}><UserRound size={18} aria-hidden="true"/><span><strong>{c.name}</strong>{c.company&&<small>{c.company}</small>}</span>{c.id===contactId&&<Check size={17} aria-hidden="true"/>}</button></li>)}
   </ul>{!matches.length&&<p>No hay coincidencias. Puedes usar este nombre.</p>}</div>}
  </div>
  {selected&&<small className="crm-contact-selected"><Check size={14} aria-hidden="true"/>{selected.company||'Contacto guardado'}</small>}
 </div>;
}
