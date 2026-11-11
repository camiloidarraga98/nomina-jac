import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {receiptJPEG} from './helpers/reconciliation-image.mjs';
import {reconciliationFixture,syntheticImport} from './helpers/reconciliation-worker.mjs';
import {PDFDocument,PDFDict,PDFArray,PDFName,PDFRawStream,decodePDFRawStream} from 'pdf-lib';

const env={OPENAI_API_KEY:'synthetic-key',PAYROLL_AUTH_KEY:'synthetic-local-signature-secret'};globalThis.__collectionEnv=env;
const output=await build({stdin:{resolveDir:process.cwd(),contents:"export * from './lib/reconciliation-collection';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'fixture',setup(b){b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({loader:'js',contents:'export const env=globalThis.__collectionEnv;'}));}}]});
const dir=await mkdtemp(join(tmpdir(),'jac-collection-'));await writeFile(join(dir,'entry.mjs'),output.outputFiles[0].contents);const m=await import(pathToFileURL(join(dir,'entry.mjs')));await rm(dir,{recursive:true});
const item=(i,extra={})=>({row:Math.floor(i/5)+1,column:i%5+1,reference:'REC-'+i,amountText:new Intl.NumberFormat('es-CO',{minimumFractionDigits:2}).format(1250000.25+i),dateText:String(i%28+1).padStart(2,'0')+'/11/2026',currency:'COP',transactionStatus:'completed',legible:true,bounds:i%2?null:{x:i%5*200,y:Math.floor(i/5)*500,width:195,height:490},...extra});
const ten=()=>Array.from({length:10},(_,i)=>item(i));
const provider=(receipts,extra={})=>Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({receipts,complete:true,moreReceipts:false,...extra})}]}]});
const auth=async()=>{};

