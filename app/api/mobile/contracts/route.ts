import {authenticatedSession} from '@/lib/payroll-auth-store';
import {payrollHeaders} from '@/lib/payroll-access';
import {canCrm} from '@/lib/crm-core';
import {contractInput,contractFilename} from '@/lib/contract-core';
import {contractPdf} from '@/lib/contract-pdf';

export const dynamic='force-dynamic';
const headers={...payrollHeaders,Vary:'Authorization'};
const failure=(error:string,status:number)=>Response.json({error},{status,headers});

export async function POST(req:Request){
 // This native endpoint never falls back to browser cookies or legacy access.
 const token=/^Bearer ([A-Za-z0-9_-]{43})$/i.exec(req.headers.get('authorization')||'')?.[1];
 if(!token)return failure('Inicia sesión con tu cuenta de JAC.',401);
 try{
  const user=await authenticatedSession(token);
  if(!user||user.legacy)return failure('Inicia sesión con tu cuenta de JAC.',401);
  if(!canCrm(user))return failure('Los contratos están disponibles solo para administradores del CRM.',403);
  if(!/^application\/json(?:\s*;|$)/i.test(req.headers.get('content-type')||''))return failure('Formulario no válido.',415);
  // Stream size is checked independently from an untrusted Content-Length.
  const reader=req.body?.getReader();if(!reader)return failure('Completa el formulario.',400);
  const chunks:Uint8Array[]=[];let size=0;
  while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>8192){await reader.cancel();return failure('El formulario es demasiado extenso.',413);}chunks.push(value);}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  let raw:unknown;try{raw=JSON.parse(new TextDecoder().decode(bytes));}catch{return failure('Formulario no válido.',400);}
  const parsed=contractInput.safeParse(raw);if(!parsed.success)return failure(parsed.error.issues[0]?.message||'Revisa el formulario.',400);
  const current=async()=>{const actor=await authenticatedSession(token);return !!actor&&canCrm(actor)&&JSON.stringify(actor)===JSON.stringify(user);};
  if(!await current())return failure('Tu sesión o tus permisos cambiaron. Inicia sesión de nuevo.',403);
  let pdf:Uint8Array;try{pdf=await contractPdf(parsed.data);}catch{return failure('Los datos son demasiado extensos para esta plantilla de cuatro páginas. Abrevia la empresa, representante o lugar sin omitir su identidad.',400);}
  // Password, version, session, administrator and section changes revoke output.
  if(!await current())return failure('Tu sesión o tus permisos cambiaron. Inicia sesión de nuevo.',403);
  const filename=contractFilename(parsed.data),fallback=filename.normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  return new Response(pdf as BodyInit,{headers:{...headers,'Content-Type':'application/pdf','Content-Disposition':`attachment; filename="${fallback}"; filename*=UTF-8''${encodeURIComponent(filename)}`,'Content-Security-Policy':"default-src 'none'; sandbox"}});
 }catch{return failure('No pudimos generar el contrato. Conserva el formulario e inténtalo de nuevo.',503);}
}
