import {periodLabel,type Period,type Employee} from './payroll';
export const GMAIL_SENDER='jacmusicestudios@gmail.com';
export const GMAIL_CALLBACK='https://jhonalexcastano.com/api/payroll/gmail/callback';
export const GMAIL_SCOPES='openid email https://www.googleapis.com/auth/gmail.send';
export type MailStatus='pending'|'missing'|'sending'|'sent'|'error'|'uncertain'|'cancelled';
export type MailJob={id:string;batchId:string;employeeId:string;name:string;email:string;status:MailStatus;attempts:number;error:string;sentAt:string|null;messageId:string|null};
export type MailPlan={id:string;periodId:string;period:Period;jobs:MailJob[]};
export const validMail=(email:string)=>email.length<=254&&/^[^\s<>(),;:\\"]+@[^\s<>(),;:\\"]+\.[^\s<>(),;:\\"]+$/.test(email);
export function mailBatchId(p:Period){return p.snapshot?`${p.id}:${p.snapshot.closedAt}`:'';}
export function planMail(p:Period,employees:Employee[]):MailPlan{
 if(p.status!=='cerrada'||!p.snapshot)throw new Error('Cierra la quincena antes de enviar sus desprendibles.');
 const batchId=mailBatchId(p),people=[...new Map(p.snapshot.rows.map(r=>[r.employeeId,r])).values()];
 return {id:batchId,periodId:p.id,period:structuredClone(p),jobs:people.map(r=>{const contact=employees.find(e=>e.id===r.employeeId)??p.snapshot!.employees.find(e=>e.id===r.employeeId);const email=(contact?.email||'').trim();return {id:batchId+':'+r.employeeId,batchId,employeeId:r.employeeId,name:r.name,email,status:validMail(email)?'pending':'missing',attempts:0,error:validMail(email)?'':'Agrega un correo válido en Personal.',sentAt:null,messageId:null};})};
}
export function base64(bytes:Uint8Array){let s='';for(let i=0;i<bytes.length;i+=4096)s+=String.fromCharCode(...bytes.subarray(i,i+4096));return btoa(s);}
export const base64Url=(b:Uint8Array)=>base64(b).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
export const fromBase64Url=(s:string)=>Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
const utf8=(s:string)=>new TextEncoder().encode(s);
const lines=(s:string)=>s.match(/.{1,76}/g)?.join('\r\n')||'';
export function mailMessage(p:Period,job:MailJob,pdf:Uint8Array){
 if(!validMail(job.email))throw new Error('Correo inválido.');
 const correction=!!p.revisions?.length,subject=`${correction?'Corrección · ':''}Desprendible de nómina · ${periodLabel(p)}`,boundary='jac-'+crypto.randomUUID();
 const body=`Hola ${job.name},\n\nAdjuntamos tu desprendible de nómina correspondiente a ${periodLabel(p)}.${correction?' Este documento reemplaza la versión anterior de este cierre.':''}\n\nSi tienes alguna consulta, puedes responder a este correo.\n\nJAC MUSIC ESTUDIOS SAS`;
 const message=[`From: JAC Music <${GMAIL_SENDER}>`,`To: ${job.email}`,`Subject: =?UTF-8?B?${base64(utf8(subject))}?=`,`MIME-Version: 1.0`,`Content-Type: multipart/mixed; boundary="${boundary}"`,'',`--${boundary}`,'Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',lines(base64(utf8(body))),`--${boundary}`,'Content-Type: application/pdf',`Content-Disposition: attachment; filename="desprendible-${p.start}.pdf"`,'Content-Transfer-Encoding: base64','',lines(base64(pdf)),`--${boundary}--`,''].join('\r\n');return base64Url(utf8(message));
}
export async function encryptMail(value:unknown,secret:string){const key=await crypto.subtle.importKey('raw',fromBase64Url(secret),{name:'AES-GCM'},false,['encrypt']),iv=crypto.getRandomValues(new Uint8Array(12)),data=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,utf8(JSON.stringify(value)));return base64Url(iv)+'.'+base64Url(new Uint8Array(data));}
export async function decryptMail<T>(value:string,secret:string):Promise<T>{const [iv,data]=value.split('.');const key=await crypto.subtle.importKey('raw',fromBase64Url(secret),{name:'AES-GCM'},false,['decrypt']);return JSON.parse(new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:fromBase64Url(iv)},key,fromBase64Url(data)))) as T;}
