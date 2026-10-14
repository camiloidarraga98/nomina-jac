import {z} from 'zod';
import {agendaMonth,type AgendaData} from './calendar-core';
export type AgendaCacheContext={scope:string;key:string};
export const AGENDA_CACHE_KEY='jac.agenda.encrypted.v1',AGENDA_SCOPE_KEY='jac.agenda.scope.v1';
const MAX_BYTES=1_500_000,MAX_MONTHS=6;
const text=z.string().max(8192),date=z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const event=z.object({id:text,title:text,start:text,end:text,allDay:z.boolean(),location:text,description:text,url:text,etag:text,editable:z.boolean(),recurring:z.boolean()});
const dataSchema=z.object({connection:z.object({configured:z.boolean(),connected:z.boolean(),email:text,selected:z.object({id:text,name:text,timeZone:text,primary:z.boolean(),writable:z.boolean().optional()}).nullable(),revision:z.number().int().nonnegative(),writeAuthorized:z.boolean()}),canEditEvents:z.boolean(),month:z.string().regex(/^(19|20|21)\d\d-(0[1-9]|1[0-2])$/),monthLabel:text,days:z.array(date).length(42),today:date,events:z.array(event).max(5000),upcoming:z.array(event).max(5000),upcomingUntil:date,updatedAt:z.string().datetime(),timeZone:z.literal('America/Bogota')});
const payloadSchema=z.array(dataSchema).max(MAX_MONTHS);
type StoragePort=Pick<Storage,'getItem'|'setItem'|'removeItem'>;
type CacheEnvironment={storage:StoragePort;crypto:Crypto};
const encode=(bytes:Uint8Array)=>btoa(String.fromCharCode(...bytes));
const decode=(value:string)=>Uint8Array.from(atob(value),c=>c.charCodeAt(0));
const keyBytes=(value:string)=>decode(value.replace(/-/g,'+').replace(/_/g,'/')+'=');
const aad=(scope:string,revision:number,selected:string)=>new TextEncoder().encode(JSON.stringify([scope,revision,selected]));
const readOnly=(data:AgendaData):AgendaData=>({...data,canEditEvents:false,events:data.events.map(e=>({...e,editable:false})),upcoming:data.upcoming.map(e=>({...e,editable:false}))});
// Operations are serialized; stop/clear increments the generation before any
// outstanding decrypt/encrypt can restore content or write it after logout.
export class AgendaCache {
 private stopped=false;private generation=0;private queue:Promise<unknown>=Promise.resolve();private listeners=new Set<()=>void>();
 constructor(readonly context:AgendaCacheContext,private env:CacheEnvironment){
  try{if(env.storage.getItem(AGENDA_SCOPE_KEY)!==context.scope){env.storage.removeItem(AGENDA_CACHE_KEY);env.storage.setItem(AGENDA_SCOPE_KEY,context.scope);}}catch{/* Storage unavailable: network continues normally. */}
 }
 get active(){try{return !this.stopped&&this.env.storage.getItem(AGENDA_SCOPE_KEY)===this.context.scope;}catch{return false;}}
 subscribe(fn:()=>void){this.listeners.add(fn);return()=>{this.listeners.delete(fn);};}
 stop(){if(this.stopped)return;this.stopped=true;this.generation++;for(const fn of this.listeners)fn();}
 clearData(){this.generation++;try{if(this.active)this.env.storage.removeItem(AGENDA_CACHE_KEY);}catch{}}
 invalidate(){this.clearData();try{if(this.active)this.env.storage.removeItem(AGENDA_SCOPE_KEY);}catch{}this.stop();}
 private serial<T>(fn:()=>Promise<T>){const task=this.queue.then(fn,fn);this.queue=task.catch(()=>{});return task;}
 private async key(){return this.env.crypto.subtle.importKey('raw',keyBytes(this.context.key),{name:'AES-GCM'},false,['encrypt','decrypt']);}
 private async unpack(){
  const raw=this.env.storage.getItem(AGENDA_CACHE_KEY);if(!raw)return null;
  if(raw.length>MAX_BYTES)throw new Error('Cache too large');
  const box=JSON.parse(raw);if(box.scope!==this.context.scope||!Number.isSafeInteger(box.revision)||box.revision<0||typeof box.selected!=='string'||box.selected.length>8192||typeof box.iv!=='string'||box.iv.length!==16||typeof box.cipher!=='string')throw new Error('Invalid cache');
  const clear=await this.env.crypto.subtle.decrypt({name:'AES-GCM',iv:decode(box.iv),additionalData:aad(box.scope,box.revision,box.selected)},await this.key(),decode(box.cipher));
  const records=payloadSchema.parse(JSON.parse(new TextDecoder().decode(clear)));
  if(records.some(d=>d.connection.revision!==box.revision||d.connection.selected?.id!==box.selected||!d.connection.connected||d.days.join()!==agendaMonth(d.month).days.join()))throw new Error('Invalid calendar binding');
  return {raw,revision:box.revision as number,selected:box.selected as string,records};
 }
 read(month:string){const generation=this.generation;return this.serial(async()=>{
  if(!this.active||generation!==this.generation)return null;
  try{const box=await this.unpack();if(!this.active||generation!==this.generation)return null;const record=box?.records.find(d=>d.month===month);return record?readOnly(record):null;}catch{if(this.active&&generation===this.generation)this.clearData();return null;}
 });}
 write(data:AgendaData){const generation=this.generation;return this.serial(async()=>{
  if(!this.active||generation!==this.generation)return false;
  try{
   const fresh=dataSchema.parse(data);let old=null;try{old=await this.unpack();}catch{/* Replace corrupt data only with a fresh authorized response. */}
   if(old&&old.revision>fresh.connection.revision)return false;
   if(old?.revision===fresh.connection.revision&&old.records.some(d=>d.month===fresh.month&&d.updatedAt>fresh.updatedAt))return false;
   if(!this.active||generation!==this.generation)return false;
   const previous=this.env.storage.getItem(AGENDA_CACHE_KEY);if(previous&&JSON.parse(previous).revision>fresh.connection.revision)return false;
   // Once a new selection/disconnection is confirmed, retire the old copy
   // even if encryption or storage of the replacement subsequently fails.
   if(old&&(old.revision!==fresh.connection.revision||old.selected!==fresh.connection.selected?.id||!fresh.connection.connected))this.env.storage.removeItem(AGENDA_CACHE_KEY);
   let records=fresh.connection.connected&&fresh.connection.selected?[fresh,...(old?.revision===fresh.connection.revision&&old.selected===fresh.connection.selected.id?old.records.filter(d=>d.month!==fresh.month):[])].slice(0,MAX_MONTHS):[];
   const revision=fresh.connection.revision,selected=fresh.connection.selected?.id||'';
   let packed='';while(true){const clear=new TextEncoder().encode(JSON.stringify(records));const iv=this.env.crypto.getRandomValues(new Uint8Array(12));const cipher=new Uint8Array(await this.env.crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:aad(this.context.scope,revision,selected)},await this.key(),clear));
    // Avoid argument limits when encoding larger calendar copies.
    let binary='';for(let i=0;i<cipher.length;i+=8192)binary+=String.fromCharCode(...cipher.subarray(i,i+8192));
    packed=JSON.stringify({scope:this.context.scope,revision,selected,iv:encode(iv),cipher:btoa(binary)});if(packed.length<=MAX_BYTES||!records.length)break;records=records.slice(0,-1);
   }
   if(!this.active||generation!==this.generation)return false;
   // Another tab may have learned about a newer connection while we encrypted.
   const current=this.env.storage.getItem(AGENDA_CACHE_KEY);if(current&&JSON.parse(current).revision>revision)return false;
   this.env.storage.setItem(AGENDA_CACHE_KEY,packed);return records.length>0;
  }catch{return false;}
 });}
}
let browserCache:AgendaCache|null=null,watching=false;
export function bindAgendaCache(context:AgendaCacheContext|null){
 if(typeof window==='undefined'||!context)return null;
 if(browserCache?.context.scope===context.scope)return browserCache;
 browserCache?.stop();
 try{browserCache=new AgendaCache(context,{storage:localStorage,crypto:window.crypto});}catch{return null;}
 if(!watching){watching=true;const check=()=>{if(browserCache&&!browserCache.active)browserCache.stop();};window.addEventListener('storage',e=>{if(e.key===AGENDA_SCOPE_KEY||e.key===null)check();});window.addEventListener('pageshow',check);}
 return browserCache;
}
export function clearBrowserAgendaCache(){
 browserCache?.invalidate();browserCache=null;
 try{localStorage.removeItem(AGENDA_CACHE_KEY);localStorage.removeItem(AGENDA_SCOPE_KEY);}catch{}
}
