import test from 'node:test';
import assert from 'node:assert/strict';
import {reconciliationFixture,syntheticImport} from './helpers/reconciliation-worker.mjs';
import {receiptJPEG} from './helpers/reconciliation-image.mjs';

const path='/api/reconciliation/scan/orientation';
const answer=choice=>Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({choice})}]}]});
function upload(bytes=receiptJPEG,type='image/jpeg'){
 const form=new FormData();form.set('file',new File([bytes],'SOURCE_FILENAME_MUST_NOT_LEAVE.jpg',{type}));return form;
}

test('orientation selects each labeled rendering only after independent agreement, without accounting or financial writes',async()=>{
 let choices=[],requests=[];
 const f=await reconciliationFixture({readReceipt:async request=>{
  const body=await request.json();requests.push(body);
  assert.equal(body.text.format.name,'jac_receipt_orientation');assert.equal(body.text.format.strict,true);assert.equal(body.store,false);
  assert.equal(body.input.length,1);assert.equal(body.input[0].content.length,2);
  assert.equal(body.input[0].content[1].image_url,'data:image/jpeg;base64,'+Buffer.from(receiptJPEG).toString('base64'));
  const text=JSON.stringify(body);for(const marker of ['SOURCE_FILENAME_MUST_NOT_LEAVE','PREVIOUS_ROTATION_MUST_NOT_LEAVE','ACCOUNTING_MUST_NOT_LEAVE','Consignación ficticia','REF-0'])assert(!text.includes(marker),marker);
  return answer(choices.shift());
 }});
 try{
  assert.equal((await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(2)})).status,200);
  const before=(await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results,shows=(await f.db.prepare('SELECT * FROM jac_crm_shows').all()).results;
  const audit=(await f.db.prepare('SELECT * FROM jac_reconciliation_audit ORDER BY id').all()).results;
  for(const [choice,rotation] of [['A',0],['B',90],['C',180],['D',270]]){
   choices=[choice,choice];requests=[];const form=upload();form.set('previousRotation','PREVIOUS_ROTATION_MUST_NOT_LEAVE');form.set('candidates','ACCOUNTING_MUST_NOT_LEAVE');
   const response=await f.request(path,{method:'POST',data:form});assert.equal(response.status,200,await response.clone().text());assert.match(response.headers.get('cache-control'),/no-store/);
   assert.deepEqual(await response.json(),{rotation,needsReview:false});assert.equal(requests.length,2);
   assert.deepEqual(requests[0].input[0].content[1],requests[1].input[0].content[1],'Both readers see the same labeled renderings');
   assert.notEqual(requests[0].input[0].content[0].text,requests[1].input[0].content[0].text,'Verification uses its own instruction, not the first answer');
  }
  assert.deepEqual((await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results,before);
  assert.deepEqual((await f.db.prepare('SELECT * FROM jac_crm_shows').all()).results,shows);
  assert.deepEqual((await f.db.prepare('SELECT * FROM jac_reconciliation_audit ORDER BY id').all()).results,audit);
  for(const table of ['jac_reconciliation_attachments','jac_crm_payments','payroll_periods'])assert.equal((await f.db.prepare('SELECT count(*) n FROM '+table).first()).n,0);
 }finally{await f.close();}
});

test('unknown, disagreement and invalid orientation answers never silently choose a rotation or retry indefinitely',async()=>{
 let choices=[],calls=0;const f=await reconciliationFixture({readReceipt:async()=>{calls++;return answer(choices.shift());}});
 try{
  for(const replies of [['unknown'],['B','D'],['D','unknown']]){
   choices=[...replies];calls=0;const response=await f.request(path,{method:'POST',data:upload()});assert.equal(response.status,200,await response.clone().text());
   assert.deepEqual(await response.json(),{rotation:null,needsReview:true});assert.equal(calls,replies.length);assert.equal(choices.length,0);
  }
  choices=['90'];calls=0;const invalid=await f.request(path,{method:'POST',data:upload()});assert.equal(invalid.status,200);assert.deepEqual(await invalid.json(),{rotation:null,needsReview:true});assert.equal(calls,1);
 }finally{await f.close();}
});

test('orientation endpoint requires the CRM session and same origin and bounds the JPEG sheet before calling the provider',async()=>{
 let calls=0;const f=await reconciliationFixture({readReceipt:async()=>{calls++;return answer('A');}});
 try{
  assert.equal((await f.request(path,{method:'POST',data:upload(),authenticated:false})).status,401);
  const req=new Request('http://localhost'+path,{method:'POST',headers:{host:'localhost',origin:'https://unrelated.invalid',cookie:'jac_session='+f.token},body:upload()});
  const crossed=await f.dispatchFetch(req.url,{method:'POST',headers:Object.fromEntries(req.headers),body:new Uint8Array(await req.arrayBuffer())});assert.equal(crossed.status,403);
  const png=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=','base64'));
  for(const [bytes,type] of [[png,'image/png'],[new TextEncoder().encode('%PDF-1.4\nSYNTHETIC ONLY'),'application/pdf'],[new TextEncoder().encode('not-a-jpeg'),'image/jpeg']]){
   const response=await f.request(path,{method:'POST',data:upload(bytes,type)});assert([400,415].includes(response.status),await response.clone().text());
  }
  const large=new Uint8Array(5*1024*1024+1);large.set(receiptJPEG);assert.equal((await f.request(path,{method:'POST',data:upload(large)})).status,413);
  const excess=upload();excess.set('padding','x'.repeat(6*1024*1024));assert.equal((await f.request(path,{method:'POST',data:excess})).status,413);
  assert.equal((await f.request(path,{method:'POST',data:upload(new Uint8Array())})).status,413);assert.equal(calls,0);
  assert.equal((await f.request(path,{method:'POST',data:upload()})).status,200,'Invalid uploads release the reader reservation');assert.equal(calls,2);
 }finally{await f.close();}
});

test('session revocation after the first orientation choice prevents the second call and returns no result',async()=>{
 let calls=0,f;f=await reconciliationFixture({readReceipt:async()=>{
  calls++;await f.db.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').bind(f.owner).run();return answer('D');
 }});
 try{
  const response=await f.request(path,{method:'POST',data:upload()});assert([401,403].includes(response.status));assert.equal(calls,1);
  const body=await response.json();assert.equal(body.rotation,undefined);assert.equal(body.needsReview,undefined);
  for(const table of ['jac_reconciliation_payments','jac_reconciliation_attachments','jac_crm_payments','payroll_periods'])assert.equal((await f.db.prepare('SELECT count(*) n FROM '+table).first()).n,0);
 }finally{await f.close();}
});
