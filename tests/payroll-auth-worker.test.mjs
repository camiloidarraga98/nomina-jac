import test from 'node:test';
import assert from 'node:assert/strict';
const base=process.env.PAYROLL_AUTH_TEST_URL;
test('Worker local ejecuta scrypt, acceso propio y cierre de sesión',{skip:!base},async()=>{
 assert.match(new URL(base).hostname,/^(127\.0\.0\.1|localhost)$/);const password='Solo pruebas locales de acceso 2026',owner='camilo@mac2you.co';
 const post=async(body,cookie='',email='')=>{const r=await fetch(base+'/api/auth',{method:'POST',headers:{Origin:base,'Content-Type':'application/json',Cookie:cookie,'oai-authenticated-user-email':email},body:JSON.stringify(body)});return {status:r.status,body:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]||''};};
 let login=await post({action:'login',username:'camilo',password});if(login.status!==200){const bootstrap=await post({action:'bootstrap',username:'camilo',password},'',owner);assert.equal(bootstrap.status,200,JSON.stringify(bootstrap.body));login=bootstrap;}
 assert.match(login.cookie,/^jac_session=/);const data=await fetch(base+'/api/payroll',{headers:{Cookie:login.cookie}});assert.equal(data.status,200);assert.ok((await data.json()).data.employees.length>0);
 const spoof=await fetch(base+'/api/payroll',{headers:{'oai-authenticated-user-email':owner}});assert.equal(spoof.status,401);
 const users=await fetch(base+'/api/users',{headers:{Cookie:login.cookie}});assert.equal(users.status,200);assert.equal((await users.json()).users.length,3);
 const noOrigin=await fetch(base+'/api/auth',{method:'POST',headers:{Cookie:login.cookie,'Content-Type':'application/json'},body:JSON.stringify({action:'logout'})});assert.equal(noOrigin.status,403);
 assert.equal((await post({action:'logout'},login.cookie)).status,200);assert.equal((await fetch(base+'/api/payroll',{headers:{Cookie:login.cookie}})).status,401);
 assert.equal((await post({action:'login',username:'camilo',password})).status,200);
});
