import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {canCrm,CrmFailure} from '@/lib/crm-core';
import {crmGuard} from '@/lib/crm-access';
import {guardActive} from '@/lib/crm-store';
import {ProspectFailure} from '@/lib/crm-prospects-core';
import {ProspectMailFailure} from '@/lib/crm-prospects-mail';
import {prospectsFeed,prospectDetail,prospectBatch,prospectBrochure,saveProspect,previewProspects,queueProspectBatch,cancelProspectBatch,checkProspectReplies,markProspectReply} from '@/lib/crm-prospects-store';
import {startProspectMailOauth} from '@/lib/crm-prospects-oauth';

export const dynamic='force-dynamic';
const reply=(data:unknown,status=200,cookie?:string)=>Response.json(data,{status,headers:{...payrollHeaders,...(cookie?{'Set-Cookie':cookie}:{})}});
const failure=(error:unknown)=>{
 const known=error instanceof CrmFailure||error instanceof ProspectFailure||error instanceof ProspectMailFailure;
 const status=error instanceof ProspectMailFailure?[401,403].includes(error.status)?409:error.status>=500?503:error.status>=400?error.status:502:error instanceof CrmFailure||error instanceof ProspectFailure?error.status:502;
 return reply({error:known?error.message:'No pudimos completar la operación. Conserva tu propuesta y vuelve a consultar antes de repetir el envío.'},status);
};

async function readBody(req:Request):Promise<{action:string;record:unknown}>{
 if(!/^application\/json(?:\s*;|$)/i.test(req.headers.get('content-type')??''))throw new CrmFailure('La solicitud debe ser JSON.');
 const limit=64*1024;
 if(Number(req.headers.get('content-length')??0)>limit)throw new CrmFailure('La propuesta excede el tamaño permitido.',413);
 if(!req.body)throw new CrmFailure('La solicitud no es válida.');
 const reader=req.body.getReader(),parts:Uint8Array[]=[];let size=0;
 for(;;){const chunk=await reader.read();if(chunk.done)break;size+=chunk.value.length;if(size>limit){await reader.cancel();throw new CrmFailure('La propuesta excede el tamaño permitido.',413);}parts.push(chunk.value);}
 const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
 let value:unknown;try{value=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new CrmFailure('La solicitud no es válida.');}
 if(!value||typeof value!=='object'||Array.isArray(value)||!('action' in value)||typeof value.action!=='string')throw new CrmFailure('Selecciona una operación válida.');
 return {action:value.action,record:'record' in value?value.record:undefined};
}

export async function GET(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);
 if(!canCrm(user))return reply({error:'El CRM está disponible solo para administradores.'},403);
 try{
  const guard=crmGuard(req,user),query=new URL(req.url).searchParams;
  if(query.has('brochure')){
   const file=await prospectBrochure(user,query.get('brochure')??'',guard);
   if(!await guardActive(guard)){await file.object.body.cancel().catch(()=>{});throw new CrmFailure('Tu sesión cambió.',403);}
   return new Response(file.object.body,{headers:{...payrollHeaders,'Content-Type':'application/pdf','Content-Length':String(file.size),'Content-Disposition':`${query.has('download')?'attachment':'inline'}; filename="Brochure-Jhon-Alex-Castano.pdf"`,'Cross-Origin-Resource-Policy':'same-origin'}});
  }
  const data=query.has('id')?await prospectDetail(user,query.get('id')??'',guard):query.has('batch')?await prospectBatch(user,query.get('batch')??'',guard):await prospectsFeed(user,query,guard);
  if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
  return reply(data);
 }catch(error){return failure(error);}
}

export async function POST(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);
 if(!canCrm(user))return reply({error:'El CRM está disponible solo para administradores.'},403);
 if(req.headers.get('origin')!==new URL(req.url).origin||req.headers.get('sec-fetch-site')==='cross-site')return reply({error:'Origen no autorizado.'},403);
 try{
  const {action,record}=await readBody(req),guard=crmGuard(req,user);
  if(!await guardActive(guard))throw new CrmFailure('Tu sesión cambió.',403);
  if(action==='connectTracking'){
   const start=await startProspectMailOauth(user,req.headers.get('cookie')??'');
   return reply({url:start.url},200,start.cookie);
  }
  const actions:Record<string,()=>Promise<unknown>>={
   saveProspect:()=>saveProspect(user,record,guard),
   preview:()=>previewProspects(user,record,guard),
   queueBatch:()=>queueProspectBatch(user,record,guard),
   cancelBatch:()=>cancelProspectBatch(user,record,guard),
   checkReplies:()=>checkProspectReplies(user,record,guard),
   markReply:()=>markProspectReply(user,record,guard),
  };
  if(!Object.hasOwn(actions,action))throw new CrmFailure('Operación de prospectos no disponible.');
  return reply(await actions[action]());
 }catch(error){return failure(error);}
}