test('full photo reads ten separate payments in two independent API calls without requiring crop coordinates',async()=>{
 let calls=0,authorizations=0;
 globalThis.fetch=async(url,opts)=>{calls++;assert.equal(url,'https://api.openai.com/v1/responses');const b=JSON.parse(opts.body);assert.equal(b.model,'gpt-4.1-2025-04-14');assert.equal(b.store,false);assert.equal(b.text.format.name,'jac_receipt_collection');assert.equal(b.input[0].content.length,2);assert.equal(b.input[0].content[1].image_url,'data:image/jpeg;base64,'+Buffer.from(receiptJPEG).toString('base64'));assert.doesNotMatch(b.input[0].content[0].text,/REC-|1250000/);return provider(calls===1?ten():ten().reverse());};
 const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',async()=>{authorizations++;});assert.equal(r.complete,true);assert.equal(r.receipts.length,10);assert.equal(calls,2);assert.equal(authorizations,4);
 r.receipts.forEach((r,i)=>{assert.equal(r.reading.amount,1250000.25+i);assert.equal(r.reading.date,'2026-11-'+String(i+1).padStart(2,'0'));assert.equal(r.reading.autoEligible,true);assert.equal(r.bounds===null,i%2===1);});
});
test('conflicting crop edges discard only the reference crop, conflicting dates discard only date and cannot auto-match',async()=>{
 let calls=0;globalThis.fetch=async()=>provider([item(0,++calls===2?{bounds:{x:600,y:0,width:200,height:400},dateText:'07/04/2026'}:{})]);
 const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(r.receipts[0].bounds,null);assert.equal(r.receipts[0].reading.amount,1250000.25);assert.equal(r.receipts[0].reading.date,null);assert.equal(r.receipts[0].reading.autoEligible,false);
 calls=0;globalThis.fetch=async()=>provider([item(0,{bounds:++calls===1?null:{x:999,y:0,width:500,height:1000}})]);
 const other=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(other.receipts[0].bounds,null);assert.equal(other.receipts[0].reading.autoEligible,true);
});
test('one confirmed receipt has no crop; uncertain multi-receipt bounds remain only visual suggestions',async()=>{
 globalThis.fetch=async()=>provider([item(0)]);const single=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(single.complete,true);assert.equal(single.receipts[0].bounds,null);assert.equal(single.receipts[0].suggestedBounds,null);assert.equal(single.receipts[0].reading.autoEligible,true);
 let calls=0;globalThis.fetch=async()=>provider([item(0,++calls===2?{bounds:{x:450,y:0,width:150,height:400}}:{}),item(1)]);
 const group=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(group.receipts[0].bounds,null);assert.deepEqual(group.receipts[0].suggestedBounds,item(0).bounds);assert.equal(group.receipts[0].reading.amount,1250000.25);assert.equal(group.receipts[0].reading.autoEligible,true);
});
test('different counts retain new receipts and independently confirmed matches; revocation prevents the second reading',async()=>{
 let calls=0;globalThis.fetch=async()=>provider(++calls===1?ten():[...ten(),item(10)]);
 const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(r.receipts.length,11);assert.equal(r.complete,false);assert(r.warnings.length);assert(r.receipts.slice(0,10).every(p=>p.reading.autoEligible));assert.equal(r.receipts[10].reading.autoEligible,false);
 let a=0;calls=0;globalThis.fetch=async()=>{calls++;return provider(ten());};await assert.rejects(m.readReceiptCollection(receiptJPEG,'image/jpeg',async()=>{if(++a===2)throw Error('revoked');}),/revoked/);assert.equal(calls,1);
});
test('an incomplete lone receipt retains independently checked fields without requiring reference or position agreement, cropping or auto-assignment',async()=>{
 for(const dateConflict of [false,true]){
  let calls=0;globalThis.fetch=async()=>provider([item(0,{reference:null,...(++calls===2?{row:2,column:3,...(dateConflict?{dateText:'07/04/2026'}:{})}:{})})],{complete:false});
  const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(calls,2);assert.equal(r.complete,false);assert.equal(r.receipts.length,1);assert(r.warnings.length);
  const p=r.receipts[0];assert.equal(p.bounds,null);assert.equal(p.suggestedBounds,null);assert.equal(p.reading.amount,1250000.25);assert.equal(p.reading.date,dateConflict?null:'2026-11-01');assert.equal(p.reading.autoEligible,false);
 }
});
test('repeated references in either independent reading preserve all ten receipts and limit review to the affected cards',async()=>{
 for(const duplicateIn of ['first','second','both']){
  let calls=0;globalThis.fetch=async()=>{calls++;const receipts=ten();if(duplicateIn==='both'||duplicateIn===(calls===1?'first':'second'))receipts[1].reference=receipts[0].reference;return provider(calls===2?receipts.reverse():receipts);};
  const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(calls,2);assert.equal(r.receipts.length,10);assert.equal(r.complete,true);assert(r.warnings.length);
  r.receipts.forEach((p,i)=>{assert.equal(p.reading.amount,1250000.25+i);assert.equal(p.reading.date,'2026-11-'+String(i+1).padStart(2,'0'));assert.equal(p.referenceNeedsReview,i<2);assert.equal(p.reading.autoEligible,i>=2);assert.equal(p.reference,i<2?null:'REC-'+i);if(i<2)assert(p.reading.warnings.some(w=>w.includes('Esto no confirma pagos duplicados')));});
 }
});
test('positional fallback never steals an independently confirmed reference or accepts conflicting date and amount',async()=>{
 let calls=0;globalThis.fetch=async()=>{const receipts=[item(0,{reference:'REPEATED'}),item(1,{reference:'REPEATED'}),item(2)];if(++calls===2){receipts[0].column=3;receipts[2].column=1;}return provider(receipts);};
 const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(r.receipts[2].reading.amount,1250002.25);assert.equal(r.receipts[2].reference,'REC-2');assert.equal(r.receipts[0].reading.amount,1250000.25);assert.equal(r.complete,false);assert.equal(r.receipts[0].reading.autoEligible,false);assert.equal(r.receipts[2].reading.autoEligible,true);
 calls=0;globalThis.fetch=async()=>provider([item(0,{reference:'REPEATED'}),item(1,{reference:'REPEATED',...(++calls===2?{amountText:'9.000.000',dateText:'07/04/2026'}:{})})]);
 const conflicting=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(conflicting.receipts.length,2);assert.equal(conflicting.receipts[0].reading.amount,1250000.25);assert.equal(conflicting.receipts[1].reading.amount,null);assert.equal(conflicting.receipts[1].reading.date,null);assert(conflicting.receipts.every(p=>!p.reading.autoEligible));
});
test('signed evidence binds the receipt identities, optional bounds, original, preview and actor without granting access',()=>{
 const data={actor:'fixture-owner',sourceHash:'a'.repeat(64),previewHash:'b'.repeat(64),receipts:[{index:0,row:1,column:1,reference:'REC-0',amount:1250000.25,date:'2026-11-01',bounds:null,key:'reference:REC-0'}]};
 const token=m.signCollection(data);assert.deepEqual(m.verifyCollection(token,data.actor,data.sourceHash,data.previewHash),data.receipts);
 for(const [value,actor,source,preview]of [[token+'x',data.actor,data.sourceHash,data.previewHash],[token,'another',data.sourceHash,data.previewHash],[token,data.actor,'c'.repeat(64),data.previewHash],[token,data.actor,data.sourceHash,'d'.repeat(64)]])assert.throws(()=>m.verifyCollection(value,actor,source,preview));
});

