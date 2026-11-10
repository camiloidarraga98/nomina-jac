import {database} from '@/db/raw';
import {env} from 'cloudflare:workers';
import {CrmFailure,canCrm,cents} from './crm-core';
import {guardActive} from './crm-store';
import type {CrmGuard} from './crm-access';
import type {AccessUser} from './payroll-permissions';
import {payrollHeaders} from './payroll-access';
import {matchReceiptPayments,receiptLookupSchema} from './reconciliation-receipt';
import {readReceipt,reserveReceiptReader,RECEIPT_OCR_MAX_BYTES} from './reconciliation-ocr';

const stamp=()=>new Date().toISOString();
const id=()=>crypto.randomUUID();
const text=(v:unknown,max=1000)=>typeof v==='string'?v.trim().slice(0,max):'';
function fail(message:string,status=400):never{throw new CrmFailure(message,status);}
const json=(value:unknown,status=200)=>Response.json(value,{status,headers:payrollHeaders});
const validDate=(v:unknown):v is string=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&!Number.isNaN(Date.parse(v))&&new Date(v+'T12:00:00Z').toISOString().slice(0,10)===v;
const defaults={status:'pending',showId:'',entrepreneur:'',payer:'',billingStatus:'unknown',nit:'',businessName:'',notes:''};
type Annotation=typeof defaults;
type Original={date:string;amount:number;description:string;reference:string;thirdParty:string;receipt:string;invoice:string;original:Record<string,unknown>;sourceRow:number;sheet:string;importName:string};
type PaymentRow={id:string;import_id:string;original:string;annotation:string;version:number;created_at:string;updated_at:string};
type ImportRow={id:string;name:string;hash:string;manifest_hash:string;count:number;completed:number;created_at:string};
type FileRow={id:string;payment_id:string;object_key:string;hash:string;name:string;type:string;size:number;state:string;created_at:string};
type Show={id:string;name:string;date:string;city:string;entrepreneur:string;source:'crm'|'reconciliation';existing?:boolean};
const fileInfo=(f:FileRow)=>({id:f.id,paymentId:f.payment_id,name:f.name,type:f.type,size:f.size,url:'/api/reconciliation/files/'+f.id,createdAt:f.created_at});
const unpack=(p:PaymentRow)=>({...JSON.parse(p.original) as Original,...JSON.parse(p.annotation) as Annotation,id:p.id,version:p.version,createdAt:p.created_at,updatedAt:p.updated_at,attachments:[] as ReturnType<typeof fileInfo>[]});
const digest=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes as BufferSource))).map(n=>n.toString(16).padStart(2,'0')).join('');
// Stable across object key ordering and file renaming, while retaining every source value.
const canonical=(value:unknown):string=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical((value as Record<string,unknown>)[key])).join(',')+'}':JSON.stringify(value);
function originalIdentity(original:Original){const {importName,...facts}=original;void importName;return canonical(facts);}

async function bounded(req:Request,max:number){
 if(Number(req.headers.get('content-length'))>max)fail('El archivo tiene demasiados datos.',413);
 const reader=req.body?.getReader();if(!reader)fail('Faltan los datos de la solicitud.');
 const chunks:Uint8Array[]=[];let length=0;
 while(true){const {done,value}=await reader.read();if(done)break;length+=value.byteLength;if(length>max){await reader.cancel();fail('El archivo tiene demasiados datos.',413);}chunks.push(value);}
 const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return bytes;
}
async function body(req:Request){
 if(!req.headers.get('content-type')?.startsWith('application/json'))fail('Envía un formulario JSON válido.',415);
 const bytes=await bounded(req,12*1024*1024);let value:unknown;
 try{value=JSON.parse(new TextDecoder().decode(bytes));}catch{fail('Los datos enviados no son válidos.');}
 if(!value||typeof value!=='object'||Array.isArray(value))fail('Los datos enviados no son válidos.');
 return value as Record<string,unknown>;
}

