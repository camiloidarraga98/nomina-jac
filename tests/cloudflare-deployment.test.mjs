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
 b.onResolve({filter:/fans-birthday$/},()=>({path:'fan-api',namespace:'fake'}));
 b.onResolve({filter:/\/lib\/maintenance$/},()=>({path:'maintenance',namespace:'fake'}));
 b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fake'}));
 b.onResolve({filter:/^next\/(headers|navigation)$/},a=>({path:a.path,namespace:'fake'}));
 b.onResolve({filter:/^\.\/index$/},a=>a.importer===resolve('worker/cloudflare.ts')?{path:'application',namespace:'fake'}:undefined);
 b.onLoad({filter:/.*/,namespace:'fake'},a=>({contents:a.path==='fan-api'?"export const handleBirthdayApi=async()=>Response.json({fan:true});export const processBirthdayJobs=async()=>{globalThis.__cfFanRuns++;};":a.path==='maintenance'?'export const runMaintenance=async()=>{globalThis.__cfMaintenanceRuns++;};':a.path==='env'?'export const env=globalThis.__cfTestEnv;':a.path==='application'?'export default {fetch(){globalThis.__cfCalls++;return new Response("application");}};':a.path==='next/headers'?'export const headers=async()=>globalThis.__cfHeaders;':'export function redirect(){throw Error("redirect");}'}));
}}]});
globalThis.__cfTestEnv={};globalThis.__cfHeaders=new Headers();globalThis.__cfCalls=0;globalThis.__cfFanRuns=0;globalThis.__cfMaintenanceRuns=0;
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

test('el servidor definitivo retira todas las entradas temporales del traslado',async()=>{
 const before=globalThis.__cfCalls;
 for(const env of [{},{JAC_READY:'1'}])for(const path of ['/_jac/transfer','/migracion','/api/hosting-transfer','/api/hosting-transfer-inventory']){
  const r=await m.worker.fetch(new Request('https://staging.example.invalid'+path,{method:'POST'}),env,{});
  assert.equal(r.status,404);assert.equal(r.headers.get('Cache-Control'),'no-store');
 }
 assert.equal(globalThis.__cfCalls,before);
});

test('CSS, JavaScript, logo, manifest y service worker salen del binding público con su tipo correcto',async()=>{
 const before=globalThis.__cfCalls,calls=[];
 const files=new Map([['/assets/app.css','text/css'],['/assets/app.js','application/javascript'],['/jac-music-logo.png','image/png'],['/jac-app-icon.png','image/png'],['/favicon.svg','image/svg+xml'],['/manifest.webmanifest','application/manifest+json'],['/jac-push-sw.js','application/javascript'],['/jac-media-offline.js','application/javascript'],['/fotografia-offline.html','text/html'],['/licenses/pdfjs-LICENSE.txt','text/plain']]);
 const env={JAC_READY:'1',ASSETS:{async fetch(request){const path=new URL(request.url).pathname;calls.push([request.method,path]);return new Response(request.method==='HEAD'?null:'public-file',{headers:{'Content-Type':files.get(path)}});}}};
 for(const [path,type] of files)for(const method of ['GET','HEAD']){
  const r=await m.worker.fetch(new Request('https://staging.example.invalid'+path,{method}),env,{});
  assert.equal(r.status,200);assert.equal(r.headers.get('Content-Type'),type);assert.equal(await r.text(),method==='HEAD'?'':'public-file');
 }
 assert.equal(calls.length,files.size*2);assert.equal(globalThis.__cfCalls,before);
});

test('la entrega estática conserva el bloqueo inicial y nunca intercepta API, documentos privados o escrituras',async()=>{
 let assets=0;const ASSETS={async fetch(){assets++;throw Error('No debe alcanzar archivos públicos');}};
 const blocked=await m.worker.fetch(new Request('https://staging.example.invalid/assets/app.css'),{ASSETS},{});assert.equal(blocked.status,503);
 const before=globalThis.__cfCalls;
 for(const path of ['/agenda','/api/users','/api/crm/file?id=private','/api/notices/file?id=private','/api/media/file?id=private','/payroll/print']){
  const r=await m.worker.fetch(new Request('https://staging.example.invalid'+path),{JAC_READY:'1',ASSETS},{});assert.equal(await r.text(),'application');
 }
 const post=await m.worker.fetch(new Request('https://staging.example.invalid/assets/app.css',{method:'POST'}),{JAC_READY:'1',ASSETS},{});assert.equal(await post.text(),'application');
 assert.equal(assets,0);assert.equal(globalThis.__cfCalls,before+7);
});