const upload=()=>{const form=new FormData();form.set('file',new File([receiptJPEG],'synthetic-original.jpg',{type:'image/jpeg'}));form.set('preview',new File([receiptJPEG],'synthetic-preview.jpg',{type:'image/jpeg'}));return form;};
test('private API searches an incomplete single receipt without approving, storing or duplicating it',async()=>{
 const f=await reconciliationFixture({readReceipt:async()=>provider([item(0,{reference:null})],{complete:false})});
 try{
  await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(2)});const before=(await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results;
  const response=await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload()});assert.equal(response.status,200);const r=await response.json();assert.equal(r.complete,false);assert.equal(r.receipts.length,1);assert.equal(r.receipts[0].matches[0].kind,'exact');assert.equal(r.receipts[0].autoMatchId,null);assert.equal(r.receipts[0].bounds,null);assert.equal(f.outgoing(),2);
  assert.deepEqual((await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results,before);assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
 }finally{await f.close();}
});
test('user-confirmed crops preserve signed identities, persist in private PDFs and reject invalid or repeated regions',async()=>{
 const f=await reconciliationFixture({readReceipt:async()=>provider([item(0,{reference:null,bounds:null}),item(1,{reference:null,bounds:null}),item(2,{reference:null,bounds:null})])});
 try{
  await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(4)});const read=await(await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload()})).json();
  const bounds={x:0,y:0,width:300,height:1000},part=index=>({index,paymentId:read.receipts[index].autoMatchId,version:1,manualBounds:bounds});
  const send=async(parts,operationId=crypto.randomUUID())=>{const form=upload();form.set('plan',JSON.stringify({mode:'collection',evidence:read.evidence,operationId,showId:'fixture-show',entrepreneur:'Empresario ficticio',parts}));return f.request('/api/reconciliation/batch',{method:'POST',data:form});};
  assert.equal((await send([{...part(0),manualBounds:{x:950,y:0,width:100,height:300}}])).status,400);
  assert.equal((await send([part(0),part(1)])).status,400);assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
  const operationId=crypto.randomUUID();let response=await send([part(0)],operationId);assert.equal(response.status,200,await response.clone().text());const saved=await response.json();response=await send([part(0)],operationId);assert.equal((await response.json()).alreadySaved,true);
  assert.equal((await send([part(1)])).status,409,'Another signed identity cannot reuse a previously saved manual crop');
  response=await send([{...part(1),manualBounds:{x:350,y:0,width:300,height:1000}}]);assert.equal(response.status,200,await response.clone().text());
  const audits=(await f.db.prepare("SELECT data FROM jac_reconciliation_audit WHERE action='identify-receipt-batch'").all()).results.map(r=>JSON.parse(r.data));assert.equal(audits.length,2);assert(audits.every(a=>a.parts[0].manualCrop));assert.equal(audits[0].parts[0].readingHash,audits[1].parts[0].readingHash,'Manual borders do not change the original signed reading identity');
  const bytes=Buffer.from(await(await f.request(saved.files[0].url)).arrayBuffer()),pdf=await PDFDocument.load(bytes);assert.equal(pdf.getPageCount(),2);
  const contents=pdf.getPages()[0].node.lookup(PDFName.of('Contents'),PDFArray);const pageCommands=Array.from({length:contents.size()},(_,i)=>Buffer.from(decodePDFRawStream(contents.lookup(i,PDFRawStream)).decode()).toString()).join('\n');
  assert(pageCommands.includes(Buffer.from('Recorte delimitado por el usuario.').toString('hex').toUpperCase()));
  const third=await f.db.prepare("SELECT id FROM jac_reconciliation_payments WHERE json_extract(annotation,'$.status')<>'identified' LIMIT 1").first();assert.equal((await send([{...part(0),paymentId:third.id,manualBounds:{x:700,y:0,width:300,height:1000}}])).status,409,'Moving a crop cannot reassign its signed receipt to another payment');
  for(const table of ['jac_crm_payments','payroll_periods'])assert.equal((await f.db.prepare('SELECT count(*) n FROM '+table).first()).n,0);
 }finally{await f.close();}
});
test('concurrent saves of overlapping manual crops identify at most one existing movement',async()=>{
 const f=await reconciliationFixture({readReceipt:async()=>provider([item(0),item(1)])});
 try{
  await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(2)});const read=await(await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload()})).json();
  const send=async(index)=>{const form=upload();form.set('plan',JSON.stringify({mode:'collection',evidence:read.evidence,operationId:crypto.randomUUID(),showId:'fixture-show',entrepreneur:'Empresario ficticio',parts:[{index,paymentId:read.receipts[index].autoMatchId,version:1,manualBounds:{x:600,y:500,width:300,height:490}}]}));return f.request('/api/reconciliation/batch',{method:'POST',data:form});};
  const result=await Promise.all([send(0),send(1)]);assert.deepEqual(result.map(r=>r.status).sort(),[200,409]);assert.equal((await f.db.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE state='ready'").first()).n,1);assert.equal((await f.db.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE state='uploading'").first()).n,0);
 }finally{await f.close();}
});
test('private API returns candidates despite repeated references and supports reviewed partial saves without duplicate assignments',async()=>{
 const f=await reconciliationFixture({readReceipt:async()=>{const receipts=ten();receipts[1].reference=receipts[0].reference;return provider(receipts);}});
 try{
  await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(11)});
  const originals=(await f.db.prepare('SELECT id,original FROM jac_reconciliation_payments ORDER BY id').all()).results;
  let response=await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload()});assert.equal(response.status,200,await response.clone().text());const read=await response.json();assert.equal(read.receipts.length,10);assert.equal(f.outgoing(),2);
  read.receipts.forEach((r,i)=>{assert.equal(r.autoMatchId===null,i<2);assert(r.matches.some(c=>c.kind==='exact'));assert.equal(r.reading.amount,1250000.25+i);});
  assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
  const save=async(parts)=>{const form=upload();form.set('plan',JSON.stringify({mode:'collection',evidence:read.evidence,operationId:crypto.randomUUID(),showId:'fixture-show',entrepreneur:'Empresario ficticio',parts}));return f.request('/api/reconciliation/batch',{method:'POST',data:form});};
  const selected=read.receipts.map(r=>({index:r.index,paymentId:r.matches.find(c=>c.kind==='exact').id,version:1}));
  for(const parts of [selected.slice(2),selected.slice(0,2)]){response=await save(parts);assert.equal(response.status,200,await response.clone().text());}
  const third=await f.db.prepare("SELECT id FROM jac_reconciliation_payments WHERE json_extract(annotation,'$.status')<>'identified'").first();assert.equal((await save([{...selected[0],paymentId:third.id}])).status,409);
  assert.equal((await f.db.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE state='ready'").first()).n,10);
  assert.deepEqual((await f.db.prepare('SELECT id,original FROM jac_reconciliation_payments ORDER BY id').all()).results,originals);for(const table of ['jac_crm_payments','payroll_periods'])assert.equal((await f.db.prepare('SELECT count(*) n FROM '+table).first()).n,0);
 }finally{await f.close();}
});
test('a signed reading without printed references can be saved in parts without reassigning an already saved receipt',async()=>{
 const f=await reconciliationFixture({readReceipt:async()=>provider([item(0,{reference:null,bounds:null}),item(1,{reference:null,bounds:null})])});
 try{
  await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(3)});
  const response=await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload()});assert.equal(response.status,200);const read=await response.json();
  const save=async(index,paymentId=read.receipts[index].autoMatchId)=>{const form=upload();form.set('plan',JSON.stringify({mode:'collection',evidence:read.evidence,operationId:crypto.randomUUID(),showId:'fixture-show',entrepreneur:'Empresario ficticio',parts:[{index,paymentId,version:1}]}));return f.request('/api/reconciliation/batch',{method:'POST',data:form});};
  for(const index of [0,1]){const r=await save(index);assert.equal(r.status,200,await r.clone().text());}
  const third=await f.db.prepare("SELECT id FROM jac_reconciliation_payments WHERE json_extract(annotation,'$.status')<>'identified'").first();assert.equal((await save(0,third.id)).status,409);
  assert.equal((await f.db.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE state='ready'").first()).n,2);
 }finally{await f.close();}
});
test('private collection API auto-searches each receipt and atomically stores separate supports with and without crops; retries and duplicates preserve financial originals',async()=>{
 const f=await reconciliationFixture({readReceipt:async req=>{const b=await req.json();assert.equal(b.text.format.name,'jac_receipt_collection');assert.equal(b.store,false);assert.equal(b.model,m.COLLECTION_MODEL);return provider(ten());}});
 try{
  assert.equal((await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload(),authenticated:false})).status,401);assert.equal(f.outgoing(),0);
  assert.equal((await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(12)})).status,200);
  const originals=(await f.db.prepare('SELECT id,original FROM jac_reconciliation_payments ORDER BY id').all()).results;
  let res=await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload()});assert.equal(res.status,200,await res.clone().text());const read=await res.json();assert.equal(read.receipts.length,10);assert(read.receipts.every(r=>r.autoMatchId));assert.equal(f.outgoing(),2);assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
  const makePlan=(receipts,overrides={})=>({mode:'collection',evidence:read.evidence,operationId:crypto.randomUUID(),showId:'fixture-show',entrepreneur:'Empresario ficticio',parts:receipts.map(r=>({index:r.index,paymentId:r.autoMatchId,version:1})),...overrides});
  const send=async plan=>{const form=upload();form.set('plan',JSON.stringify(plan));return f.request('/api/reconciliation/batch',{method:'POST',data:form});};
  assert.equal((await send(makePlan(read.receipts,{evidence:read.evidence+'x'}))).status,400);
  const stale=makePlan(read.receipts);stale.parts[9].version=999;assert.equal((await send(stale)).status,409);assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
  const plan=makePlan(read.receipts.slice(0,5));res=await send(plan);assert.equal(res.status,200,await res.clone().text());const saved=await res.json();assert.equal(saved.saved,5);
  res=await send(plan);assert.equal(res.status,200);assert.equal((await res.json()).alreadySaved,true);
  const remaining=makePlan(read.receipts.slice(5));res=await send(remaining);assert.equal(res.status,200,await res.clone().text());assert.equal((await res.json()).saved,5);
  const state=await(await f.request('/api/reconciliation/state')).json();assert.equal(state.payments.filter(p=>p.status==='identified').length,10);assert.equal(state.payments.filter(p=>p.attachments.length===1).length,10);
  const other=state.payments.find(p=>p.status!=='identified');const duplicated=makePlan([read.receipts[0]]);duplicated.parts[0].paymentId=other.id;assert.equal((await send(duplicated)).status,409);
  const legacy=upload();legacy.set('plan',JSON.stringify({operationId:crypto.randomUUID(),showId:'fixture-show',entrepreneur:'Ficticio',parts:[{paymentId:other.id,version:1,index:0,bounds:{x:0,y:0,width:50,height:50}}]}));assert.equal((await f.request('/api/reconciliation/batch',{method:'POST',data:legacy})).status,409,'Changing to old crop mode cannot bypass source deduplication');
  const file=await f.request(saved.files[1].url);assert.equal(file.status,200);assert.equal((await f.request(saved.files[1].url,{authenticated:false})).status,401);const pdf=await PDFDocument.load(await file.arrayBuffer());assert.equal(pdf.getPageCount(),2);
  const names=pdf.catalog.lookup(PDFName.of('Names'),PDFDict).lookup(PDFName.of('EmbeddedFiles'),PDFDict).lookup(PDFName.of('Names'),PDFArray);const spec=names.lookup(1,PDFDict);const attached=spec.lookup(PDFName.of('EF'),PDFDict).lookup(PDFName.of('F'),PDFRawStream);assert.deepEqual(new Uint8Array(decodePDFRawStream(attached).decode()),receiptJPEG);
  assert.deepEqual((await f.db.prepare('SELECT id,original FROM jac_reconciliation_payments ORDER BY id').all()).results,originals);for(const table of ['jac_crm_payments','payroll_periods'])assert.equal((await f.db.prepare('SELECT count(*) n FROM '+table).first()).n,0);
 }finally{await f.close();}
});