async function receiptUpload(req:Request,max=20*1024*1024){
 if(!req.headers.get('content-type')?.startsWith('multipart/form-data'))fail('Selecciona un archivo.',415);
 const raw=await bounded(req,max+1024*1024);let form:FormData;
 try{form=await new Request(req.url,{method:'POST',headers:{'Content-Type':req.headers.get('content-type')!},body:raw as BodyInit}).formData();}catch{fail('No se pudo leer el soporte.');}
 const upload=form.get('file');if(!upload||typeof upload==='string')fail('Selecciona un archivo.');
 if(upload.size===0||upload.size>max)fail(`El comprobante debe tener contenido y pesar máximo ${max/1024/1024} MB.`,413);
 const bytes=new Uint8Array(await upload.arrayBuffer());let type='';
 if(bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff)type='image/jpeg';
 else if(bytes[0]===0x89&&String.fromCharCode(...bytes.slice(1,4))==='PNG')type='image/png';
 else if(new TextDecoder().decode(bytes.slice(0,5))==='%PDF-')type='application/pdf';
 else if(new TextDecoder().decode(bytes.slice(0,4))==='RIFF'&&new TextDecoder().decode(bytes.slice(8,12))==='WEBP')type='image/webp';
 if(!type)fail('Adjunta una imagen JPG, PNG, WebP o un PDF.');
 return {form,upload,bytes,type,hash:await digest(bytes)};
}

