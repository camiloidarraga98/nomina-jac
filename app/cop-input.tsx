'use client';
import {useEffect,useLayoutEffect,useRef,useState} from 'react';
import {Input} from '@/components/ui/input';
import {copText,editCop,copPaste} from '@/lib/cop-input';

export default function CopInput({label,value,onChange,disabled=false,max=1e12}:{label:string;value:number;onChange:(value:number)=>void;disabled?:boolean;max?:number}){
 const [draft,setDraft]=useState(()=>copText(value));
 const input=useRef<HTMLInputElement>(null),emitted=useRef(value),selection=useRef<number|null>(null);
 useEffect(()=>{if(value!==emitted.current){emitted.current=value;setDraft(copText(value));}},[value]);
 useLayoutEffect(()=>{
  if(selection.current!==null&&input.current){input.current.setSelectionRange(selection.current,selection.current);selection.current=null;}
  const number=editCop(draft)?.value;
  input.current?.setCustomValidity(number===undefined||number<0||number>max?'Introduce un valor entre 0 y '+copText(max)+' COP.':'');
 },[draft,max]);
 function change(text:string,caret:number){
  const next=editCop(text,caret);if(!next)return;
  selection.current=next.caret;setDraft(next.text);emitted.current=next.value;onChange(next.value);
  // A separator-only edit may keep the same text and skip a React render.
  if(next.text===draft)input.current?.setSelectionRange(next.caret,next.caret);
 }
 function insert(text:string){const field=input.current;if(field)change(draft.slice(0,field.selectionStart??draft.length)+text+draft.slice(field.selectionEnd??draft.length),(field.selectionStart??draft.length)+text.length);}
 return <Input ref={input} aria-label={label} type="text" inputMode="decimal" autoComplete="off" value={draft} disabled={disabled} required
  onChange={e=>change(e.currentTarget.value,e.currentTarget.selectionStart??e.currentTarget.value.length)}
  onFocus={e=>{if(draft==='0')e.currentTarget.select();}}
  onKeyDown={e=>{if(e.key==='.'&&!e.ctrlKey&&!e.metaKey&&!e.altKey){e.preventDefault();insert(',');}}}
  onPaste={e=>{e.preventDefault();const text=copPaste(e.clipboardData.getData('text'));if(text!==null)insert(text);}}
  onBlur={()=>{if(draft){selection.current=null;setDraft(copText(value));}}}/>;
}
