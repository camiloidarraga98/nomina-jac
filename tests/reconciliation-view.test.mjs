import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import vm from 'node:vm';
import {build} from 'esbuild';

const context = {user:null,active:true,reads:0};
globalThis.__reconciliationView = context;
const result = await build({
  stdin:{contents:"export {GET} from './app/crm/reconciliation/route';",resolveDir:process.cwd()},
  bundle:true,platform:'node',format:'esm',write:false,
  plugins:[{name:'reconciliation-view-fixtures',setup(builder){
    builder.onResolve({filter:/^@\/lib\/(payroll-access|crm-access|crm-store)$/},args=>({path:args.path,namespace:'fixture'}));
    builder.onLoad({filter:/.*/,namespace:'fixture'},args=>({loader:'js',contents:
      args.path.endsWith('payroll-access') ? "export const payrollUser=async()=>globalThis.__reconciliationView.user;export const payrollHeaders={'Cache-Control':'private, no-store, max-age=0','Vary':'Cookie','X-Robots-Tag':'noindex, nofollow'};" :
      args.path.endsWith('crm-access') ? "export const crmGuard=()=>({sql:'fixture',bindings:[]});" :
      "export const guardActive=async()=>{globalThis.__reconciliationView.reads++;return globalThis.__reconciliationView.active;};"
    }));
  }}]
});
await mkdir('work',{recursive:true});
const temporary = await mkdtemp(resolve('work/reconciliation-view-'));
const bundle = resolve(temporary,'route.mjs');
await writeFile(bundle,result.outputFiles[0].contents);
const {GET} = await import(pathToFileURL(bundle));
await rm(temporary,{recursive:true});
const request = () => new Request('https://fixture.example.invalid/crm/reconciliation?embedded=1');
const admin = {id:'fixture-admin',username:'fixture',isOwner:true,legacy:false,permissions:[],sections:['crm']};

test('la vista no entrega la herramienta a usuarios anónimos, legado o sin CRM administrativo',async()=>{
  for(const user of [null,{...admin,legacy:true},{...admin,isOwner:false}]){
    context.user=user;context.active=true;context.reads=0;
    const response=await GET(request());
    assert.equal(response.status,user&&!user.legacy?403:401);
    assert.doesNotMatch(await response.text(),/reconciliation\/app\.js/);
    assert.equal(context.reads,0);
  }
});

test('revalida sesión activa antes de servir el iframe financiero',async()=>{
  context.user=admin;context.active=false;context.reads=0;
  const response=await GET(request());
  assert.equal(response.status,403);assert.equal(context.reads,1);
  assert.doesNotMatch(await response.text(),/reconciliation\/app\.js/);
});

test('administrador activo recibe solo shell genérico privado con scripts locales',async()=>{
  context.user=admin;context.active=true;
  const response=await GET(request()),body=await response.text();
  assert.equal(response.status,200);
  assert.equal(response.headers.get('Cache-Control'),'private, no-store, max-age=0');
  assert.equal(response.headers.get('X-Frame-Options'),'SAMEORIGIN');
  assert.match(response.headers.get('Content-Security-Policy'),/frame-ancestors 'self'/);
  assert.match(body,/src="\/reconciliation\/app\.js\?v=receipt-coverage-16"/);
  assert.doesNotMatch(body,/JAC_INITIAL_IMPORT|indexedDB|offline\.js|https:\/\//);
});

test('exportación rechaza URLs ajenas y retira acceso ante un soporte denegado sin descargar un ZIP parcial',async()=>{
  const events=[],requests=[];
  let zipDownloads=0;
  class Zip {file(){return this;}async generateAsync(){zipDownloads++;throw new Error('No debe producir un paquete parcial');}}
  const sandbox={URL,Blob,Response,CustomEvent,JSZip:Zip,location:{origin:'https://fixture.example.invalid'},dispatchEvent:event=>events.push(event),fetch:async(url,options)=>{requests.push({url,options});return new Response('denied',{status:403});}};
  vm.runInNewContext(await readFile('public/reconciliation/files.js','utf8'),sandbox);
  const payment={id:'fixture-payment',date:'2026-01-01',amount:100,status:'identified',original:{},attachments:[{id:'fixture-file',name:'fixture.pdf',url:'https://untrusted.example.invalid/document'}]};
  await assert.rejects(()=>sandbox.FileTools.exportPackage([payment]),/dirección no válida/);
  assert.equal(requests.length,0);
  payment.attachments[0].url='/api/files/fixture-file';
  await assert.rejects(()=>sandbox.FileTools.exportPackage([payment]),/dirección no válida/);
  assert.equal(requests.length,0);
  delete payment.attachments[0].url;
  await assert.rejects(()=>sandbox.FileTools.exportPackage([payment]),/No se pudo descargar/);
  assert.equal(requests[0].url,'https://fixture.example.invalid/api/reconciliation/files/fixture-file');
  assert.equal(requests[0].options.credentials,'same-origin');
  assert.equal(events[0].type,'jac-reconciliation-access-denied');
  assert.equal(events[0].detail.status,403);
  assert.equal(zipDownloads,0);
});
