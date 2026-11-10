import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const compiled=await build({stdin:{contents:"export {default as worker} from './worker/cloudflare';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'reconciliation-assets-fixtures',setup(builder){
  builder.onResolve({filter:/fans-birthday$/},()=>({path:'fans',namespace:'fixture'}));
  builder.onResolve({filter:/maintenance$/},()=>({path:'maintenance',namespace:'fixture'}));
  builder.onResolve({filter:/^\.\/index$/},args=>args.importer===resolve('worker/cloudflare.ts')?{path:'app',namespace:'fixture'}:undefined);
  builder.onLoad({filter:/.*/,namespace:'fixture'},args=>({loader:'js',contents:args.path==='fans'?"export const handleBirthdayApi=()=>{throw new Error('No fan call expected');};export const processBirthdayJobs=()=>{};":args.path==='maintenance'?"export const runMaintenance=()=>{};":"export default {fetch:async()=>new Response('protected-router')};"}));
}}]});
const folder=await mkdtemp(join(tmpdir(),'jac-reconciliation-assets-')),entry=join(folder,'worker.mjs');
await writeFile(entry,compiled.outputFiles[0].contents);
const {worker}=await import(pathToFileURL(entry));
await rm(folder,{recursive:true});

test('la entrega estática permite solamente los seis assets genéricos de conciliación',async()=>{
  const calls=[];
  const env={JAC_READY:'1',ASSETS:{fetch:async request=>{calls.push(new URL(request.url).pathname);return new Response(request.method==='HEAD'?null:'generic-asset');}}};
  const paths=['/reconciliation/receipt-batch.js','/reconciliation/app.js','/reconciliation/files.js','/reconciliation/style.css','/reconciliation/jszip.min.js','/reconciliation/JSZip-LICENSE.md'];
  for(const path of paths)for(const method of ['GET','HEAD']){
    const response=await worker.fetch(new Request('https://fixture.example.invalid'+path,{method}),env,{});
    assert.equal(await response.text(),method==='HEAD'?'':'generic-asset');
  }
  assert.equal(calls.length,12);
  for(const path of ['/crm/reconciliation','/api/reconciliation/state','/api/reconciliation/files/fixture','/reconciliation/seed.json','/reconciliation/index.html']){
    const response=await worker.fetch(new Request('https://fixture.example.invalid'+path),env,{});
    assert.equal(await response.text(),'protected-router');
  }
  const post=await worker.fetch(new Request('https://fixture.example.invalid/reconciliation/app.js',{method:'POST'}),env,{});
  assert.equal(await post.text(),'protected-router');assert.equal(calls.length,12);
});

test('el entorno sin activar tampoco sirve la conciliación',async()=>{
  const response=await worker.fetch(new Request('https://fixture.example.invalid/reconciliation/app.js'),{ASSETS:{fetch:()=>{throw new Error('Assets must stay blocked');}}},{});
  assert.equal(response.status,503);
});
