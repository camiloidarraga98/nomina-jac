import test from 'node:test';
import assert from 'node:assert/strict';
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
