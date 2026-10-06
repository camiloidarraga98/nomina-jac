import assert from 'node:assert/strict';
import test from 'node:test';
const base=process.env.PAYROLL_TEST_URL;
const auth=process.env.PAYROLL_TEST_AUTH?{'oai-authenticated-user-email':process.env.PAYROLL_TEST_AUTH}:{};
test('guardado persistente, concurrencia, cierre, exportación y acceso', {skip:!base},async()=>{
 const get=()=>fetch(base+'/api/payroll',{headers:auth}).then(r=>r.json());
 const post=async body=>{const r=await fetch(base+'/api/payroll',{method:'POST',headers:{...auth,'Content-Type':'application/json',Origin:base},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};};
 let original=await get();assert.ok(original.data.employees.length>0);
 if(process.env.PAYROLL_TEST_AUTH){const unauth=await fetch(base+'/api/payroll',{headers:{Host:'unauthorized.example'}});assert.equal(unauth.status,401);
 const landing=await fetch(base+'/',{headers:{Host:'unauthorized.example'}});assert.ok(!(await landing.text()).includes('YONIER ALEJANDRO'));}
 const csrf=await fetch(base+'/api/payroll',{method:'POST',headers:{...auth,Origin:'https://unauthorized.example'},body:'{}'});assert.equal(csrf.status,403);
 const a=structuredClone(original.data),b=structuredClone(original.data);a.settings.company='Prueba simultánea A';b.settings.company='Prueba simultánea B';
 const result=await Promise.all([post({action:'save',version:original.version,data:a}),post({action:'save',version:original.version,data:b})]);assert.deepEqual(result.map(r=>r.status).sort(),[200,409]);
 let saved=await get();assert.equal(saved.version,original.version+1);assert.equal(saved.data.settings.company,result.find(r=>r.status===200).body.data.settings.company);
 saved.data.settings.company=original.data.settings.company;let restored=await post({action:'save',version:saved.version,data:saved.data});assert.equal(restored.status,200);
 const p=restored.body.data.periods.find(p=>p.status==='abierta');assert.ok(p);const closed=await post({action:'close',version:restored.body.version,periodId:p.id});assert.equal(closed.status,200);const frozen=closed.body.data.periods.find(q=>q.id===p.id).snapshot;assert.ok(frozen.total>0);
 const edited=structuredClone(closed.body.data);edited.employees[0].showRate=800000;
 const update=await post({action:'save',version:closed.body.version,data:edited});assert.equal(update.status,200);assert.equal(update.body.data.periods.find(q=>q.id===p.id).snapshot.total,frozen.total);
 const bad=structuredClone(update.body.data);bad.periods.find(q=>q.id===p.id).shows=[];const blocked=await post({action:'save',version:update.body.version,data:bad});assert.equal(blocked.status,400);
 for(const [format,mime] of [['pdf','application/pdf'],['slips','application/pdf'],['xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],['zip','application/zip']]){const r=await fetch(base+'/api/payroll/export?period='+p.id+'&format='+format,{headers:auth});assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),mime);assert.ok((await r.arrayBuffer()).byteLength>500);assert.match(r.headers.get('cache-control'),/no-store/);}
 if(process.env.PAYROLL_TEST_AUTH){const noExport=await fetch(base+'/api/payroll/export?period='+p.id+'&format=xlsx',{headers:{Host:'unauthorized.example'}});assert.equal(noExport.status,401);}
 const retired=await fetch(base+'/api/registro');assert.equal(retired.status,410);
});
