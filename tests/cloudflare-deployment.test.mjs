import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {pathToFileURL} from 'node:url';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';

const dir=await mkdtemp(join(tmpdir(),'jac-cloudflare-test-'));
const out=join(dir,'test.mjs');
await build({stdin:{contents:"export {default as worker} from './worker/cloudflare';export {getChatGPTUser} from './app/chatgpt-auth';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',outfile:out,plugins:[{name:'isolated-cloudflare',setup(b){
 b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fake'}));
 b.onResolve({filter:/^next\/(headers|navigation)$/},a=>({path:a.path,namespace:'fake'}));
 b.onResolve({filter:/^\.\/index$/},a=>a.importer===resolve('worker/cloudflare.ts')?{path:'application',namespace:'fake'}:undefined);
 b.onLoad({filter:/.*/,namespace:'fake'},a=>({contents:a.path==='env'?'export const env=globalThis.__cfTestEnv;':a.path==='application'?'export default {fetch(){globalThis.__cfCalls++;return new Response("application");}};':a.path==='next/headers'?'export const headers=async()=>globalThis.__cfHeaders;':'export function redirect(){throw Error("redirect");}'}));
}}]});
globalThis.__cfTestEnv={};globalThis.__cfHeaders=new Headers();globalThis.__cfCalls=0;
const m=await import(pathToFileURL(out));
test.after(async()=>{await rm(dir,{recursive:true,force:true});});

test('el destino sin activar bloquea aplicación, API, adjuntos y webhooks sin ejecutar sus efectos',async()=>{
 for(const path of ['/','/api/auth','/api/notices/slack','/api/crm/file?id=private','/fotografia']){
  const r=await m.worker.fetch(new Request('https://staging.example.invalid'+path,{method:'POST'}),{},{});
  assert.equal(r.status,503);assert.equal(r.headers.get('Cache-Control'),'no-store');
 }
 assert.equal(globalThis.__cfCalls,0);
 const health=await m.worker.fetch(new Request('https://staging.example.invalid/_jac/health'),{},{});
 assert.deepEqual(await health.json(),{service:'JAC',ready:false});assert.equal(globalThis.__cfCalls,0);
});

test('solo la activación explícita de ejecución entrega las peticiones a la aplicación existente',async()=>{
 const env={JAC_READY:'1'};
 const r=await m.worker.fetch(new Request('https://staging.example.invalid/agenda'),env,{});
 assert.equal(r.status,200);assert.equal(await r.text(),'application');assert.equal(globalThis.__cfCalls,1);
 const h=await m.worker.fetch(new Request('https://staging.example.invalid/_jac/health'),env,{});
 assert.deepEqual(await h.json(),{service:'JAC',ready:true});
});

test('Cloudflare independiente rechaza identidad de Sites falsificada y conserva el perfil original',async()=>{
 globalThis.__cfHeaders=new Headers({'oai-authenticated-user-email':'camilo@mac2you.co'});
 globalThis.__cfTestEnv.JAC_HOSTING='cloudflare';assert.equal(await m.getChatGPTUser(),null);
 delete globalThis.__cfTestEnv.JAC_HOSTING;
 assert.equal((await m.getChatGPTUser()).email,'camilo@mac2you.co');
});
