import {database} from '@/db/raw';
import {env} from 'cloudflare:workers';
import {z} from 'zod';
import {canCrm,CrmFailure} from './crm-core';
import {guardActive} from './crm-store';
import type {CrmGuard} from './crm-access';
import type {AccessUser} from './payroll-permissions';
import {contractInput,contractFilename} from './contract-core';
import {contractPdf} from './contract-pdf';
const uuid=z.string().uuid();
export const contractSaveInput=z.object({action:z.literal('save'),id:uuid,showId:uuid.nullable(),input:contractInput}).strict();
const linkInput=z.object({action:z.literal('link'),id:uuid,showId:uuid.nullable(),version:z.number().int().positive()}).strict();
type Row={id:string;actor_id:string;request_hash:string;filename:string;company:string;municipality:string;event_date:string;price:number;show_id:string|null;state:string;file_key:string;write_nonce:string;lease_until:string;version:number;created_at:string;show_title?:string|null;show_date?:string|null};
async function authorize(u:AccessUser,g:CrmGuard){
 // crmStoredGuard binds session, user and clock. Renew the clock at every
 // boundary, including after a slow R2 write; expiry must not use request time.
 g.bindings=[g.bindings[0],g.bindings[1],new Date().toISOString()];
 if(!canCrm(u)||!await guardActive(g))throw new CrmFailure('Tu sesión o tus permisos cambiaron.',403);}
