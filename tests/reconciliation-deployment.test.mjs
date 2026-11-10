import test from 'node:test';
import assert from 'node:assert/strict';
import {PDFDocument} from 'pdf-lib';
import {reconciliationFixture,syntheticImport} from './helpers/reconciliation-worker.mjs';
import {receiptJPEG} from './helpers/reconciliation-image.mjs';

// Exercise the actual built hosting entry, including framework dispatch. Calling
// route.ts alone misses vinext's 1 MiB progressive-action parser before API routes.
// Run npm run build before this test. No network or production data is used.
function largeJPEG(bytes){
 const chunks=[receiptJPEG.slice(0,2)];let remaining=bytes-receiptJPEG.length;
 while(remaining>0){const size=Math.min(65537,remaining);assert(size>=4);const segment=new Uint8Array(size);segment.set([255,254,(size-2)>>8,(size-2)&255]);chunks.push(segment);remaining-=size;}
 chunks.push(receiptJPEG.slice(2));return new Uint8Array(Buffer.concat(chunks));
}
const formFor=(bytes,name='synthetic-receipt.jpg')=>{const form=new FormData();form.set('file',new File([bytes],name,{type:'image/jpeg'}));return form;};

test('built Worker accepts large receipt forms through the private API while retaining authentication, body bounds and action limits',async()=>{
 const image=largeJPEG(1200*1024),guide=largeJPEG(600*1024),original=largeJPEG(2200*1024);
 const regions=Array.from({length:8},(_,i)=>({left:i%4*250,top:Math.floor(i/4)*500,right:i%4*250+245,bottom:Math.floor(i/4)*500+495}));
 const f=await reconciliationFixture({workerBundle:process.env.JAC_TEST_WORKER_BUNDLE||'dist/server/index.js',readReceipt:async request=>{
  const body=await request.json();assert.equal(body.store,false);let result;
  if(body.text.format.name==='jac_receipt_layout')result={count:8,rotation:0,rows:2,columns:4,moreReceipts:false};
  else{assert.equal(body.text.format.name,'jac_receipt_regions');assert.equal(body.input[0].content.length,3);result={receipts:regions,complete:true,moreReceipts:false};}
  return Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify(result)}]}]});
 }});
 try{
  const anonymous=async path=>{const wire=new Request('http://localhost'+path,{method:'POST',body:formFor(image)});return f.dispatchFetch(wire.url,{method:'POST',headers:wire.headers,body:new Uint8Array(await wire.arrayBuffer())});};
  let response=await anonymous('/api/reconciliation/scan/layout');assert.equal(response.status,401);assert.match(response.headers.get('content-type'),/json/);assert.equal(f.outgoing(),0);
  const post=async(path,data,headers={})=>{const wire=new Request('http://localhost'+path,{method:'POST',headers:{host:'localhost',origin:'http://localhost',cookie:'jac_session='+f.token,...headers},body:data});return f.dispatchFetch(wire.url,{method:'POST',headers:wire.headers,body:new Uint8Array(await wire.arrayBuffer())});};
  response=await post('/api/reconciliation/scan/layout',formFor(image),{origin:'https://foreign.example.invalid'});assert.equal(response.status,403);assert.equal(f.outgoing(),0);
  response=await f.request('/api/reconciliation/scan/layout',{method:'POST',data:formFor(image)});assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).count,8);
  const form=formFor(image);form.set('grid',new File([guide],'synthetic-guide.jpg',{type:'image/jpeg'}));form.set('expectedCount','8');
  response=await f.request('/api/reconciliation/scan/regions',{method:'POST',data:form});assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).regions.length,8);assert.equal(f.outgoing(),3);
  const tooLarge=new Uint8Array(10*1024*1024+1);tooLarge.set([255,216,255]);response=await f.request('/api/reconciliation/scan/layout',{method:'POST',data:formFor(tooLarge)});assert.equal(response.status,413);assert.match((await response.json()).error,/máximo 10 MB/);assert.equal(f.outgoing(),3);
  response=await anonymous('/acceso');assert.equal(response.status,413,'Server Action limits stay unchanged for pages');
  response=await anonymous('/api/reconciliation-other');assert.equal(response.status,413,'Prefix lookalikes still use the original router');
  assert.equal((await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(1)})).status,200);
  const before=(await f.db.prepare('SELECT id,original FROM jac_reconciliation_payments').all()).results,payment=before[0];
  const batch=formFor(original),operationId=crypto.randomUUID();batch.set('preview',new File([image],'synthetic-preview.jpg',{type:'image/jpeg'}));batch.set('plan',JSON.stringify({operationId,showId:'fixture-show',entrepreneur:'Empresario ficticio',parts:[{paymentId:payment.id,version:1,index:0,bounds:{x:0,y:0,width:1000,height:1000}}]}));
  response=await f.request('/api/reconciliation/batch',{method:'POST',data:batch});assert.equal(response.status,200,await response.clone().text());const saved=await response.json();assert.equal(saved.saved,1);
  response=await f.request('/api/reconciliation/batch',{method:'POST',data:batch});assert.equal(response.status,200);assert.equal((await response.json()).alreadySaved,true);
  response=await f.request(saved.files[0].url);assert.equal(response.status,200);assert.match(response.headers.get('cache-control'),/no-store/);assert.equal((await PDFDocument.load(await response.arrayBuffer())).getPageCount(),2);assert.equal((await f.request(saved.files[0].url,{authenticated:false})).status,401);
  assert.deepEqual((await f.db.prepare('SELECT id,original FROM jac_reconciliation_payments').all()).results,before);
  for(const table of ['jac_crm_payments','payroll_periods'])assert.equal((await f.db.prepare('SELECT count(*) n FROM '+table).first()).n,0);
  await f.db.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').bind(f.owner).run();response=await f.request('/api/reconciliation/scan/layout',{method:'POST',data:formFor(image)});assert.equal(response.status,401);assert.equal(f.outgoing(),3);
 }finally{await f.close();}
});
