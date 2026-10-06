import assert from 'node:assert/strict';
import test from 'node:test';
const base=process.env.PAYROLL_TEST_URL;
if(base&&!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(base))throw new Error('Las pruebas solo pueden modificar la base local.');
const owner='camilo@mac2you.co',assistant='info@jacmusic.co',accountant='contabilidad@jacmusic.co';
const get=()=>fetch(base+'/api/payroll',{headers:{'oai-authenticated-user-email':owner}}).then(r=>r.json());
const post=async(body,email=owner)=>{const r=await fetch(base+'/api/payroll',{method:'POST',headers:{'Content-Type':'application/json',Origin:base,'oai-authenticated-user-email':email},body:JSON.stringify(body)});return {status:r.status,...await r.json()};};
test('reapertura exclusiva, cierre corregido, impresión y eliminación recuperable', {skip:!base},async()=>{
 let current=await get();const p=current.data.periods.find(p=>p.status==='cerrada');assert.ok(p);const frozen=structuredClone(p.snapshot),person=p.snapshot.rows[0].employeeId;
 const denied=await post({action:'reopen',version:current.version,periodId:p.id},assistant);assert.equal(denied.status,403);
 const reopened=await post({action:'reopen',version:current.version,periodId:p.id});assert.equal(reopened.status,200);current=reopened;const period=current.data.periods.find(q=>q.id===p.id);assert.equal(period.ownerOnly,true);assert.deepEqual(period.revisions.at(-1),frozen);
 const malicious=structuredClone(current.data);malicious.periods.find(q=>q.id===p.id).shows[0].sale+=1;const noEdit=await post({action:'save',version:current.version,data:malicious},accountant);assert.notEqual(noEdit.status,200);
 const noClose=await post({action:'close',version:current.version,periodId:p.id},assistant);assert.equal(noClose.status,403);
 const safeEdit=structuredClone(current.data);safeEdit.settings.hourDivisor=200;let changed=await post({action:'save',version:current.version,data:safeEdit},assistant);assert.equal(changed.status,200);current=changed;
 const edit=structuredClone(current.data);edit.periods.find(q=>q.id===p.id).movements.push({id:crypto.randomUUID(),employeeId:person,concept:'Corrección local',kind:'reintegro',quantity:1,amount:18000,note:''});changed=await post({action:'save',version:current.version,data:edit});assert.equal(changed.status,200);current=changed;
 const corrected=await post({action:'close',version:current.version,periodId:p.id});assert.equal(corrected.status,200);current=corrected;const cp=current.data.periods.find(q=>q.id===p.id);assert.equal(cp.snapshot.total,frozen.total+18000);assert.equal(cp.snapshot.closedBy,owner);assert.deepEqual(cp.revisions.at(-1),frozen);assert.equal(cp.snapshot.settings.hourDivisor,frozen.settings.hourDivisor);
 for(const email of [owner,assistant,accountant]){const r=await fetch(base+'/payroll/print?period='+p.id+'&employee='+person,{headers:{'oai-authenticated-user-email':email}});assert.equal(r.status,200);assert.match(r.headers.get('cache-control'),/no-store/);const html=await r.text();assert.match(html,/Imprimir desprendible/);assert.ok(html.includes(cp.snapshot.rows[0].name));}
 const invalid=await fetch(base+'/payroll/print?period='+p.id+'&employee=missing',{headers:{'oai-authenticated-user-email':owner}});assert.ok((await invalid.text()).includes('Desprendible no disponible'));
 const removed=await post({action:'deleteEmployee',version:current.version,employeeId:person},assistant);assert.equal(removed.status,200);current=removed;assert.ok(current.data.employees.find(e=>e.id===person).deleted);assert.equal(current.data.periods.find(q=>q.id===p.id).snapshot.total,cp.snapshot.total);
 const pdf=await fetch(base+'/api/payroll/export?period='+p.id+'&employee='+person+'&format=pdf',{headers:{'oai-authenticated-user-email':accountant}});assert.equal(pdf.status,200);
 const restore=await post({action:'restoreEmployee',version:current.version,employeeId:person});assert.equal(restore.status,200);assert.equal(restore.data.employees.find(e=>e.id===person).deleted,false);assert.equal(restore.data.employees.find(e=>e.id===person).active,false);
});
