import {z} from 'zod';
import municipalities from './colombia-municipalities.json';
import {validAgendaDate,agendaDate,type AgendaEvent} from './calendar-core';
import type {AccessUser} from './payroll-permissions';
export class CrmFailure extends Error {constructor(message:string,readonly status=400){super(message);}}
export const canCrm=(u:AccessUser)=>!u.legacy&&!u.itinerariesOnly&&u.isOwner;
export const MAX_CENTS=100_000_000_000_000;
export function cents(value:number){const n=Math.round(value*100);if(!Number.isFinite(value)||value<0||n>MAX_CENTS||!Number.isSafeInteger(n)||Math.abs(value*100-n)>0.001)throw new CrmFailure('Revisa el valor COP: usa hasta dos decimales y un máximo de un billón.');return n;}
export const crmMoney=(amount:number)=>'$ '+amount.toLocaleString('es-CO',{minimumFractionDigits:0,maximumFractionDigits:2});
const normalize=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9]+/g,' ').trim();
const names=[...new Set(municipalities.map(m=>m.name))].map(name=>({name,match:normalize(name)})).concat([{name:'BOGOTÁ, D.C.',match:'BOGOTA'}]).sort((a,b)=>b.match.length-a.match.length);
export function showMunicipalities(title:string){const text=' '+normalize(title)+' ',found:{name:string;match:string}[]=[];for(const m of names)if(text.includes(' '+m.match+' ')&&!found.some(other=>(' '+other.match+' ').includes(' '+m.match+' ')))found.push(m);return [...new Set(found.map(m=>m.name))];}
export function calendarShowDate(event:AgendaEvent){return event.allDay?event.start:agendaDate(new Date(event.start));}
export type CrmShowRow={id:string;calendar_id:string;event_id:string;title:string;municipality:string;show_date:string;source_state:string;status:string;sale_cents:number|null;paid_cents:number;receipt_sequence:number;entrepreneur:string;contact_id:string;note:string;promotional:number;version:number;created_at:string;updated_at:string};
export type CrmPaymentRow={id:string;show_id:string;amount_cents:number;payment_date:string;note:string;hash:string;actor_id:string;upload_token:string;status:string;version:number;created_at:string;voided_at:string;voided_by:string;void_reason:string};
export function publicCrmShow(r:CrmShowRow){const balance=r.sale_cents===null?null:(r.sale_cents-r.paid_cents)/100;return {id:r.id,title:r.title,municipality:r.municipality,showDate:r.show_date,sourceState:r.source_state,status:r.status,sale:r.sale_cents===null?null:r.sale_cents/100,paid:r.paid_cents/100,receiptNext:(r.receipt_sequence??0)+1,balance,entrepreneur:r.entrepreneur,contactId:r.contact_id||null,note:r.note,promotional:r.promotional===1,version:r.version,updatedAt:r.updated_at};}
export type CrmShow=ReturnType<typeof publicCrmShow>;
const uuid=z.string().uuid(),date=z.string().refine(validAgendaDate),amount=z.number().min(0).max(1e12).refine(n=>{try{cents(n);return true;}catch{return false;}});
export const crmShowInput=z.object({id:uuid,version:z.number().int().positive(),sale:amount,entrepreneur:z.string().trim().max(200),contactId:z.string().uuid().nullable().optional(),note:z.string().trim().max(1000),status:z.enum(['active','ignored']),promotional:z.boolean()}).strict();
export const crmPaymentInput=z.object({id:uuid,showId:uuid,amount:amount.refine(n=>n>0),paymentDate:date,note:z.string().trim().max(1000),files:z.array(z.object({filename:z.string().min(1).max(160),data:z.string().max(14*1024*1024)}).strict()).min(1).max(5)}).strict();
export const crmVoidInput=z.object({id:uuid,version:z.number().int().positive(),reason:z.string().trim().min(2).max(500)}).strict();
