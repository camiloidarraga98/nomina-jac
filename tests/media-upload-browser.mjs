// Local browser regression for the real upload transport and React queue.
// All storage capabilities/data are synthetic and every foreign host is mocked.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {build} from 'esbuild';
const {chromium}=await import(process.env.JAC_PLAYWRIGHT_MODULE||'playwright');
const directory=resolve('work/local/media-upload-browser');await mkdir(directory,{recursive:true});
await writeFile(directory+'/entry.tsx',"import {createRoot} from 'react-dom/client';import MediaPanel from '../../../app/media-panel';const root=createRoot(document.getElementById('app')!);root.render(<MediaPanel/>);globalThis.unmountUploads=()=>root.unmount();");
await build({entryPoints:[directory+'/entry.tsx'],outdir:directory+'/bundle',bundle:true,minify:true,format:'esm',platform:'browser',jsx:'automatic',define:{'process.env.NODE_ENV':'"production"'}});
const transport=await build({entryPoints:['lib/media-upload-client.ts'],bundle:true,minify:true,format:'iife',globalName:'uploads',platform:'browser',write:false});
const storage='https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',etag='"'+'d'.repeat(32)+'"';
const safari='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15';
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64');
function capability(id='11111111-1111-4111-8111-111111111111'){
 const query=new URLSearchParams({uploadId:'fixture',partNumber:'1','X-Amz-Algorithm':'AWS4-HMAC-SHA256','X-Amz-Credential':'b'.repeat(32)+'/20261026/auto/s3/aws4_request','X-Amz-Date':'20261026T120000Z','X-Amz-Expires':'300','X-Amz-SignedHeaders':'content-length;content-type;host','X-Amz-Signature':'c'.repeat(64)});
 return storage+'/jac-fotografia/originals/'+id+'?'+query;
}
const server=createServer(async(req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname;
 if(path==='/transport.js'){res.setHeader('Content-Type','text/javascript');return res.end(transport.outputFiles[0].text);}
 if(path==='/entry.js'||path==='/entry.css'){res.setHeader('Content-Type',path.endsWith('.css')?'text/css':'text/javascript');return res.end(await readFile(directory+'/bundle'+path));}
 if(path==='/blocked')res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; frame-src 'self'; connect-src "+storage);
 res.setHeader('Content-Type','text/html');res.end('<!doctype html><html lang="es"><meta charset="utf-8"><body>'+(path==='/panel'?'<main id="app"></main><script type="module" src="/entry.js"></script>':'<script src="/transport.js"></script>')+'</body></html>');
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,...(process.env.JAC_CHROMIUM_EXECUTABLE?{executablePath:process.env.JAC_CHROMIUM_EXECUTABLE}:{})});
const checks=[];
async function direct(name,{webkit=false,blocked=false,redirect=false,abort=false}={}){
 const context=await browser.newContext(webkit?{userAgent:safari}:{});let puts=0,foreign=0,received;
 await context.route('**/*',async route=>{
  const request=route.request(),url=new URL(request.url());if(url.origin===base)return route.continue();
  if(url.origin!==storage){foreign++;return route.abort();}
  const headers={'access-control-allow-origin':'*','access-control-allow-methods':'PUT','access-control-allow-headers':'content-type','access-control-expose-headers':'ETag',ETag:etag};
  if(request.method()==='OPTIONS')return route.fulfill({status:204,headers});
  puts++;received=request.postDataBuffer();
  return route.fulfill({status:redirect?302:200,headers:{...headers,...(redirect?{Location:'https://attacker.invalid/bytes'}:{})},body:''});
 });
 const page=await context.newPage();
 if(webkit)await page.addInitScript(()=>{const create=document.createElement.bind(document);document.createElement=(tag,...args)=>{if(tag==='iframe')throw Error('WebKit compatibility must not create a transfer iframe');return create(tag,...args);};});
 try{
  await page.goto(base+(blocked?'/blocked':'/'));
  const result=await page.evaluate(async({url,abort})=>{
   const progress=[],controller=new AbortController();if(abort)controller.abort();
   try{const received=await uploads.sendMediaDirectChunk(url,'image/jpeg',new Blob([new Uint8Array(100000).fill(7)]),0,100000,controller.signal,(sent,continuous)=>progress.push({sent,continuous}));return{ok:true,received,progress,frames:document.querySelectorAll('iframe').length};}
   catch(error){return{ok:false,error:error.name,frames:document.querySelectorAll('iframe').length};}
  },{url:capability(),abort});
  assert.equal(result.ok,!redirect&&!abort);assert.equal(result.frames,0);assert.equal(puts,abort?0:1);assert.equal(foreign,0);
  if(result.ok){assert.deepEqual(result.received,{etag});assert.equal(result.progress.at(-1).sent,100000);assert.deepEqual(received,Buffer.alloc(100000,7));if(webkit||blocked)assert.equal(result.progress.at(-1).continuous,false);}
  checks.push(name);console.log('Passed: '+name);
 }finally{await context.close();}
}
async function panel(name,initialMode,count=1){
 const context=await browser.newContext({userAgent:safari});let mode=initialMode,puts=0,peak=0,inFlight=0,receipts=0;
 const operations=new Map(),startIDs=[],events=[];
 const root={id:'jac_r2_root',name:'Archivo ficticio'},folder={id:'r2_22222222-2222-4222-8222-222222222222',name:'Carpeta de prueba'};
 await context.route('**/*',async route=>{
  const request=route.request(),url=new URL(request.url());
  const json=(data,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(data)});
  if(url.origin===storage){
   const headers={'access-control-allow-origin':'*','access-control-allow-methods':'PUT','access-control-allow-headers':'content-type','access-control-expose-headers':'ETag',ETag:etag};
   if(request.method()==='OPTIONS')return route.fulfill({status:204,headers});
   const id=url.pathname.split('/').at(-1),row=operations.get(id);assert.ok(row);assert.deepEqual(request.postDataBuffer(),png);
   puts++;events.push('put');inFlight++;peak=Math.max(peak,inFlight);await new Promise(r=>setTimeout(r,80));inFlight--;
   if(mode==='fail'||mode==='revoke'||mode==='unmount')return route.abort();
   row.stored=true;
   if(mode==='lost-response')return route.abort();
   if(mode==='retry'&&puts===1){row.stored=false;return route.abort();}
   return route.fulfill({status:200,headers,body:''});
  }
  if(url.origin!==base)throw Error('Unexpected foreign host');
  if(url.pathname==='/api/media/offline')return json({scope:Buffer.alloc(32,7).toString('base64url'),key:Buffer.alloc(32,5).toString('base64url')});
  if(url.pathname==='/api/media')return mode==='revoke'&&events.includes('status')?json({error:'Acceso retirado'},403):json({connected:true,canRead:true,canUpload:true,canDelete:false,canConnect:false,provider:'r2',collectionID:'fixture',root,folder,breadcrumbs:[root,folder],items:[]});
  if(url.pathname==='/api/media/upload'){
   if(request.method()==='PUT')return json({ok:true}); // synthetic thumbnail/preview
   const body=request.postDataJSON();events.push(body.action);
   if(body.action==='start'){
    startIDs.push(body.id);if(!operations.has(body.id))operations.set(body.id,{size:body.size,stored:false});
   }
   const row=operations.get(body.id);assert.ok(row);
   if(body.action==='status'&&mode==='revoke')return json({error:'Acceso retirado'},403);
   if(body.partReceipt){assert.deepEqual(body.partReceipt,{partNumber:1,etag,size:row.size});assert.equal(row.stored,true);receipts++;if(mode==='lost-confirmation'&&!row.lostConfirmation){row.lostConfirmation=true;return route.abort();}}
   return json({id:body.id,provider:'r2',offset:row.stored?row.size:0,chunkSize:8*1024*1024,complete:row.stored,...(!row.stored?{uploadURL:capability(body.id)}:{})});
  }
  return route.continue();
 });
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 try{
  await page.goto(base+'/panel');await page.getByRole('button',{name:'Subir fotos y videos',exact:true}).click();
  await page.getByLabel('Seleccionar fotos y videos',{exact:true}).setInputFiles(Array.from({length:count},(_,n)=>({name:`Prueba-${n}.png`,mimeType:'image/png',buffer:png})));
  await page.getByRole('button',{name:`Subir ${count} ${count===1?'archivo':'archivos'}`,exact:true}).click();
  if(mode==='fail'){
   await page.getByRole('heading',{name:'Revisa los archivos pendientes',exact:true}).waitFor();assert.equal(puts,3);assert.equal(operations.size,1);
   assert.ok(!await page.getByText('La conexión se interrumpió.',{exact:false}).count());
   mode='ok';await page.getByText('Ver archivos',{exact:false}).click();await page.getByRole('button',{name:'Reintentar',exact:true}).click();
   await page.getByRole('heading',{name:'Archivos guardados',exact:true}).waitFor();assert.equal(puts,4);assert.equal(new Set(startIDs).size,1);assert.equal(operations.size,1);
  }else if(mode==='revoke'){
   await page.getByText('Tu cuenta ya no tiene acceso a la galería.',{exact:true}).waitFor();assert.equal(puts,1);
  }else if(mode==='unmount'){
   await page.waitForFunction(()=>document.querySelector('[data-testid="media.upload.speed"]')?.textContent.includes('Reintentando'));
   await page.evaluate(()=>unmountUploads());await page.waitForTimeout(1200);assert.equal(puts,1);
  }else{
   await page.getByRole('heading',{name:'Archivos guardados',exact:true}).waitFor();assert.equal(puts,mode==='retry'?2:count);assert.equal(operations.size,count);assert.ok(peak<=2);
   assert.equal(receipts,mode==='lost-response'?0:count);
   if(mode==='lost-response')assert.deepEqual(events,['start','put','status']);
   if(mode==='lost-confirmation')assert.deepEqual(events,['start','put','status','status']);
   if(mode==='retry')assert.deepEqual(events.slice(0,5),['start','put','status','put','status']);
   assert.equal(await page.getByRole('progressbar',{name:'Progreso general de subida'}).getAttribute('aria-valuenow'),'100');
  }
  assert.deepEqual(errors,[]);checks.push(name);console.log('Passed: '+name);
 }finally{await context.close();}
}
try{
 await direct('Chromium isolated progress and exact bytes');
 await direct('Safari compatibility without iframe and without fabricated speed',{webkit:true});
 await direct('Blocked srcdoc falls back before any PUT',{blocked:true});
 await direct('XHR never sends bytes to a foreign redirect',{redirect:true});
 await direct('Fetch rejects redirects',{webkit:true,redirect:true});
 await direct('Aborted upload never sends bytes',{abort:true});
 await direct('Aborted Safari fetch never sends bytes',{webkit:true,abort:true});
 await panel('Two simultaneous uploads with receipt and real completion','ok',2);
 await panel('Lost storage response is reconciled without another PUT','lost-response');
 await panel('Lost final confirmation is reconciled without another PUT','lost-confirmation');
 await panel('Transient failure retries the same part after status','retry');
 await panel('Bounded failure and manual retry preserve one operation','fail');
 await panel('Access revocation prevents retry','revoke');
 await panel('Unmount during backoff prevents retry','unmount');
 await writeFile(directory+'/report.json',JSON.stringify({passed:true,engine:'Chromium; Safari user-agent compatibility path (not actual Safari)',checks},null,2));
 console.log(`Upload browser QA passed: ${checks.length} checks; no real storage or users.`);
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