test('Cloudflare independiente rechaza identidad de Sites falsificada y conserva el perfil original',async()=>{
 globalThis.__cfHeaders=new Headers({'oai-authenticated-user-email':'camilo@mac2you.co'});
 globalThis.__cfTestEnv.JAC_HOSTING='cloudflare';assert.equal(await m.getChatGPTUser(),null);
 delete globalThis.__cfTestEnv.JAC_HOSTING;
 assert.equal((await m.getChatGPTUser()).email,'camilo@mac2you.co');
});

test('rider público entrega GET/HEAD desde Assets sin ejecutar la aplicación ni ampliar el acceso privado',async()=>{
 const before=globalThis.__cfCalls,seen=[];
 const env={JAC_READY:'1',ASSETS:{async fetch(request){seen.push([request.method,new URL(request.url).pathname]);return new Response(request.method==='HEAD'?null:'rider-static',{headers:{'Content-Type':'text/html'}});}}};
 for(const path of ['/rider','/rider/','/rider/style.css','/rider/assets/superior.webp','/rider/rider-tecnico-2026.pdf'])for(const method of ['GET','HEAD']){
  const response=await m.worker.fetch(new Request('https://example.invalid'+path,{method}),env,{});
  assert.equal(response.status,200);assert.equal(await response.text(),method==='HEAD'?'':'rider-static');
  assert.equal(response.headers.get('X-Content-Type-Options'),'nosniff');assert.match(response.headers.get('Content-Security-Policy'),/frame-ancestors 'none'/);
 }
 assert.equal(seen[0][1],'/rider/');assert.equal(globalThis.__cfCalls,before);
 for(const method of ['POST','PUT','DELETE']){
  const response=await m.worker.fetch(new Request('https://example.invalid/rider/',{method}),env,{});assert.equal(response.status,405);assert.equal(response.headers.get('Allow'),'GET, HEAD');
 }
 assert.equal(seen.length,10);
 for(const path of ['/rider-private','/rider.json','/api/users','/api/crm/file?id=private']){
  const response=await m.worker.fetch(new Request('https://example.invalid'+path),env,{});assert.equal(await response.text(),'application');
 }
 const paused=await m.worker.fetch(new Request('https://example.invalid/rider'),{ASSETS:env.ASSETS},{});assert.equal(paused.status,503);
});

test('rider2 independiente conserva lectura pública, CSP, READY y límites de ruta',async()=>{
 const before=globalThis.__cfCalls,seen=[];
 const env={JAC_READY:'1',ASSETS:{async fetch(request){seen.push([request.method,new URL(request.url).pathname]);return new Response(request.method==='HEAD'?null:'simulator',{headers:{'Content-Type':'text/html'}});}}};
 for(const path of ['/rider2','/rider2/','/rider2/simulator.js','/rider2/simulator.css','/rider2/index.html'])for(const method of ['GET','HEAD']){
  const r=await m.worker.fetch(new Request('https://example.invalid'+path,{method}),env,{});
  assert.equal(r.status,200);assert.equal(await r.text(),method==='HEAD'?'':'simulator');
  assert.match(r.headers.get('Content-Security-Policy'),/script-src 'self'/);
 }
 assert.equal(seen[0][1],'/rider2/');assert.equal(globalThis.__cfCalls,before);
 for(const method of ['POST','PUT','DELETE']){const r=await m.worker.fetch(new Request('https://example.invalid/rider2/',{method}),env,{});assert.equal(r.status,405);}
 assert.equal(seen.length,10);
 for(const path of ['/rider2-private','/rider2.json','/api/crm/file?id=private']){const r=await m.worker.fetch(new Request('https://example.invalid'+path),env,{});assert.equal(await r.text(),'application');}
 const blocked=await m.worker.fetch(new Request('https://example.invalid/rider2'),{ASSETS:env.ASSETS},{});assert.equal(blocked.status,503);
});


