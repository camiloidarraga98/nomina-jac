import test from 'node:test';
import assert from 'node:assert/strict';
import {PDFDocument} from 'pdf-lib';
import {reconciliationFixture,syntheticImport} from './helpers/reconciliation-worker.mjs';

test('Workerd/D1/R2: 296 synthetic rows, CRM session, original data, save/retry, private supports and no financial side effects',async()=>{
 const f=await reconciliationFixture();
 try{
  assert.equal((await f.request('/crm/reconciliation',{authenticated:false})).status,401);
  assert.equal((await f.request('/api/reconciliation/state',{authenticated:false})).status,401);
  const view=await f.request('/crm/reconciliation');assert.equal(view.status,200);assert.match(await view.text(),/\/reconciliation\/app.js/);
  const originalShow=await f.db.prepare('SELECT * FROM jac_crm_shows').all();
  const data=syntheticImport(),first=await f.request('/api/reconciliation/import',{method:'POST',data});
  assert.equal(first.status,200,await first.clone().text());assert.equal((await first.json()).imported,296);
  const state=await(await f.request('/api/reconciliation/state')).json();assert.equal(state.payments.length,296);
  const p=state.payments[0],source=data.rows.find(r=>r.sourceRow===p.sourceRow);assert.deepEqual(p.original,source.original);
  const saved=await f.request('/api/reconciliation/payments/'+p.id,{method:'PATCH',data:{version:p.version,status:'identified',showId:'fixture-show',entrepreneur:'Empresario de prueba',billingStatus:'required',nit:'000123-4',businessName:'Empresa ficticia',notes:'Revisado sin generar ingresos'}});
  assert.equal(saved.status,200,await saved.clone().text());assert.equal((await saved.json()).version,2);
  const pdf='%PDF-1.4\nFICTIONAL SUPPORT ONLY\n%%EOF';
  const form=()=>{const data=new FormData();data.set('file',new File([pdf],'fixture.pdf',{type:'application/pdf'}));return data;};
  const uploaded=await f.request('/api/reconciliation/payments/'+p.id+'/files',{method:'POST',data:form()});
  assert.equal(uploaded.status,201,await uploaded.clone().text());const support=await uploaded.json();
  assert.equal((await f.request(support.url,{authenticated:false})).status,401);
  assert.equal(await(await f.request(support.url)).text(),pdf);
  assert.equal((await f.request('/api/reconciliation/payments/'+p.id+'/files',{method:'POST',data:form()})).status,200);
  assert.equal((await f.request('/api/reconciliation/import',{method:'POST',data})).status,200);
  const after=await(await f.request('/api/reconciliation/state')).json(),retained=after.payments.find(r=>r.id===p.id);
  assert.equal(after.payments.length,296);assert.equal(retained.attachments.length,1);assert.equal(retained.notes,'Revisado sin generar ingresos');
  assert.deepEqual((await f.db.prepare('SELECT * FROM jac_crm_shows').all()).results,originalShow.results);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_crm_payments').first()).n,0);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM payroll_periods').first()).n,0);
  assert.equal(f.outgoing(),0);
 }finally{await f.close();}
});

test('Workerd reads a synthetic receipt through an intercepted provider, matches existing cents/date and saves support only on request',async()=>{
 let providerCalls=0;
 const f=await reconciliationFixture({readReceipt:async req=>{
  providerCalls++;const input=await req.json();assert.equal(input.store,false);assert.equal(input.text.format.strict,true);const document=input.input[0].content[1];if(document.type==='input_file')assert.match(document.file_data,/^data:application\/pdf;base64,/);else assert.match(document.image_url,/^data:image\/png;base64,/);
  return Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({document:'single_payment',amountText:'$ 1.250.000,25',dateText:'01/11/2026',currency:'COP',transactionStatus:'completed',legible:true})}]}]});
 }});
 try{
  assert.equal((await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(3)})).status,200);
  const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=','base64');
  const form=()=>{const form=new FormData();form.set('file',new File([png],'fixture.png',{type:'image/png'}));return form;};
  const response=await f.request('/api/reconciliation/scan',{method:'POST',data:form()});assert.equal(response.status,200,await response.clone().text());const result=await response.json();assert.ok(result.autoMatchId);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
  assert.equal(result.matches[0].amount,1250000.25);assert.equal(result.matches[0].date,'2026-11-01');
  const upload=form();upload.set('paymentVersion','1');assert.equal((await f.request('/api/reconciliation/payments/'+result.autoMatchId+'/files',{method:'POST',data:upload})).status,201);
  const repeated=await(await f.request('/api/reconciliation/scan',{method:'POST',data:form()})).json();assert.equal(repeated.existingPaymentId,result.autoMatchId);assert.equal(providerCalls,1);
  const pdf=await PDFDocument.create();pdf.addPage().drawText('SYNTHETIC PAYMENT RECEIPT');const pdfForm=new FormData();pdfForm.set('file',new File([await pdf.save()],'fixture.pdf',{type:'application/pdf'}));const pdfRead=await f.request('/api/reconciliation/scan',{method:'POST',data:pdfForm});assert.equal(pdfRead.status,200,await pdfRead.clone().text());assert.equal((await pdfRead.json()).autoMatchId,result.autoMatchId);assert.equal(providerCalls,2);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_crm_payments').first()).n,0);assert.equal((await f.db.prepare('SELECT count(*) n FROM payroll_periods').first()).n,0);
  const row=await f.db.prepare('SELECT annotation,version FROM jac_reconciliation_payments WHERE id=?').bind(result.autoMatchId).first();assert.equal(JSON.parse(row.annotation).status,'pending');assert.equal(row.version,1);
 }finally{await f.close();}
});

test('upstream authorization failure preserves the JAC session, receipt privacy and manual lookup without writes or retries',async()=>{
 let calls=0;
 const f=await reconciliationFixture({readReceipt:async()=>{calls++;return Response.json({error:{code:'insufficient_permissions',message:'PRIVATE_RECEIPT_KEY_OR_ACCOUNT'}},{status:403});}});
 try{
  assert.equal((await f.request('/api/reconciliation/import',{method:'POST',data:syntheticImport(3)})).status,200);
  const before=(await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results;
  const form=new FormData();form.set('file',new File([Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=','base64')],'synthetic.png',{type:'image/png'}));
  const response=await f.request('/api/reconciliation/scan',{method:'POST',data:form});
  assert.equal(response.status,502);const result=await response.json();assert.match(result.error,/OCR_PERMISOS · HTTP 403/);assert(!JSON.stringify(result).includes('PRIVATE'));
  assert.equal((await f.request('/api/reconciliation/state')).status,200);
  const lookup=await f.request('/api/reconciliation/scan/matches',{method:'POST',data:{amount:1250000.25,date:'2026-11-01'}});
  assert.equal(lookup.status,200);assert.equal((await lookup.json()).matches.length,1);assert.equal(calls,1);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_reconciliation_attachments').first()).n,0);
  assert.deepEqual((await f.db.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all()).results,before);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM jac_crm_payments').first()).n,0);
 }finally{await f.close();}
});
