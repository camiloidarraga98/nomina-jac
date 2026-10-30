'use client';
import {useEffect,useId,useRef,useState} from 'react';
import {Check,Search} from 'lucide-react';
import {Input} from '@/components/ui/input';
import {categoryNames,type Employee} from '@/lib/payroll';

const normalize=(text:string)=>text.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('es').trim();

// Keep Escape inside the suggestions before Radix handles it on the dialog.
export function protectPayrollPersonSuggestions(event:KeyboardEvent){
 if(event.target instanceof Element&&event.target.hasAttribute('data-payroll-person')&&event.target.getAttribute('aria-expanded')==='true')event.preventDefault();
}

export default function PayrollPersonInput({employees,value,onChange,disabled=false}:{employees:Employee[];value:string;onChange:(id:string)=>void;disabled?:boolean}){
 const id=useId(),input=useRef<HTMLInputElement>(null),list=useRef<HTMLUListElement>(null);
 const selected=employees.find(e=>e.id===value);
 const [query,setQuery]=useState(()=>selected?.name??''),[open,setOpen]=useState(false),[active,setActive]=useState(-1);
 const words=normalize(query).split(/\s+/).filter(Boolean);
 const matches=words.length?employees.filter(e=>words.every(word=>normalize(e.name).includes(word))).slice(0,8):[];
 const expanded=open&&words.length>0&&!disabled;
 useEffect(()=>{input.current?.setCustomValidity(selected&&query===selected.name?'':'Selecciona una persona de las sugerencias.');},[query,selected]);
 useEffect(()=>{if(expanded&&active>=0)list.current?.children[active]?.scrollIntoView({block:'nearest'});},[active,expanded]);
 function choose(person:Employee){input.current?.focus({preventScroll:true});setQuery(person.name);onChange(person.id);setOpen(false);setActive(-1);}
 return <div className="field payroll-person-field" onBlur={e=>{
  const field=e.currentTarget;
  // Let the next input receive focus before removing the list from Radix's focus scope.
  requestAnimationFrame(()=>{if(field.isConnected&&!field.contains(document.activeElement)){setOpen(false);setActive(-1);}});
 }}>
  <label className="field-label" htmlFor={id}>Persona</label>
  <div className="payroll-person-control">
   <Search size={18} className="payroll-person-search" aria-hidden="true"/>
   <Input ref={input} id={id} data-payroll-person aria-label="Persona" role="combobox" aria-autocomplete="list" aria-expanded={expanded} aria-controls={expanded?id+'-list':undefined} aria-activedescendant={expanded&&active>=0&&matches[active]?id+'-option-'+active:undefined} autoComplete="off" placeholder="Escribe el nombre o apellido" value={query} required maxLength={200} disabled={disabled}
    onFocus={e=>{setOpen(false);setActive(-1);if(selected)e.currentTarget.select();}}
    onChange={e=>{setQuery(e.target.value);onChange('');setOpen(true);setActive(-1);}}
    onKeyDown={e=>{
     if(e.nativeEvent.isComposing)return;
     if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);setActive(i=>matches.length?(e.key==='ArrowDown'?(i+1)%matches.length:(i<=0?matches.length-1:i-1)):-1);}
     else if(e.key==='Enter'&&expanded){e.preventDefault();if(active>=0&&matches[active])choose(matches[active]);else if(matches.length===1)choose(matches[0]);}
     else if(e.key==='Escape'&&expanded){e.preventDefault();e.stopPropagation();setOpen(false);setActive(-1);}
    }}/>
   {expanded&&<div className="payroll-person-menu"><ul ref={list} id={id+'-list'} role="listbox" aria-label="Personas de nómina">
    {matches.map((person,index)=><li key={person.id} role="presentation"><button type="button" role="option" id={id+'-option-'+index} aria-selected={active===index} tabIndex={-1} className={active===index?'active':''} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(person)}>
     <span><strong>{person.name}</strong><small>{person.role||categoryNames[person.category]}</small></span>{person.id===value&&<Check size={17} aria-hidden="true"/>}
    </button></li>)}
   </ul>{!matches.length&&<p role="status">No hay personas con ese nombre.</p>}</div>}
  </div>
 </div>;
}