test('overlapping detail views are supplied only to independent inventory, preserving a seventh receipt missed in either pass',async()=>{
 for(const missIn of [1,2]){
  let calls=0;globalThis.fetch=async(_,opts)=>{const b=JSON.parse(opts.body),images=b.input[0].content.filter(c=>c.type==='input_image');calls++;assert.equal(images.length,calls===1?1:5);assert.doesNotMatch(b.input[0].content.filter(c=>c.type==='input_text').map(c=>c.text).join(' '),/REC-6|1\.250/);return provider(Array.from({length:calls===missIn?6:7},(_,i)=>item(i,{amountText:'3.000.000',dateText:'28/02/2026'})));};
  const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth,undefined,Array(4).fill(receiptJPEG));assert.equal(r.receipts.length,7);assert.equal(r.complete,false);assert.deepEqual(r.observedCounts,missIn===1?[6,7]:[7,6]);assert.equal(new Set(r.receipts.map(p=>p.reference||p.candidateReference)).size,7);assert.equal(r.receipts.filter(p=>p.reading.autoEligible).length,6);assert(r.receipts.every(p=>p.reading.amount===3000000));
 }
 let calls=0;globalThis.fetch=async(_,opts)=>{calls++;assert.equal(JSON.parse(opts.body).input[0].content.filter(c=>c.type==='input_image').length,1);return provider([item(0)]);};await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth,undefined,Array(4).fill(receiptJPEG));assert.equal(calls,2);
});
const cropOutput=(items)=>Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({receipts:items})}]}]});
const cropItem=(i,extra={})=>{const {row,column,bounds,...reading}=item(i);return {index:i,document:'single_payment',...reading,fullFields:true,...extra};};
const cropRecord=i=>({index:i,row:1,column:i+1,reference:null,candidateReference:'REC-'+i,amount:1250000.25+i,date:'2026-11-'+String(i+1).padStart(2,'0'),bounds:null,key:'position:1:'+(i+1),canVerify:true});
const cropPart=i=>({index:i,bounds:{x:i*200,y:0,width:190,height:900},bytes:receiptJPEG});
test('crop approval independently reads actual pixels and rejects clipped, conflicting or duplicate data without losing other receipts',async()=>{
 for(const bad of [{fullFields:false},{amountText:'9.999.999'},{dateText:'07/04/2026'},{reference:'WRONG'},{document:'multiple_payments'},{legible:false},{transactionStatus:'pending'}]){
  globalThis.fetch=async(_,opts)=>{const b=JSON.parse(opts.body);assert.equal(b.text.format.name,'jac_receipt_crop_review');assert.equal(b.model,m.COLLECTION_MODEL);assert.equal(b.store,false);assert.equal(b.input[0].content.filter(c=>c.type==='input_image').length,2);assert.doesNotMatch(b.input[0].content.filter(c=>c.type==='input_text').map(c=>c.text).join(' '),/REC-|1250000|01\/11\/2026/);return cropOutput([cropItem(0),cropItem(1,bad)]);};
  const r=await m.verifyReceiptCrops([cropPart(0),cropPart(1)],[cropRecord(0),cropRecord(1)],auth);assert.equal(r[0].approved,true);assert.equal(r[0].autoEligible,true);assert.deepEqual(r[0].bounds,cropPart(0).bounds);assert.equal(r[1].approved,false);assert.equal(r[1].bounds,null);
 }
 globalThis.fetch=async()=>cropOutput([cropItem(0),cropItem(0)]);assert.equal((await m.verifyReceiptCrops([cropPart(0)],[cropRecord(0)],auth))[0].approved,false);
 globalThis.fetch=async()=>cropOutput([cropItem(0),cropItem(1,{reference:'REC-0'})]);assert((await m.verifyReceiptCrops([cropPart(0),cropPart(1)],[cropRecord(0),cropRecord(1)],auth)).every(r=>!r.approved));
 let calls=0;globalThis.fetch=async()=>{calls++;return cropOutput([cropItem(0)]);};await assert.rejects(m.verifyReceiptCrops([cropPart(0)],[cropRecord(0)],async()=>{throw Error('revoked');}),/revoked/);assert.equal(calls,0);
 let access=0;await assert.rejects(m.verifyReceiptCrops([cropPart(0)],[cropRecord(0)],async()=>{if(++access===2)throw Error('revoked');}),/revoked/);assert.equal(calls,1);
});
test('crop review API validates signed source and proposed coordinates, upgrades recovered receipts and writes no financial data',async()=>{
 let enumerations=0;const f=await reconciliationFixture({readReceipt:async req=>{const b=await req.json();if(b.text.format.name==='jac_receipt_crop_review')return cropOutput([cropItem(0),cropItem(1)]);return provider(Array.from({length:++enumerations===1?1:2},(_,i)=>item(i,{bounds:cropPart(i).bounds})));}});
 try{
  await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(3)});const before=(await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results;
  const form=upload();form.set('detail-0',new File([receiptJPEG],'detail.jpg',{type:'image/jpeg'}));assert.equal((await f.request('/api/reconciliation/scan/collection',{method:'POST',data:form})).status,400);assert.equal(f.outgoing(),0);
  const read=await(await f.request('/api/reconciliation/scan/collection',{method:'POST',data:upload()})).json();assert.equal(read.receipts.length,2);assert(read.receipts.every(r=>r.bounds===null&&r.cropProposal));assert.equal(read.receipts[1].autoMatchId,null);
  const plan={evidence:read.evidence,sourceHash:read.sourceHash,parts:read.receipts.map(r=>({index:r.index,bounds:r.cropProposal}))};
  const review=(overrides={},authenticated=true)=>{const form=new FormData();form.set('file',new File([receiptJPEG],'preview.jpg',{type:'image/jpeg'}));form.set('plan',JSON.stringify({...plan,...overrides}));for(const r of plan.parts)form.set('crop-'+r.index,new File([receiptJPEG],'crop.jpg',{type:'image/jpeg'}));return f.request('/api/reconciliation/scan/collection/crops',{method:'POST',data:form,authenticated});};
  assert.equal((await review({},false)).status,401);assert.equal((await review({evidence:read.evidence+'x'})).status,400);assert.equal((await review({sourceHash:'a'.repeat(64)})).status,409);assert.equal((await review({parts:[{index:0,bounds:{x:300,y:0,width:200,height:500}}]})).status,400);assert.equal(f.outgoing(),2);
  const response=await review();assert.equal(response.status,200,await response.clone().text());const checked=await response.json();assert(checked.receipts.every(r=>r.approved&&r.autoMatchId));assert.notEqual(checked.evidence,read.evidence);assert.equal(f.outgoing(),3);
  assert.deepEqual((await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results,before);assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
  const save=upload();save.set('plan',JSON.stringify({mode:'collection',evidence:checked.evidence,operationId:crypto.randomUUID(),showId:'fixture-show',entrepreneur:'Ficticio',parts:checked.receipts.map(r=>({index:r.index,paymentId:r.autoMatchId,version:1}))}));const saved=await f.request('/api/reconciliation/batch',{method:'POST',data:save});assert.equal(saved.status,200,await saved.clone().text());assert.equal((await saved.json()).saved,2);
  for(const table of ['jac_crm_payments','payroll_periods'])assert.equal((await f.db.prepare('SELECT count(*) n FROM '+table).first()).n,0);
 }finally{await f.close();}
});

