import {agendaMonth,type AgendaData} from './calendar-core';
import type {AgendaCache} from './agenda-cache';
const FRESH_FOR=15*60*1000;
export function agendaWindowMonths(first:string){
 agendaMonth(first);const start=new Date(first+'-01T12:00:00Z');
 return Array.from({length:6},(_,offset)=>{const d=new Date(start);d.setUTCMonth(d.getUTCMonth()+offset);const month=d.toISOString().slice(0,7);agendaMonth(month);return month;});
}
// Low-priority sequential reads use the existing authorized API. They never
// change the selected month, event, editor or visible calendar.
export async function prefetchAgendaWindow({first,revision,selected,cache,fetchMonth,current,now=Date.now}:{first:string;revision:number;selected:string;cache:AgendaCache;fetchMonth:(month:string)=>Promise<AgendaData>;current:()=>boolean;now?:()=>number}){
 const epoch=cache.epoch,valid=()=>current()&&cache.active&&cache.epoch===epoch;
 for(const month of agendaWindowMonths(first)){
  if(!valid())return 'stopped';
  const saved=await cache.read(month);if(!valid())return 'stopped';
  if(saved&&saved.connection.revision>revision)return 'changed';
  if(saved?.connection.revision===revision&&saved.connection.selected?.id===selected){const age=now()-Date.parse(saved.updatedAt);if(age>=0&&age<FRESH_FOR)continue;}
  const fresh=await fetchMonth(month);if(!valid())return 'stopped';
  if(fresh.month!==month)throw new Error('La respuesta no corresponde al mes solicitado.');
  if(fresh.connection.revision!==revision||fresh.connection.selected?.id!==selected||!fresh.connection.connected){cache.clearData();return 'changed';}
  if(!await cache.write(fresh))return 'unavailable';
 }
 return 'complete';
}
