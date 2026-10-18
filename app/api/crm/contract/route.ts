import {contractArchive,storedContract,saveContract,linkContract,deleteContract,archivedPdfResponse} from '@/lib/contract-archive';
import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {canCrm,CrmFailure} from '@/lib/crm-core';
import {crmGuard} from '@/lib/crm-access';
import {guardActive} from '@/lib/crm-store';
import {contractInput,contractFilename} from '@/lib/contract-core';
import {contractPdf} from '@/lib/contract-pdf';
export const dynamic='force-dynamic';
const failure=(error:string,status:number)=>Response.json({error},{status,headers:payrollHeaders});
export async function POST(req:Request){
 const u=await payrollUser();if(!u||u.legacy)return failure('Inicia sesión con tu cuenta de JAC.',401);if(!canCrm(u))return failure('Los contratos están disponibles solo para administradores del CRM.',403);
 if(req.headers.get('origin')!==new URL(req.url).origin)return failure('Origen no autorizado.',403);
 if(!req.headers.get('content-type')?.startsWith('application/json'))return failure('Formulario no válido.',415);
 try{
  const guard=crmGuard(req,u);if(!await guardActive(guard))return failure('Tu sesión cambió.',403);
  // Read a bounded stream; Content-Length alone is not trustworthy.
  const reader=req.body?.getReader();if(!reader)return failure('Completa el formulario.',400);const chunks:Uint8Array[]=[];let size=0;
  while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>8192){await reader.cancel();return failure('El formulario es demasiado extenso.',413);}chunks.push(value);}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  let raw:unknown;try{raw=JSON.parse(new TextDecoder().decode(bytes));}catch{return failure('Formulario no válido.',400);}
  if(raw&&typeof raw==='object'&&'action' in raw){if(raw.action==='delete')return Response.json(await deleteContract(u,guard,raw),{headers:payrollHeaders});if(raw.action==='link')return Response.json(await linkContract(u,guard,raw),{headers:payrollHeaders});return archivedPdfResponse(await saveContract(u,guard,raw),payrollHeaders,true);}
  const parsed=contractInput.safeParse(raw);if(!parsed.success)return failure(parsed.error.issues[0]?.message||'Revisa el formulario.',400);
  let pdf:Uint8Array;try{pdf=await contractPdf(parsed.data);}catch{return failure('Los datos son demasiado extensos para esta plantilla de cuatro páginas. Abrevia la empresa, representante o lugar sin omitir su identidad.',400);}
  if(!await guardActive(crmGuard(req,u)))return failure('Tu sesión o tus permisos cambiaron. Inicia sesión de nuevo.',403);
  const filename=contractFilename(parsed.data),fallback=filename.normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  return new Response(pdf as BodyInit,{headers:{...payrollHeaders,'Content-Type':'application/pdf','Content-Disposition':`attachment; filename="${fallback}"; filename*=UTF-8''${encodeURIComponent(filename)}`,'X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; sandbox"}});
 }catch(e){return failure(e instanceof CrmFailure?e.message:'No pudimos generar el contrato. Conserva el formulario e inténtalo de nuevo.',e instanceof CrmFailure?e.status:500);}
}

export async function GET(req:Request){
 const u=await payrollUser();if(!u||u.legacy)return failure('Inicia sesión con tu cuenta de JAC.',401);if(!canCrm(u))return failure('Solo administradores del CRM.',403);
 try{const g=crmGuard(req,u),url=new URL(req.url),id=url.searchParams.get('id');return id?archivedPdfResponse(await storedContract(u,g,id),payrollHeaders,url.searchParams.has('download')):Response.json(await contractArchive(u,g,url),{headers:payrollHeaders});}
 catch(e){return failure(e instanceof CrmFailure?e.message:'No pudimos consultar los contratos.',e instanceof CrmFailure?e.status:503);}
}