test('cumpleaños público entrega solo sus recursos y su API sin entrar a CRM o sesiones administrativas',async()=>{
 const before=globalThis.__cfCalls,calls=[];const env={JAC_READY:'1',ASSETS:{async fetch(req){calls.push(new URL(req.url).pathname);return new Response(req.method==='HEAD'?null:'fan-public',{headers:{'Content-Type':new URL(req.url).pathname.endsWith('.png')?'image/png':'text/html'}});}}};
 for(const path of ['/cumple','/cumpleanos/master-v1.png','/cumpleanos/app.js']){
  const r=await m.worker.fetch(new Request('https://fans.example.invalid'+path),env,{});assert.equal(r.status,200);assert.match(r.headers.get('Content-Security-Policy'),/frame-ancestors 'none'/);assert.match(r.headers.get('Content-Security-Policy'),/challenges.cloudflare.com/);assert.equal(r.headers.get('Referrer-Policy'),'no-referrer');assert.equal(r.headers.get('X-Content-Type-Options'),'nosniff');
 }
 assert.deepEqual(calls,['/cumpleanos/','/cumpleanos/master-v1.png','/cumpleanos/app.js']);
 for(const path of ['/cumpleanos','/cumpleanos/','/cumpleanos/index.html','/cumple/','/cumple/index.html'])for(const method of ['GET','HEAD']){
  const r=await m.worker.fetch(new Request('https://fans.example.invalid'+path+'?source=fixture',{method}),env,{});assert.equal(r.status,308);assert.equal(r.headers.get('Location'),'https://fans.example.invalid/cumple?source=fixture');assert.equal(await r.text(),'');
 }
 const head=await m.worker.fetch(new Request('https://fans.example.invalid/cumple',{method:'HEAD'}),env,{});assert.equal(head.status,200);assert.equal(await head.text(),'');assert.equal(calls.length,4);
 for(const path of ['/cumple','/cumple/','/cumpleanos/','/cumpleanos/app.js']){const blocked=await m.worker.fetch(new Request('https://fans.example.invalid'+path,{method:'POST'}),env,{});assert.equal(blocked.status,405);}
 assert.equal(calls.length,4);
 const api=await m.worker.fetch(new Request('https://fans.example.invalid/api/fans/cumpleanos'),env,{});assert.deepEqual(await api.json(),{fan:true});assert.equal(globalThis.__cfCalls,before);
 const privateAPI=await m.worker.fetch(new Request('https://fans.example.invalid/api/crm'),env,{});assert.equal(await privateAPI.text(),'application');assert.equal(globalThis.__cfCalls,before+1);
 const unready=await m.worker.fetch(new Request('https://fans.example.invalid/api/fans/cumpleanos'),{},{});assert.equal(unready.status,503);
 const unreadyPage=await m.worker.fetch(new Request('https://fans.example.invalid/cumple'),{},{});assert.equal(unreadyPage.status,503);
 const unrelated=await m.worker.fetch(new Request('https://fans.example.invalid/cumple-private'),env,{});assert.equal(await unrelated.text(),'application');
 await m.worker.scheduled({cron:'0-59 * * * *'},{});assert.equal(globalThis.__cfFanRuns,0);
 await m.worker.scheduled({cron:'0-59 * * * *'},env);assert.equal(globalThis.__cfFanRuns,1);assert.equal(globalThis.__cfMaintenanceRuns,0,'The second trigger never repeats financial, Slack or media maintenance.');
 await m.worker.scheduled({cron:'* * * * *'},env);assert.equal(globalThis.__cfFanRuns,1);assert.equal(globalThis.__cfMaintenanceRuns,1);
});

test('caché de cumple se renueva una vez sin retirar cookies ni almacenamiento del dispositivo',async()=>{
 const calls=[],env={JAC_READY:'1',ASSETS:{async fetch(req){calls.push(req.url);return new Response('fan-public',{headers:{'Content-Type':'text/html'}});}}};
 const first=await m.worker.fetch(new Request('https://fans.example.invalid/cumple?interno=1'),env,{});
 assert.equal(first.headers.get('Cache-Control'),'private, no-store');assert.equal(first.headers.get('Clear-Site-Data'),'"cache"');
 const marker=first.headers.get('Set-Cookie');assert.match(marker,/^jac_fan_cache=light-upload-1;/);assert.match(marker,/HttpOnly; Secure; SameSite=Strict/);
 assert(!first.headers.get('Clear-Site-Data').includes('cookies'));assert(!first.headers.get('Clear-Site-Data').includes('storage'));
 const next=await m.worker.fetch(new Request('https://fans.example.invalid/cumple',{headers:{cookie:marker.split(';')[0]+'; __Host-jac_fan=synthetic-owner-cookie'}}),env,{});
 assert.equal(next.headers.get('Cache-Control'),'private, no-store');assert.equal(next.headers.get('Clear-Site-Data'),null);assert.equal(next.headers.get('Set-Cookie'),null,'A repeat visit preserves cookies and avoids evicting fresh assets again.');
 const previous=await m.worker.fetch(new Request('https://fans.example.invalid/cumple',{headers:{cookie:'jac_fan_cache=internal-access-2'}}),env,{});assert.equal(previous.headers.get('Clear-Site-Data'),'"cache"');assert.match(previous.headers.get('Set-Cookie'),/^jac_fan_cache=light-upload-1;/,'Visitors with the preceding interface must also receive fresh assets.');
 const image=await m.worker.fetch(new Request('https://fans.example.invalid/cumpleanos/master-v1.png'),env,{});assert.match(image.headers.get('Cache-Control'),/immutable/);assert.equal(image.headers.get('Clear-Site-Data'),null);
 assert.equal(new URL(calls[0]).pathname,'/cumpleanos/');
});