export async function reconciliationRequest(req:Request,user:AccessUser,g:CrmGuard){
 const db=database();
 // The current JAC cookie session and CRM permission are checked both in SQL
 // and after asynchronous boundaries. No Sites identity headers are trusted.
 async function authorize(){g.bindings=[g.bindings[0],g.bindings[1],stamp()];if(!canCrm(user)||!await guardActive(g))fail('Tu sesión o tus permisos cambiaron. Inicia sesión de nuevo.',403);}
 const prepared=(sql:string,args:(string|number)[]=[])=>db.prepare(sql).bind(...args,...g.bindings);
 async function payment(paymentId:string){
  const p=await prepared(`SELECT * FROM jac_reconciliation_payments WHERE id=? AND ${g.sql}`,[paymentId]).first<PaymentRow>();
  await authorize();if(!p)fail('No se encontró el abono.',404);return p;
 }
 async function file(fileId:string){
  const f=await prepared(`SELECT * FROM jac_reconciliation_attachments WHERE id=? AND state='ready' AND ${g.sql}`,[fileId]).first<FileRow>();
  await authorize();if(!f)fail('No se encontró el soporte.',404);return f;
 }
 async function shows():Promise<Show[]>{
  const result=await db.batch([
   prepared(`SELECT id,data FROM jac_reconciliation_shows WHERE ${g.sql}`),
   prepared(`SELECT id,title,show_date,municipality,entrepreneur FROM jac_crm_shows WHERE source_state NOT IN ('deleted','deleting') AND ${g.sql}`)
  ]);
  await authorize();
  const crm=result[1].results as {id:string;title:string;show_date:string;municipality:string;entrepreneur:string}[];
  const manual=result[0].results as {id:string;data:string}[];
  return [...crm.map(r=>({id:r.id,name:r.title,date:r.show_date,city:r.municipality,entrepreneur:r.entrepreneur,source:'crm' as const})),...manual.map(r=>({id:r.id,...JSON.parse(r.data),source:'reconciliation' as const}))].sort((a,b)=>a.date.localeCompare(b.date)||a.name.localeCompare(b.name,'es'));
 }
 async function receiptCandidates(criteria:{amount:number|null;date:string|null},autoEligible=false){
  const rows=(await prepared(`SELECT * FROM jac_reconciliation_payments WHERE ${g.sql}`).all<PaymentRow>()).results;
  await authorize();
  return matchReceiptPayments(rows.map(row=>{const p=unpack(row);return {id:p.id,version:p.version,date:p.date,amount:p.amount,status:p.status,entrepreneur:p.entrepreneur,showId:p.showId};}),criteria,autoEligible);
 }
 function showGate(showId:string){return showId?`(EXISTS(SELECT 1 FROM jac_reconciliation_shows WHERE id=?) OR EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND source_state NOT IN ('deleted','deleting')))`:'1';}
 const showArgs=(showId:string)=>showId?[showId,showId]:[];
 function audit(paymentId:string,action:string,data:unknown,changedOnly=false){
  return prepared(`INSERT INTO jac_reconciliation_audit (id,payment_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE ${changedOnly?'changes()=1 AND ':''}${g.sql}`,[id(),paymentId,user.id,action,JSON.stringify(data),stamp()]);
 }
 async function cleanup(fileId?:string){
  await authorize();
  // A process interrupted before publication may leave a reserved, inaccessible object.
  await prepared(`UPDATE jac_reconciliation_attachments SET state='deleted' WHERE state='uploading' AND created_at<? AND ${g.sql}`,[new Date(Date.now()-24*60*60*1000).toISOString()]).run();
  const deleted=(await prepared(`SELECT id,object_key FROM jac_reconciliation_attachments WHERE state='deleted' AND object_key<>'' ${fileId?'AND id=? ':''}AND ${g.sql} LIMIT 5`,fileId?[fileId]:[]).all<{id:string;object_key:string}>()).results;
  for(const entry of deleted){
   await authorize();let removed=false;
   try{await env.BUCKET.delete(entry.object_key);removed=true;}catch{/* A later private state read retries the inaccessible object. */}
   await authorize();
   if(removed)await prepared(`UPDATE jac_reconciliation_attachments SET object_key='' WHERE id=? AND state='deleted' AND object_key=? AND ${g.sql}`,[entry.id,entry.object_key]).run();
  }
 }
 await authorize();
 const path=new URL(req.url).pathname.slice('/api/reconciliation'.length),method=req.method;
 if(path==='/scan'&&method==='POST'){
  const release=reserveReceiptReader(user.id);
  try{
   const {bytes,type,hash}=await receiptUpload(req,RECEIPT_OCR_MAX_BYTES);await authorize();
   const duplicate=await prepared(`SELECT * FROM jac_reconciliation_attachments WHERE hash=? AND state='ready' AND ${g.sql}`,[hash]).first<FileRow>();
   await authorize();
   if(duplicate){await payment(duplicate.payment_id);return json({existingPaymentId:duplicate.payment_id,reading:null,matches:[],total:0,autoMatchId:null});}
   const reading=await readReceipt(bytes,type,authorize,req.signal);await authorize();
   const result=reading.amount!==null||reading.date!==null?await receiptCandidates({amount:reading.amount,date:reading.date},reading.autoEligible):{matches:[],total:0,autoMatchId:null};
   await authorize();return json({reading,...result});
  }finally{release();}
 }
 if(path==='/scan/matches'&&method==='POST'){
  const input=receiptLookupSchema.safeParse(await body(req));
  if(!input.success)fail('Indica un valor positivo con máximo dos decimales y/o una fecha válida.');
  // Correcting OCR fields only searches. It cannot attach, mark identified or alter originals.
  const result=await receiptCandidates(input.data);await authorize();return json(result);
 }
 if(path==='/state'&&method==='GET'){
  await cleanup();
  const out=await db.batch([
   prepared(`SELECT * FROM jac_reconciliation_payments WHERE ${g.sql} ORDER BY created_at,id`),
   prepared(`SELECT * FROM jac_reconciliation_attachments WHERE state='ready' AND ${g.sql} ORDER BY created_at,id`),
   prepared(`SELECT id,name,count,completed,created_at FROM jac_reconciliation_imports WHERE ${g.sql} ORDER BY created_at,id`)
  ]);
  const catalog=await shows(),files=(out[1].results as unknown as FileRow[]).map(fileInfo),payments=(out[0].results as unknown as PaymentRow[]).map(unpack),byId=new Map(payments.map(p=>[p.id,p]));
  for(const f of files)byId.get(f.paymentId)?.attachments.push(f);
  await authorize();return json({payments,shows:catalog,files,imports:out[2].results});
 }
 if(path==='/import'&&method==='POST'){
  const input=await body(req),rows=input.rows;
  if(!Array.isArray(rows)||!rows.length||rows.length>5000)fail('Importa entre 1 y 5.000 filas por hoja.');
  if(typeof input.fileHash!=='string'||!/^[a-f0-9]{64}$/.test(input.fileHash))fail('No se pudo verificar la identidad del archivo.');
  const name=text(input.name,250);if(!name)fail('Falta el nombre del archivo.');
  const keys=new Set<string>();
  const clean=rows.map((raw:unknown,index:number)=>{
   if(!raw||typeof raw!=='object'||Array.isArray(raw))fail('La fila '+(index+1)+' no contiene datos válidos.');
   const r=raw as Record<string,unknown>;
   if(!validDate(r.date))fail('Revisa la fecha de la fila '+r.sourceRow+'.');
   if(typeof r.amount!=='number'||r.amount<=0)fail('Revisa el valor de la fila '+r.sourceRow+'.');
   const amount=cents(r.amount)/100;
   if(typeof r.sourceRow!=='number'||!Number.isSafeInteger(r.sourceRow)||r.sourceRow<1)fail('Falta la fila de origen.');
   const sheet=text(r.sheet,150),key=sheet+'|'+r.sourceRow;if(keys.has(key))fail('La selección repite la fila '+r.sourceRow+'.');keys.add(key);
   if(!r.original||typeof r.original!=='object'||Array.isArray(r.original))fail('Faltan las columnas originales.');
   if(JSON.stringify(r.original).length>60000)fail('La fila '+r.sourceRow+' contiene demasiado texto.');
   const data:Original={date:r.date,amount,description:text(r.description,4000),reference:text(r.reference),thirdParty:text(r.thirdParty),receipt:text(r.receipt),invoice:text(r.invoice),original:r.original as Record<string,unknown>,sourceRow:r.sourceRow,sheet,importName:name};
   return {key,data};
  });
  const manifest=await digest(new TextEncoder().encode(canonical(clean.map(r=>({key:r.key,facts:JSON.parse(originalIdentity(r.data))})).sort((a,b)=>a.key.localeCompare(b.key,'en')))));
  await authorize();
  const getImport=()=>prepared(`SELECT * FROM jac_reconciliation_imports WHERE hash=? AND ${g.sql}`,[input.fileHash as string]).first<ImportRow>();
  let imp=await getImport();
  if(!imp){await prepared(`INSERT OR IGNORE INTO jac_reconciliation_imports (id,hash,manifest_hash,name,count,created_by,created_at) SELECT ?,?,?,?,?,?,? WHERE ${g.sql}`,[id(),input.fileHash as string,manifest,name,rows.length,user.id,stamp()]).run();imp=await getImport();}
  await authorize();if(!imp)fail('No se pudo iniciar la importación.',409);
  if(imp.count!==clean.length||(imp.manifest_hash&&imp.manifest_hash!==manifest))fail('Esta hoja ya tiene una selección de filas distinta. Recupera la selección original; el avance guardado se conserva.',409);
  const expected=new Map(clean.map(r=>[r.key,originalIdentity(r.data)]));
  const stored=await prepared(`SELECT source_key,original FROM jac_reconciliation_payments WHERE import_id=? AND ${g.sql}`,[imp.id]).all<{source_key:string;original:string}>();
  if(stored.results.some(r=>expected.get(r.source_key)!==originalIdentity(JSON.parse(r.original))))fail('Los datos originales no coinciden con la importación guardada. No se modificó el avance.',409);
  if(!imp.manifest_hash){
   await prepared(`UPDATE jac_reconciliation_imports SET manifest_hash=? WHERE id=? AND manifest_hash='' AND ${g.sql}`,[manifest,imp.id]).run();
   imp=await getImport();await authorize();if(!imp||imp.manifest_hash!==manifest)fail('Otra importación está en curso. Actualiza y vuelve a intentar.',409);
  }
  if(imp.completed&&stored.results.length===clean.length){await authorize();return json({imported:0,skipped:imp.count,total:imp.count,message:'Esta hoja ya fue importada. Tus conciliaciones se conservaron.'});}
  let inserted=0;
  for(let offset=0;offset<clean.length;offset+=50){
   await authorize();const time=stamp();
   const result=await db.batch(clean.slice(offset,offset+50).map(r=>prepared(`INSERT OR IGNORE INTO jac_reconciliation_payments (id,import_id,source_key,original,annotation,created_at,updated_at) SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jac_reconciliation_imports WHERE id=? AND manifest_hash=?) AND ${g.sql}`,[id(),imp!.id,r.key,JSON.stringify({...r.data,importName:imp!.name}),JSON.stringify(defaults),time,time,imp!.id,manifest])));
   inserted+=result.reduce((sum,r)=>sum+(r.meta.changes||0),0);
  }
  await authorize();
  await prepared(`UPDATE jac_reconciliation_imports SET completed=1 WHERE id=? AND manifest_hash=? AND count=(SELECT COUNT(*) FROM jac_reconciliation_payments WHERE import_id=?) AND ${g.sql}`,[imp.id,manifest,imp.id]).run();
  const confirmed=await getImport();if(!confirmed?.completed)fail('La importación quedó parcial. Reintenta el mismo archivo y selección para continuar sin duplicar.',409);
  await authorize();return json({imported:inserted,skipped:rows.length-inserted,total:rows.length});
 }
 if(path==='/shows'&&method==='POST'){
  const input=await body(req),s={name:text(input.name,200),date:input.date,city:text(input.city,100),entrepreneur:text(input.entrepreneur,200)};
  if(!s.name||!validDate(s.date))fail('Escribe el nombre y la fecha del show.');
  await authorize();const existing=(await shows()).find(t=>t.date===s.date&&t.name.toLowerCase()===s.name.toLowerCase()&&t.city.toLowerCase()===s.city.toLowerCase());
  if(existing)return json({...existing,existing:true});
  const showId='historical-'+await digest(new TextEncoder().encode(canonical([s.date,s.name.normalize('NFC').toLowerCase(),s.city.normalize('NFC').toLowerCase()])));
  await prepared(`INSERT OR IGNORE INTO jac_reconciliation_shows (id,data,created_by,created_at) SELECT ?,?,?,? WHERE ${g.sql}`,[showId,JSON.stringify(s),user.id,stamp()]).run();
  await authorize();const saved=(await shows()).find(s=>s.id===showId);if(!saved)fail('No se pudo guardar la referencia histórica.',409);return json(saved,201);
 }
 let match=path.match(/^\/payments\/([^/]+)$/);
 if(match&&method==='PATCH'){
  const paymentId=match[1],p=await payment(paymentId),input=await body(req);
  if(input.version!==p.version)fail('Este abono cambió en otra pestaña. Cierra la ficha y vuelve a abrirla.',409);
  const a={...JSON.parse(p.annotation)} as Annotation;
  for(const key of Object.keys(defaults) as (keyof Annotation)[])if(key in input)a[key]=text(input[key],key==='notes'?5000:500);
  if(!['pending','review','identified'].includes(a.status))fail('Estado no válido.');
  if(!['unknown','required','not_required'].includes(a.billingStatus))fail('Revisa la opción de facturación.');
  if(a.status==='identified'&&(!a.showId||!a.entrepreneur))fail('Para identificar el abono debes asignar el show y el empresario.');
  await authorize();
  if(a.showId&&!(await shows()).some(s=>s.id===a.showId))fail('Selecciona un show válido.');
  const result=await db.batch([
   prepared(`UPDATE jac_reconciliation_payments SET annotation=?,version=version+1,updated_at=? WHERE id=? AND version=? AND ${showGate(a.showId)} AND ${g.sql}`,[JSON.stringify(a),stamp(),paymentId,p.version,...showArgs(a.showId)]),
   audit(paymentId,'edit',{before:JSON.parse(p.annotation),after:a,previousVersion:p.version},true)
  ]);
  await authorize();if(!result[0].meta.changes)fail('El abono o el show cambió. Actualiza la ficha.',409);
  const out=unpack(await payment(paymentId));out.attachments=(await prepared(`SELECT * FROM jac_reconciliation_attachments WHERE payment_id=? AND state='ready' AND ${g.sql} ORDER BY created_at,id`,[paymentId]).all<FileRow>()).results.map(fileInfo);
  await authorize();return json(out);
 }
 match=path.match(/^\/payments\/([^/]+)\/history$/);
 if(match&&method==='GET'){
  await payment(match[1]);const history=(await prepared(`SELECT actor_id,action,data,created_at FROM jac_reconciliation_audit WHERE payment_id=? AND ${g.sql} ORDER BY created_at DESC,id DESC`,[match[1]]).all<{actor_id:string;action:string;data:string;created_at:string}>()).results;
  await authorize();return json({history:history.map(r=>({...r,data:JSON.parse(r.data)}))});
 }
 match=path.match(/^\/payments\/([^/]+)\/files$/);
 if(match&&method==='POST'){
  const paymentId=match[1];await payment(paymentId);
  const {form,upload,bytes,type,hash}=await receiptUpload(req);await authorize();
  const rawVersion=form.get('paymentVersion'),version=rawVersion===null?null:Number(rawVersion);
  if(version!==null&&(!Number.isSafeInteger(version)||version<1||(await payment(paymentId)).version!==version))fail('Este abono cambió. Revisa su ficha antes de adjuntar el comprobante.',409);
  const versionGate=version===null?'':' AND version=?',versionArgs=version===null?[]:[version];
  const findDuplicate=()=>prepared(`SELECT * FROM jac_reconciliation_attachments WHERE hash=? AND state='ready' AND ${g.sql}`,[hash]).first<FileRow>();
  const duplicate=await findDuplicate();await authorize();
  if(duplicate){if(duplicate.payment_id===paymentId)return json(fileInfo(duplicate));fail('Este comprobante ya está adjunto a otro abono. Revisa la relación antes de repetirlo.',409);}
  const fileId=id(),key='crm/reconciliation/'+paymentId+'/'+fileId,time=stamp(),name=text(upload.name||'comprobante',240).replace(/[\x00-\x1f/\\]/g,'_');
  try{
   const reservation=await prepared(`INSERT INTO jac_reconciliation_attachments (id,payment_id,object_key,hash,name,type,size,state,created_by,created_at) SELECT ?,?,?,?,?,?,?,'uploading',?,? WHERE EXISTS(SELECT 1 FROM jac_reconciliation_payments WHERE id=?${versionGate}) AND ${g.sql}`,[fileId,paymentId,key,hash,name,type,bytes.length,user.id,time,paymentId,...versionArgs]).run();
   await authorize();if(!reservation.meta.changes)fail('No se pudo preparar el soporte. Vuelve a intentar.',409);
   await authorize();await env.BUCKET.put(key,bytes,{httpMetadata:{contentType:type}});await authorize();await payment(paymentId);
   const results=await db.batch([
    prepared(`UPDATE jac_reconciliation_attachments SET state='ready' WHERE id=? AND state='uploading' AND EXISTS(SELECT 1 FROM jac_reconciliation_payments WHERE id=?${versionGate}) AND ${g.sql}`,[fileId,paymentId,...versionArgs]),
    audit(paymentId,'attach',{id:fileId,name,hash},true)
   ]);
   if(!results[0].meta.changes){await authorize();fail('El abono cambió. El soporte no se guardó.',409);}
  }catch(error){
   // Retire only this request's unfinished reservation. A lost DB acknowledgement
   // must never delete an object whose ready record already committed.
   try{
    const retired=await db.prepare(`UPDATE jac_reconciliation_attachments SET state='deleted' WHERE id=? AND object_key=? AND created_by=? AND state='uploading'`).bind(fileId,key,user.id).run();
    if(retired.meta.changes){await env.BUCKET.delete(key);await db.prepare(`UPDATE jac_reconciliation_attachments SET object_key='' WHERE id=? AND state='deleted' AND object_key=?`).bind(fileId,key).run();}
   }catch{/* Keep the durable reservation; private cleanup retries safely. */}
   if(error instanceof CrmFailure)throw error;
   await authorize();const other=await findDuplicate();await authorize();
   if(other){if(other.payment_id===paymentId)return json(fileInfo(other),other.id===fileId?201:200);fail('Este comprobante acaba de adjuntarse a otro abono. Actualiza la ficha.',409);}throw error;
  }
  await authorize();return json({id:fileId,paymentId,name,type,size:bytes.length,url:'/api/reconciliation/files/'+fileId,createdAt:time},201);
 }
 match=path.match(/^\/files\/([^/]+)$/);
 if(match&&['GET','DELETE'].includes(method)){
  const f=await file(match[1]);
  if(method==='GET'){
   const object=await env.BUCKET.get(f.object_key);
   try{await authorize();await file(f.id);}catch(error){await object?.body.cancel().catch(()=>{});throw error;}
   if(!object)fail('No se pudo recuperar el soporte.',404);
   return new Response(object.body,{headers:{...payrollHeaders,'Content-Type':f.type,'Content-Length':String(f.size),'Content-Disposition':"inline; filename*=UTF-8''"+encodeURIComponent(f.name),'Content-Security-Policy':"default-src 'none'; sandbox",'Cross-Origin-Resource-Policy':'same-origin'}});
  }
  const result=await db.batch([
   prepared(`UPDATE jac_reconciliation_attachments SET state='deleted' WHERE id=? AND state='ready' AND ${g.sql}`,[f.id]),
   audit(f.payment_id,'remove_attachment',{id:f.id,name:f.name},true)
  ]);
  await authorize();if(!result[0].meta.changes)fail('El soporte cambió. Actualiza la ficha.',409);
  await cleanup(f.id);await authorize();return json({deleted:true});
 }
 return json({error:'No se encontró esta operación.'},404);
}
