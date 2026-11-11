import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {build} from 'esbuild';
const compiled=await build({entryPoints:['lib/reconciliation-status.ts'],bundle:true,platform:'node',format:'esm',write:false});
const {hasAccountingIdentification:resolved}=await import('data:text/javascript;base64,'+Buffer.from(compiled.outputFiles[0].text).toString('base64'));
test('only an actual original invoice and identified third party remove the review requirement',()=>{
 for(const invoice of ['FV-2-326','123456','FV-001 / FV-002'])assert(resolved({thirdParty:'Empresa de prueba SAS',invoice}));
 for(const thirdParty of ['', 'Tercero sin identificar','Pendiente','N/A','0','Sin definir','Por confirmar','Tercero','Varios','Consumidor final'])assert(!resolved({thirdParty,invoice:'FV-2-326'}),thirdParty);
 for(const invoice of ['', '0','FV-000','Factura','Sin factura','Por facturar','Pendiente','N/A','FV-123 anulada','No disponible'])assert(!resolved({thirdParty:'Empresa de prueba SAS',invoice}),invoice);
 assert(!resolved({thirdParty:'Empresa de prueba SAS',billingStatus:'required'}),'A request to issue an invoice is not a recorded invoice');
});
test('CSV readiness distinguishes accounting evidence from an attached file',async()=>{
 const scope={window:{},TextDecoder,TextEncoder,Blob,URL};vm.runInNewContext(await readFile('public/reconciliation/files.js','utf8'),scope);
 const csv=scope.FileTools.csvForPayments([{id:'synthetic',status:'pending',accountingIdentified:true,invoice:'FV-1-22',thirdParty:'Empresa ficticia',attachments:[],original:{'FAC.SIIGO':'FV-1-22'}}]);
 assert.match(csv,/Identificado y facturado/);assert.match(csv,/FV-1-22/);assert.match(csv,/;"Sí";/);assert.match(csv,/;0;/,'No fictitious support file is invented');
});