test('API locates missing references, retries a rejected crop once and never promotes an unchecked replacement',async()=>{
 let reviews=0,locations=0;const f=await reconciliationFixture({readReceipt:async req=>{const b=await req.json();if(b.text.format.name==='jac_receipt_relocate'){locations++;assert.match(b.input[0].content[0].text,/REC-1/);return cropOutput([{index:1,bounds:{x:500,y:0,width:400,height:900}}]);}if(b.text.format.name==='jac_receipt_crop_review'){reviews++;return cropOutput([cropItem(1,{fullFields:reviews>1})]);}return provider([item(0,{bounds:null}),item(1,{bounds:null})]);}});
 try{
  await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(2)});const initial=upload();initial.set('locateMissing','true');const scan=await f.request('/api/reconciliation/scan/collection',{method:'POST',data:initial});assert.equal(scan.status,200,await scan.clone().text());const read=await scan.json();assert.equal(locations,1);assert.equal(read.receipts[0].cropProposal,null);assert(read.receipts[1].cropProposal);assert.equal(read.receipts[1].bounds,null);
  const review=(evidence,bounds,attempt)=>{const form=new FormData();form.set('file',new File([receiptJPEG],'preview.jpg',{type:'image/jpeg'}));form.set('crop-1',new File([receiptJPEG],'crop.jpg',{type:'image/jpeg'}));form.set('plan',JSON.stringify({evidence,sourceHash:read.sourceHash,parts:[{index:1,bounds}],attempt}));return f.request('/api/reconciliation/scan/collection/crops',{method:'POST',data:form});};
  const first=await(await review(read.evidence,read.receipts[1].cropProposal,1)).json();assert.equal(first.receipts[0].approved,false);assert.equal(first.receipts[0].bounds,null);assert(first.receipts[0].cropProposal);assert.equal(locations,2);
  const second=await(await review(first.evidence,first.receipts[0].cropProposal,2)).json();assert.equal(second.receipts[0].approved,true);assert.equal(second.receipts[0].cropProposal,null);assert.equal(locations,2);assert.equal(reviews,2);assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
 }finally{await f.close();}
});
