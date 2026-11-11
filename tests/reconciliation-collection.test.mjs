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
const provider=receipts=>Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({receipts,complete:true,moreReceipts:false})}]}]});
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
test('different counts or physical identities remain reviewable but cannot automatically identify; repeated references are rejected',async()=>{
 let calls=0;globalThis.fetch=async()=>provider(++calls===1?ten():[...ten(),item(10)]);
 const r=await m.readReceiptCollection(receiptJPEG,'image/jpeg',auth);assert.equal(r.receipts.length,10);assert.equal(r.complete,false);assert(r.warnings.length);assert(r.receipts.every(p=>!p.reading.autoEligible));
 globalThis.fetch=async()=>provider([item(0),item(1,{reference:'REC-0'})]);await assert.rejects(m.readReceiptCollection(receiptJPEG,'image/jpeg',auth),e=>e.status===422);
 let a=0;calls=0;globalThis.fetch=async()=>{calls++;return provider(ten());};await assert.rejects(m.readReceiptCollection(receiptJPEG,'image/jpeg',async()=>{if(++a===2)throw Error('revoked');}),/revoked/);assert.equal(calls,1);
});
test('signed evidence binds the receipt identities, optional bounds, original, preview and actor without granting access',()=>{
 const data={actor:'fixture-owner',sourceHash:'a'.repeat(64),previewHash:'b'.repeat(64),receipts:[{index:0,row:1,column:1,reference:'REC-0',amount:1250000.25,date:'2026-11-01',bounds:null,key:'reference:REC-0'}]};
 const token=m.signCollection(data);assert.deepEqual(m.verifyCollection(token,data.actor,data.sourceHash,data.previewHash),data.receipts);
 for(const [value,actor,source,preview]of [[token+'x',data.actor,data.sourceHash,data.previewHash],[token,'another',data.sourceHash,data.previewHash],[token,data.actor,'c'.repeat(64),data.previewHash],[token,data.actor,data.sourceHash,'d'.repeat(64)]])assert.throws(()=>m.verifyCollection(value,actor,source,preview));
});

const upload=()=>{const form=new FormData();form.set('file',new File([receiptJPEG],'synthetic-original.jpg',{type:'image/jpeg'}));form.set('preview',new File([receiptJPEG],'synthetic-preview.jpg',{type:'image/jpeg'}));return form;};
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