const showGate=(id:string|null)=>id===null?'1':"EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND source_state NOT IN ('deleted','deleting'))";
const showBindings=(id:string|null)=>id===null?[]:[id];
const publicRow=(r:Row)=>({id:r.id,filename:r.filename,company:r.company,municipality:r.municipality,eventDate:r.event_date,price:r.price,showId:r.show_id,showTitle:r.show_title||'',showDate:r.show_date||'',version:r.version,createdAt:r.created_at});
export async function contractArchive(u:AccessUser,g:CrmGuard,url:URL){
 await authorize(u,g);const db=database(),offset=Number(url.searchParams.get('offset')||0);if(!Number.isSafeInteger(offset)||offset<0||offset>100000)throw new CrmFailure('Página no válida.');
 if(url.searchParams.get('view')==='shows'){
  const q=(url.searchParams.get('q')||'').trim().slice(0,120);
  const rows=await db.prepare(`SELECT id,title,show_date FROM jac_crm_shows WHERE source_state NOT IN ('deleted','deleting') AND (instr(lower(title),lower(?))>0 OR instr(show_date,?)>0) AND ${g.sql} ORDER BY show_date DESC,title,id LIMIT 101 OFFSET ?`).bind(q,q,...g.bindings,offset).all<{id:string;title:string;show_date:string}>();
  await authorize(u,g);return {shows:rows.results.slice(0,100).map(r=>({id:r.id,title:r.title,showDate:r.show_date})),next:rows.results.length>100?offset+100:null};
 }
 const rows=await db.prepare(`SELECT c.*,s.title AS show_title,s.show_date FROM jac_crm_contracts c LEFT JOIN jac_crm_shows s ON s.id=c.show_id AND s.source_state NOT IN ('deleted','deleting') WHERE c.state='ready' AND ${g.sql} ORDER BY c.created_at DESC,c.id DESC LIMIT 51 OFFSET ?`).bind(...g.bindings,offset).all<Row>();
 await authorize(u,g);return {contracts:rows.results.slice(0,50).map(publicRow),next:rows.results.length>50?offset+50:null};
}
export async function storedContract(u:AccessUser,g:CrmGuard,id:string){
 await authorize(u,g);if(!uuid.safeParse(id).success)throw new CrmFailure('Contrato no disponible.',404);
 const get=()=>database().prepare(`SELECT * FROM jac_crm_contracts WHERE id=? AND state='ready' AND ${g.sql}`).bind(id,...g.bindings).first<Row>();
 const row=await get();if(!row)throw new CrmFailure('Contrato no disponible.',404);
 const object=await env.BUCKET.get(row.file_key);await authorize(u,g);if(!object||!await get())throw new CrmFailure('Contrato no disponible.',404);
 return {object,filename:row.filename,id:row.id};
}
export async function linkContract(u:AccessUser,g:CrmGuard,raw:unknown){
 await authorize(u,g);const p=linkInput.safeParse(raw);if(!p.success)throw new CrmFailure('Selecciona un show válido.');const v=p.data;
 const result=await database().prepare(`UPDATE jac_crm_contracts SET show_id=?,version=version+1,updated_at=? WHERE id=? AND state='ready' AND version=? AND ${showGate(v.showId)} AND ${g.sql}`).bind(v.showId,new Date().toISOString(),v.id,v.version,...showBindings(v.showId),...g.bindings).run();
 await authorize(u,g);if(!result.meta.changes)throw new CrmFailure('El contrato o el show cambió. Actualiza el listado e inténtalo de nuevo.',409);return {ok:true};
}
export async function saveContract(u:AccessUser,g:CrmGuard,raw:unknown){
 await authorize(u,g);const p=contractSaveInput.safeParse(raw);if(!p.success)throw new CrmFailure(p.error.issues[0]?.message||'Revisa el formulario.');const v=p.data,db=database();
 const canonical=JSON.stringify({input:v.input,showId:v.showId});const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonical)))).map(n=>n.toString(16).padStart(2,'0')).join('');
 const get=()=>db.prepare('SELECT * FROM jac_crm_contracts WHERE id=?').bind(v.id).first<Row>();
 let prior=await get();if(prior&&(prior.actor_id!==u.id||prior.request_hash!==hash))throw new CrmFailure('Ese intento corresponde a otro contrato. Genera un contrato nuevo.',409);
 if(prior?.state==='ready')return storedContract(u,g,v.id);
 // Generate before reserving storage: invalid or oversized drafts leave no record.
 let pdf:Uint8Array;try{pdf=await contractPdf(v.input);}catch{throw new CrmFailure('Los datos son demasiado extensos para la plantilla. Abrevia los campos conservando su identidad.');}
 await authorize(u,g);const now=new Date().toISOString(),nonce=crypto.randomUUID(),key='crm/contracts/'+v.id+'/'+nonce+'.pdf',filename=contractFilename(v.input),lease=new Date(Date.now()+120000).toISOString();
 if(!prior){await db.prepare(`INSERT INTO jac_crm_contracts (id,actor_id,request_hash,input_json,filename,company,municipality,event_date,price,show_id,file_key,write_nonce,lease_until,created_at,updated_at) SELECT ?,?,?,?,?,?,?,?,?,?,?,?,?,?,? WHERE ${showGate(v.showId)} AND ${g.sql} ON CONFLICT(id) DO NOTHING`).bind(v.id,u.id,hash,JSON.stringify(v.input),filename,v.input.company,v.input.municipality,v.input.eventDate,v.input.price,v.showId,key,nonce,lease,now,now,...showBindings(v.showId),...g.bindings).run();}
 else {await db.prepare(`UPDATE jac_crm_contracts SET state='pending',write_nonce=?,file_key=?,lease_until=? WHERE id=? AND request_hash=? AND actor_id=? AND (state='failed' OR (state='pending' AND lease_until<?)) AND ${showGate(v.showId)} AND ${g.sql}`).bind(nonce,key,lease,v.id,hash,u.id,now,...showBindings(v.showId),...g.bindings).run();}
 prior=await get();await authorize(u,g);if(!prior)throw new CrmFailure('El show ya no está disponible.',409);
 if(prior.actor_id!==u.id||prior.request_hash!==hash)throw new CrmFailure('Ese intento corresponde a otro contrato.',409);
 if(prior.state==='ready')return storedContract(u,g,v.id);
 if(prior.write_nonce!==nonce)throw new CrmFailure('El contrato se está guardando. Reintenta en unos instantes.',409);
 try{
  await env.BUCKET.put(key,pdf,{httpMetadata:{contentType:'application/pdf'}});
  await authorize(u,g);
  const done=await db.prepare(`UPDATE jac_crm_contracts SET state='ready',updated_at=? WHERE id=? AND state='pending' AND write_nonce=? AND ${showGate(v.showId)} AND ${g.sql}`).bind(new Date().toISOString(),v.id,nonce,...showBindings(v.showId),...g.bindings).run();
  if(!done.meta.changes){await authorize(u,g);throw new CrmFailure('El show cambió. El contrato no se guardó.',409);}
 }catch(error){await db.prepare("UPDATE jac_crm_contracts SET state='failed' WHERE id=? AND state='pending' AND write_nonce=?").bind(v.id,nonce).run();await env.BUCKET.delete(key).catch(()=>{});throw error;}
 return storedContract(u,g,v.id);
}
export function archivedPdfResponse(file:{object:{body:ReadableStream};filename:string;id:string},headers:Record<string,string>,download=false){const fallback=file.filename.normalize('NFD').replace(/[\u0300-\u036f]/g,'');return new Response(file.object.body,{headers:{...headers,'Content-Type':'application/pdf','Content-Disposition':`${download?'attachment':'inline'}; filename="${fallback}"; filename*=UTF-8''${encodeURIComponent(file.filename)}`,'X-JAC-Contract-ID':file.id,'Content-Security-Policy':"default-src 'none'; sandbox"}});}
