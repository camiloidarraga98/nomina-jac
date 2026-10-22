import {database} from '@/db/raw';
import {gmailAccessToken,mailConnection,mailKey} from './payroll-mail';
import {GMAIL_SENDER,base64,decryptMail,encryptMail,validMail} from './payroll-mail-core';
import {CrmFailure} from './crm-core';
import {guardActive} from './crm-store';
import type {CrmGuard} from './crm-access';

export const PROSPECT_METADATA_SCOPE='https://www.googleapis.com/auth/gmail.metadata';
export const PROSPECT_SEND_SCOPE='https://www.googleapis.com/auth/gmail.send';
export type ProspectMailCredentials={clientId:string;clientSecret:string;refreshToken:string;scopes:string[]};
export type ProspectMailConfig={id:string;credentials:string;connected_email:string;enabled:number;version:number;error:string;updated_at:string};
export type ProspectEmailSnapshot={id:string;email:string;subject:string;body:string;rfcMessageId:string};
export type ProspectEmailAttachment={body:ReadableStream<Uint8Array>;filename:string;size:number};
export class ProspectMailFailure extends Error {
 constructor(message:string,readonly status=502,readonly uncertain=false){super(message);}
}
const encoder=new TextEncoder(),stamp=()=>new Date().toISOString();
export const prospectMailConfig=()=>database().prepare('SELECT * FROM jac_crm_prospect_mail WHERE id=?').bind('jac').first<ProspectMailConfig>();
const supported=(credentials:ProspectMailCredentials)=>!!credentials.refreshToken&&Array.isArray(credentials.scopes)&&credentials.scopes.includes(PROSPECT_SEND_SCOPE)&&credentials.scopes.includes(PROSPECT_METADATA_SCOPE);
async function ownConnection(){
 const row=await prospectMailConfig();if(!row?.enabled||row.connected_email!==GMAIL_SENDER||!row.credentials)return null;
 const credentials=await decryptMail<ProspectMailCredentials>(row.credentials,mailKey());return supported(credentials)?{row,credentials}:null;
}
export async function prospectMailConnection(){
 const shared=await mailConnection();let own:Awaited<ReturnType<typeof ownConnection>>=null,error='';
 try{own=await ownConnection();}catch{error='Vuelve a autorizar el seguimiento de respuestas.';}
 return {sender:GMAIL_SENDER,connected:!!own||shared.connected,trackingConnected:!!own,error:error||own?.row.error||shared.error||''};
}
export async function ensureProspectMailConfig(guard:CrmGuard){
 guard.bindings=[guard.bindings[0],guard.bindings[1],stamp()];
 await database().prepare(`INSERT INTO jac_crm_prospect_mail(id,updated_at) SELECT ?,? WHERE ${guard.sql} ON CONFLICT(id) DO NOTHING`).bind('jac',stamp(),...guard.bindings).run();
 if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
 const row=await prospectMailConfig();if(!row)throw new CrmFailure('No pudimos preparar la conexión de seguimiento.',503);return row;
}
export async function storeProspectMailCredentials(credentials:ProspectMailCredentials,revision:number,guard:CrmGuard){
 if(!supported(credentials))throw new CrmFailure('Google no concedió los permisos necesarios.');
 const encrypted=await encryptMail(credentials,mailKey());guard.bindings=[guard.bindings[0],guard.bindings[1],stamp()];
 const saved=await database().prepare(`UPDATE jac_crm_prospect_mail SET credentials=?,connected_email=?,enabled=1,error='',version=version+1,updated_at=? WHERE id='jac' AND version=? AND ${guard.sql}`).bind(encrypted,GMAIL_SENDER,stamp(),revision,...guard.bindings).run();
 if(saved.meta.changes!==1)throw new CrmFailure('La conexión o la sesión cambió. Vuelve a autorizar el seguimiento.',409);
}
export async function disconnectProspectMail(revision:number,guard:CrmGuard){
 guard.bindings=[guard.bindings[0],guard.bindings[1],stamp()];
 const changed=await database().prepare(`UPDATE jac_crm_prospect_mail SET credentials='',connected_email='',enabled=0,error='',version=version+1,updated_at=? WHERE id='jac' AND version=? AND ${guard.sql}`).bind(stamp(),revision,...guard.bindings).run();
 if(changed.meta.changes!==1)throw new CrmFailure('La conexión o la sesión cambió. Actualiza el panel.',409);
 // Never revoke the Google grant: the same account also authorizes payroll and Agenda.
}
async function authorization(tracking=false){
 let own:Awaited<ReturnType<typeof ownConnection>>;
 try{own=await ownConnection();}catch{throw new ProspectMailFailure('Vuelve a autorizar el seguimiento de respuestas.',403);}
 if(own){
  let result:Record<string,unknown>;
  try{const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:own.credentials.clientId,client_secret:own.credentials.clientSecret,refresh_token:own.credentials.refreshToken,grant_type:'refresh_token'}),signal:AbortSignal.timeout(15000)});if(!response.ok){await response.body?.cancel().catch(()=>{});throw new Error('Google rejected the tracking grant');}result=await boundedJSON(response);}catch{throw new ProspectMailFailure('Google requiere que vuelvas a conectar el seguimiento.',403);}
  if(typeof result.access_token!=='string')throw new ProspectMailFailure('Google no confirmó la autorización de correo.',403);
  const expected=own.row;
  return {token:result.access_token,check:async()=>{const live=await prospectMailConfig();return !!live?.enabled&&live.version===expected.version&&live.credentials===expected.credentials&&live.connected_email===GMAIL_SENDER;}};
 }
 if(tracking)throw new ProspectMailFailure('Autoriza el seguimiento de respuestas antes de consultarlas.',403);
 const current=await database().prepare('SELECT credentials,connected_email,enabled FROM payroll_gmail WHERE id=?').bind('jac').first<{credentials:string;connected_email:string;enabled:number}>();
 let token:string;try{token=await gmailAccessToken();}catch{throw new ProspectMailFailure('Conecta Gmail en JAC para enviar las propuestas.',403);}
 return {token,check:async()=>{const live=await database().prepare('SELECT credentials,connected_email,enabled FROM payroll_gmail WHERE id=?').bind('jac').first<{credentials:string;connected_email:string;enabled:number}>();return !!current&&!!live?.enabled&&live.credentials===current.credentials&&live.connected_email===GMAIL_SENDER;}};
}
const escapeHTML=(value:string)=>value.replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]!));
const encodedText=(text:string)=>base64(encoder.encode(text)).match(/.{1,76}/g)?.join('\r\n')||'';
function messageParts(snapshot:ProspectEmailSnapshot,filename:string){
 if(!validMail(snapshot.email)||!snapshot.id||snapshot.id.length>180||!snapshot.subject.trim()||snapshot.subject.length>500||/[\r\n\0]/.test(snapshot.subject)||!snapshot.body.trim()||snapshot.body.length>20000||!/^<[A-Za-z0-9._%+-]{1,180}@[A-Za-z0-9.-]{1,180}>$/.test(snapshot.rfcMessageId))throw new ProspectMailFailure('Revisa el destinatario y el contenido de la propuesta.',400);
 const safeName=Array.from(filename.replace(/[\x00-\x1f\x7f/\\]/g,'_')).slice(0,120).join('')||'Brochure-Jhon-Alex-Castano.pdf';
 const fallback=safeName.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^\x20-\x7e]|["\\]/g,'_');
 const mixed='jac-prospect-'+crypto.randomUUID(),alternative='jac-text-'+crypto.randomUUID();
 const html='<html><body style="font-family:Arial,sans-serif;line-height:1.6;color:#173348">'+snapshot.body.split(/\n\s*\n/).map(paragraph=>'<p>'+escapeHTML(paragraph).replace(/\n/g,'<br>').replace(/https:\/\/wa\.me\/573125064091(?:\?text=[^\s<]*)?/g,url=>'<a href="'+url+'" style="color:#0077b6;font-weight:bold">Escríbenos por WhatsApp</a>')+'</p>').join('')+'</body></html>';
 const start=[`From: =?UTF-8?B?${base64(encoder.encode('Equipo de management de Jhon Alex Castaño'))}?= <${GMAIL_SENDER}>`,`To: ${snapshot.email}`,`Subject: =?UTF-8?B?${base64(encoder.encode(snapshot.subject))}?=`,`Message-ID: ${snapshot.rfcMessageId}`,`Date: ${new Date().toUTCString()}`,'MIME-Version: 1.0',`Content-Type: multipart/mixed; boundary="${mixed}"`,'',`--${mixed}`,`Content-Type: multipart/alternative; boundary="${alternative}"`,'',`--${alternative}`,'Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',encodedText(snapshot.body),`--${alternative}`,'Content-Type: text/html; charset=UTF-8','Content-Transfer-Encoding: base64','',encodedText(html),`--${alternative}--`,`--${mixed}`,'Content-Type: application/pdf',`Content-Disposition: attachment; filename="${fallback}"; filename*=UTF-8''${encodeURIComponent(safeName)}`,'Content-Transfer-Encoding: base64','',''].join('\r\n');
 return {start:encoder.encode(start),end:encoder.encode(`--${mixed}--\r\n`)};
}
// Only one small base64 block and at most56 carry bytes are allocated per pull.
// The PDF and a second base64 JSON envelope are never buffered in full.
async function* pdfChunks(reader:ReadableStreamDefaultReader<Uint8Array>,initial:Uint8Array[],expected:number){
 let size=0,carry=new Uint8Array(0);
 async function* encode(chunk:Uint8Array){
  size+=chunk.length;if(size>expected)throw new Error('Attachment length changed');let offset=0;
  if(carry.length){const count=Math.min(57-carry.length,chunk.length),joined=new Uint8Array(carry.length+count);joined.set(carry);joined.set(chunk.subarray(0,count),carry.length);offset=count;carry=joined;if(carry.length===57){yield encoder.encode(base64(carry)+'\r\n');carry=new Uint8Array(0);}}
  const full=Math.floor((chunk.length-offset)/57)*57;
  for(let done=0;done<full;done+=57*256){const block=chunk.subarray(offset+done,offset+Math.min(full,done+57*256));yield encoder.encode((base64(block).match(/.{76}/g)||[]).join('\r\n')+'\r\n');}
  offset+=full;if(offset<chunk.length)carry=chunk.slice(offset);
 }
 for(const chunk of initial)yield* encode(chunk);
 for(;;){const next=await reader.read();if(next.done)break;yield* encode(next.value);}
 if(size!==expected)throw new Error('Attachment length changed');if(carry.length)yield encoder.encode(base64(carry)+'\r\n');
}
async function boundedJSON(response:Response,limit=64*1024){
 if(!response.body)throw new Error('Missing provider response');const reader=response.body.getReader(),parts:Uint8Array[]=[];let length=0;
 try{for(;;){const next=await reader.read();if(next.done)break;length+=next.value.length;if(length>limit)throw new Error('Provider response too large');parts.push(next.value);}}catch(error){await reader.cancel().catch(()=>{});throw error;}
 const bytes=new Uint8Array(length);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}return JSON.parse(new TextDecoder().decode(bytes)) as Record<string,unknown>;
}
export async function sendProspectEmail(snapshot:ProspectEmailSnapshot,attachment:ProspectEmailAttachment,beforeSend?:()=>Promise<void>):Promise<{messageId:string;threadId:string}>{
 let requested=false,reader:ReadableStreamDefaultReader<Uint8Array>|null=null,pump:Promise<void>|null=null;const abort=new AbortController();let timer:ReturnType<typeof setTimeout>|undefined;
 try{
  if(!Number.isSafeInteger(attachment.size)||attachment.size<5||attachment.size>10*1024*1024)throw new ProspectMailFailure('El brochure PDF debe pesar como máximo 10 MB.',400);
  const parts=messageParts(snapshot,attachment.filename),auth=await authorization();reader=attachment.body.getReader();const initial:Uint8Array[]=[];let prefix=0;
  while(prefix<5){const chunk=await reader.read();if(chunk.done)throw new ProspectMailFailure('No pudimos leer el brochure adjunto.',400);initial.push(chunk.value);prefix+=chunk.value.length;if(prefix>attachment.size)throw new ProspectMailFailure('El brochure adjunto cambió.',400);}
  const signature=new Uint8Array(5);let cursor=0;for(const chunk of initial){const taken=Math.min(5-cursor,chunk.length);signature.set(chunk.subarray(0,taken),cursor);cursor+=taken;if(cursor===5)break;}
  if(new TextDecoder().decode(signature)!=='%PDF-')throw new ProspectMailFailure('El brochure no es un PDF válido.',400);
  const content=(async function*(){yield parts.start;yield* pdfChunks(reader!,initial,attachment.size);yield parts.end;})();
  const stream=new ReadableStream<Uint8Array>({async pull(controller){try{const next=await content.next();if(next.done)controller.close();else controller.enqueue(next.value);}catch(error){controller.error(error);}},async cancel(){await reader?.cancel().catch(()=>{});await content.return(undefined);}});
  const length=parts.start.length+4*Math.ceil(attachment.size/3)+2*Math.ceil(attachment.size/57)+parts.end.length;
  const fixed=typeof FixedLengthStream==='function'?new FixedLengthStream(length):null;
  const payload=fixed?(pump=stream.pipeTo(fixed.writable,{signal:abort.signal}),pump.catch(()=>{}),fixed.readable):stream;
  if(beforeSend)await beforeSend();
  if(!await auth.check())throw new ProspectMailFailure('La conexión de correo cambió. Revisa el panel antes de enviar.',403);
  timer=setTimeout(()=>abort.abort(),45000);requested=true;
  const response=await fetch('https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/send?uploadType=media',{method:'POST',redirect:'manual',headers:{Authorization:'Bearer '+auth.token,'Content-Type':'message/rfc822','Content-Length':String(length)},body:payload,signal:abort.signal});
  if(!response.ok){await response.body?.cancel().catch(()=>{});throw new ProspectMailFailure(response.status===429?'Google limitó los envíos. Revisa el lote más tarde.':response.status>=500?'Google no confirmó el envío. Revisa Enviados antes de repetirlo.':'Google rechazó el envío. Revisa Gmail y el destinatario.',response.status,response.status>=500||response.status>=300&&response.status<400);}
  const data=await boundedJSON(response);
  if(typeof data.id!=='string'||!data.id||data.id.length>200||typeof data.threadId!=='string'||!data.threadId||data.threadId.length>200)throw new Error('Unconfirmed delivery');
  return {messageId:data.id,threadId:data.threadId};
 }catch(error){if(error instanceof ProspectMailFailure)throw error;throw new ProspectMailFailure(requested?'No se confirmó el envío. Revisa Enviados antes de repetirlo.':'No pudimos preparar la propuesta. Revisa el correo y el brochure.',502,requested);}
 finally{if(timer)clearTimeout(timer);abort.abort();if(reader)await reader.cancel().catch(()=>{});else await attachment.body.cancel().catch(()=>{});if(pump)await pump.catch(()=>{});}
}
type Header={name?:string;value?:string};
type MetadataMessage={id?:string;internalDate?:string;labelIds?:string[];payload?:{headers?:Header[]}};
const header=(message:MetadataMessage,name:string)=>{const values=message.payload?.headers;if(!Array.isArray(values))return '';const value=values.find(value=>typeof value?.name==='string'&&value.name.toLowerCase()===name)?.value;return typeof value==='string'?value.slice(0,2000):'';};
const addresses=(value:string)=>(value.match(/[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g)??[]).map(address=>address.toLowerCase());
export async function checkProspectReplies(snapshot:{threadId:string;messageId:string;email:string;sentAt:string;rfcMessageId?:string}):Promise<{status:'none'|'received'|'automatic'|'bounced';repliedAt:string}>{
 if(!/^[A-Za-z0-9_-]{1,200}$/.test(snapshot.threadId)||!snapshot.messageId||!validMail(snapshot.email)||!Number.isFinite(Date.parse(snapshot.sentAt)))throw new ProspectMailFailure('El hilo de la propuesta no está disponible.',400);
 const auth=await authorization(true);if(!await auth.check())throw new ProspectMailFailure('La conexión de seguimiento cambió.',403);
 const url=new URL('https://gmail.googleapis.com/gmail/v1/users/me/threads/'+encodeURIComponent(snapshot.threadId));url.searchParams.set('format','metadata');url.searchParams.set('fields','id,messages(id,internalDate,labelIds,payload(headers))');
 for(const name of ['From','To','Subject','Date','Auto-Submitted','Precedence','Content-Type','In-Reply-To','References','Return-Path','X-Autoreply','X-Autorespond'])url.searchParams.append('metadataHeaders',name);
 let response:Response;try{response=await fetch(url,{headers:{Authorization:'Bearer '+auth.token},redirect:'manual',signal:AbortSignal.timeout(15000)});}catch{throw new ProspectMailFailure('No pudimos consultar las respuestas. Inténtalo más tarde.');}
 if(!response.ok){await response.body?.cancel().catch(()=>{});throw new ProspectMailFailure('Google no permitió consultar este hilo. Revisa el seguimiento.',response.status);}
 let data:Record<string,unknown>;try{data=await boundedJSON(response,512*1024);}catch{throw new ProspectMailFailure('Google no confirmó el estado de este hilo.');}
 if(!await auth.check())throw new ProspectMailFailure('La conexión de seguimiento cambió.',403);
 if(data.id!==snapshot.threadId||!Array.isArray(data.messages))throw new ProspectMailFailure('Google no confirmó el hilo solicitado.');
 const messages=data.messages.filter(message=>message&&typeof message==='object') as MetadataMessage[];
 const original=messages.find(message=>message.id===snapshot.messageId),after=original&&Number.isFinite(Number(original.internalDate))?Number(original.internalDate):Date.parse(snapshot.sentAt);
 const replies:{status:'received'|'automatic'|'bounced';repliedAt:string}[]=[];
 for(const message of messages){
  const date=Number(message.internalDate),from=addresses(header(message,'from'));
  if(message.id===snapshot.messageId||message.labelIds?.includes('SENT')||!Number.isFinite(date)||date<after||!from.length||from.includes(GMAIL_SENDER)||!addresses(header(message,'to')).includes(GMAIL_SENDER))continue;
  const automatic=header(message,'auto-submitted'),subject=header(message,'subject'),content=header(message,'content-type');
  const bounced=from.some(address=>/^(?:mailer-daemon|postmaster)@/i.test(address))||/delivery-status/i.test(content)||/(?:undeliverable|delivery (?:status notification|failure)|failure notice|no se pudo entregar|mensaje no entregado)/i.test(subject);
  const auto=!!automatic&&!/^no$/i.test(automatic.trim())||/^(?:bulk|list|junk)$/i.test(header(message,'precedence').trim())||!!header(message,'x-autoreply')||!!header(message,'x-autorespond')||/(?:automatic reply|auto.?reply|respuesta autom[aá]tica|fuera de la oficina|out of office)/i.test(subject);
  const referenced=snapshot.rfcMessageId&&[header(message,'references'),header(message,'in-reply-to')].some(value=>value.split(/\s+/).includes(snapshot.rfcMessageId!));
  if(!bounced&&!from.includes(snapshot.email.toLowerCase())&&!referenced)continue;
  replies.push({status:bounced?'bounced':auto?'automatic':'received',repliedAt:new Date(date).toISOString()});
 }
 replies.sort((a,b)=>b.repliedAt.localeCompare(a.repliedAt));return replies.find(reply=>reply.status==='received')??replies[0]??{status:'none',repliedAt:''};
}
