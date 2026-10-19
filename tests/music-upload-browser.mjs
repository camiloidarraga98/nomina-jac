// Focused upload regression: synthetic audio, local HTTP and intercepted storage.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,writeFile,readdir,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {build} from 'esbuild';
import {audioFixtures} from './music-audio-fixtures.mjs';
const {chromium}=await import(process.env.JAC_PLAYWRIGHT_MODULE||'playwright');
const fixtures=await audioFixtures(),directory=resolve('work/local/music-upload-browser');await mkdir(directory,{recursive:true});
const core=await build({stdin:{contents:"export * from './lib/music-core';",resolveDir:process.cwd()},bundle:true,format:'esm',platform:'node',write:false});const audio=await import('data:text/javascript;base64,'+Buffer.from(core.outputFiles[0].contents).toString('base64'));
await writeFile(directory+'/entry.tsx',"import {createRoot} from 'react-dom/client';import MusicPanel from '../../../app/music-panel';createRoot(document.getElementById('app')!).render(<MusicPanel active/>);");
await build({entryPoints:[directory+'/entry.tsx'],outdir:directory+'/bundle',bundle:true,format:'esm',platform:'browser',jsx:'automatic',define:{'process.env.NODE_ENV':'"development"'}});
const assets=await readdir('dist/client/assets'),globalCSS=assets.find(name=>/^index-.*\.css$/.test(name));assert(globalCSS,'Run npm run build before browser QA');
const gate=()=>{let release;const promise=new Promise(done=>{release=done;});return {promise,release};};
const transferGate=gate(),confirmationGate=gate();
const records=new Map(),starts=[],parts=[],completions=[];let lostReceipt=true;
const server=createServer(async(req,res)=>{try{
 const url=new URL(req.url,'http://localhost'),json=(body,status=200)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(body));};
 if(url.pathname==='/api/music')return json({tracks:[...records.values()].filter(r=>r.ready).map(r=>({id:r.id,section:r.section,title:r.filename.replace(/\.[^.]+$/,''),filename:audio.musicFilename(r.filename,r.mimeType),mimeType:r.mimeType,size:r.size,revision:r.id,createdAt:'2026-10-19'})),canUpload:true,canDelete:true,scope:'s'.repeat(43),key:Buffer.alloc(32,18).toString('base64url')});
 if(url.pathname==='/api/music/upload'){
  const chunks=[];for await(const b of req)chunks.push(b);const bytes=Buffer.concat(chunks);
  if(req.method==='PUT'){
   const r=records.get(url.searchParams.get('id'));assert(r);parts.push(r.filename);assert.equal(Number(url.searchParams.get('offset')),r.offset);
   if(r.filename==='Permiso revocado.mp3')return json({error:'Tu cuenta ya no puede subir audios.'},403);
   if(r.filename==='Ensayo largo.wav'&&r.offset===0)await transferGate.promise;
   const detected=r.offset?r.mimeType:audio.detectedAudioMime(bytes,r.size);if(!detected)return json({error:'No pudimos reconocer el audio de «'+r.filename+'».'},415);
   r.mimeType=detected;r.offset+=bytes.length;return json({...r,chunkSize:8*1024*1024});
  }
  const b=JSON.parse(bytes);if(b.action==='start'){
   starts.push(b.filename);const previous=records.get(b.id);
   if(previous){assert.equal(previous.filename,b.filename);assert.equal(previous.section,b.section);return json({...previous,chunkSize:8*1024*1024});}
   const record={...b,offset:0,ready:false,mimeType:audio.audioType(b.filename)};records.set(b.id,record);return json({...record,chunkSize:8*1024*1024});
  }
  if(b.action==='complete'){
   const r=records.get(b.id);assert.equal(r.offset,r.size);if(r.filename==='Ensayo largo.wav')await confirmationGate.promise;if(!r.ready){completions.push(r.id);r.ready=true;}
   if(r.filename==='Respuesta perdida.wav'&&lostReceipt){lostReceipt=false;return json({error:'No se recibió la confirmación. Reintenta.'},503);}
   return json({track:{id:r.id}});
  }
  return json({});
 }
 const map={'/global.css':resolve('dist/client/assets',globalCSS),'/entry.js':directory+'/bundle/entry.js','/entry.css':directory+'/bundle/entry.css','/jac-music-offline.js':resolve('public/jac-music-offline.js'),'/jac-push-sw.js':resolve('public/jac-push-sw.js'),'/jac-media-offline.js':resolve('public/jac-media-offline.js'),'/fotografia-offline.html':resolve('public/fotografia-offline.html'),'/musica-offline.html':resolve('public/musica-offline.html'),'/jac-music-offline-shell.js':resolve('public/jac-music-offline-shell.js')};
 if(url.pathname==='/'){res.writeHead(200,{'Content-Type':'text/html'});return res.end('<!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/global.css"><link rel="stylesheet" href="/entry.css"><body><div id="app"></div><script type="module" src="/entry.js"></script></body></html>');}
 const file=map[url.pathname];if(!file){res.writeHead(404);return res.end();}res.writeHead(200,{'Content-Type':file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html','Service-Worker-Allowed':'/'});res.end(await readFile(file));
 }catch(error){res.writeHead(500);res.end(error.message);}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,executablePath:process.env.JAC_CHROMIUM_EXECUTABLE||'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1360,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(base);await page.getByRole('button',{name:'Subir audios',exact:true}).waitFor();
 const input=page.locator('input[type=file]'),dialog=page.getByRole('dialog');
 await input.setInputFiles([{name:'Dañado.mp3',mimeType:'audio/mpeg',buffer:Buffer.alloc(128)},{name:'Pista recibida.wav',mimeType:'audio/wav',buffer:fixtures.mp3},{name:'Voz de estudio.mp3',mimeType:'audio/mpeg',buffer:fixtures.rf64}]);
 await dialog.getByLabel('Sección de destino').selectOption('tracks');await dialog.getByRole('button',{name:'Subir audios',exact:true}).click();
 await dialog.getByRole('button',{name:'Reintentar pendientes'}).waitFor();assert.equal(await dialog.locator('.music-imports li[data-state=complete]').count(),2);assert.equal(await dialog.locator('.music-imports li[data-state=error]').count(),1);assert.match(await dialog.locator('.music-import-error').textContent(),/Dañado.mp3/);assert(Number(await dialog.getByRole('progressbar').getAttribute('aria-valuenow'))<100,'Failed audio never produces false 100%');assert.match(await dialog.getByRole('alert').textContent(),/Se subieron 2 de 3/);assert.equal(completions.length,2);assert.equal([...records.values()].find(r=>r.filename==='Pista recibida.wav').mimeType,'audio/mpeg');assert.equal([...records.values()].find(r=>r.filename==='Voz de estudio.mp3').mimeType,'audio/wav');assert.equal([...records.values()].filter(r=>r.ready).every(r=>r.section==='tracks'),true);
 const readyIDs=[...records.values()].filter(r=>r.ready).map(r=>r.id);await dialog.getByRole('button',{name:'Reintentar pendientes'}).click();await page.waitForFunction(()=>document.querySelector('.music-import-error')&&document.querySelectorAll('.music-imports li[data-state=complete]').length===2&&document.querySelector('.music-imports button')?.disabled===false);assert.equal(completions.length,2);for(const name of ['Pista recibida.wav','Voz de estudio.mp3'])assert.equal(starts.filter(n=>n===name).length,1,'Successful files are never restarted');
 await dialog.getByRole('button',{name:'Quitar Dañado.mp3 del lote'}).click();await dialog.getByRole('button',{name:'Listo',exact:true}).click();await dialog.waitFor({state:'hidden'});
 await input.setInputFiles([{name:'Respuesta perdida.wav',mimeType:'audio/wav',buffer:fixtures.wav},{name:'Después del error.wav',mimeType:'audio/wav',buffer:fixtures.wav}]);await dialog.getByRole('button',{name:'Subir audios',exact:true}).click();await dialog.getByRole('button',{name:'Reintentar pendientes'}).waitFor();assert.equal(await dialog.locator('.music-imports li').count(),2);assert.equal(starts.includes('Después del error.wav'),false,'Service failures stop further writes');const receiptID=[...records.values()].find(r=>r.filename==='Respuesta perdida.wav').id;assert.equal(completions.filter(id=>id===receiptID).length,1);
 await dialog.getByRole('button',{name:'Reintentar pendientes'}).click();await dialog.getByRole('button',{name:'Listo',exact:true}).waitFor();assert.equal(await dialog.getByRole('progressbar').getAttribute('aria-valuenow'),'100');await dialog.getByRole('button',{name:'Listo',exact:true}).click();assert.equal(completions.length,4);assert.equal(completions.filter(id=>id===receiptID).length,1,'An uncertain completion is recovered without duplication');assert.deepEqual([...records.values()].filter(r=>r.ready).slice(0,2).map(r=>r.id),readyIDs);
 const large=Buffer.alloc(12*1024*1024);fixtures.wav.copy(large);
 await input.setInputFiles([{name:'Ensayo largo.wav',mimeType:'audio/wav',buffer:large},{name:'Calentamiento vocal — versión final para el show.mp3',mimeType:'audio/mpeg',buffer:fixtures.mp3},{name:'Armonías de estudio.wav',mimeType:'audio/wav',buffer:fixtures.wav}]);
 await dialog.getByLabel('Sección de destino').selectOption('warmup');
 assert.equal(await dialog.getByRole('progressbar').getAttribute('aria-valuenow'),'0');
 await page.screenshot({path:directory+'/upload-desktop-ready.png'});
 await dialog.getByRole('button',{name:'Subir audios',exact:true}).click();
 await page.waitForFunction(()=>Number(document.querySelector('[role=progressbar]')?.getAttribute('aria-valuenow'))>=60);
 const inFlight=Number(await dialog.getByRole('progressbar').getAttribute('aria-valuenow'));assert(inFlight<70,'Overall progress uses bytes, not file count');assert.equal(completions.length,4,'Transfer advances before server block acknowledgment');
 assert.equal(await dialog.locator('select').isDisabled(),true);await page.keyboard.press('Escape');assert.equal(await dialog.isVisible(),true,'Do not dismiss a running batch');
 await page.screenshot({path:directory+'/upload-desktop-progress.png'});
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:directory+'/upload-mobile-progress.png'});
 const layout=await dialog.evaluate(el=>{const box=el.getBoundingClientRect();return {left:box.left,right:box.right,width:innerWidth,scroll:el.scrollWidth,client:el.clientWidth};});assert(layout.left>=0&&layout.right<=layout.width&&layout.scroll<=layout.client+1,'Mobile upload dialog stays within viewport: '+JSON.stringify(layout));
 transferGate.release();await dialog.locator('li[data-state=confirming]').waitFor();assert(Number(await dialog.getByRole('progressbar').getAttribute('aria-valuenow'))<100,'Final confirmation is required before 100%');confirmationGate.release();
 await dialog.getByRole('button',{name:'Listo',exact:true}).waitFor();assert.equal(await dialog.getByRole('progressbar').getAttribute('aria-valuenow'),'100');assert.equal(await dialog.locator('li[data-state=complete]').count(),3);assert.equal(completions.length,7);await page.screenshot({path:directory+'/upload-mobile-complete.png'});await dialog.getByRole('button',{name:'Listo',exact:true}).click();
 await page.setViewportSize({width:1360,height:1000});
 await input.setInputFiles([{name:'Permiso revocado.mp3',mimeType:'audio/mpeg',buffer:fixtures.mp3},{name:'No intentar.wav',mimeType:'audio/wav',buffer:fixtures.wav}]);await dialog.getByRole('button',{name:'Subir audios',exact:true}).click();await dialog.getByRole('button',{name:'Reintentar pendientes'}).waitFor();assert.equal(starts.includes('No intentar.wav'),false,'Authorization failures stop the whole batch');assert.equal(completions.length,7);assert.deepEqual(errors,[]);
 console.log(JSON.stringify({passed:true,checks:['valid MP3 and RF64 after rejected file','actual content MIME','filename-specific errors','pending-only retries','remove invalid item','lost completion receipt recovery without duplicates','stop on service failure','stop on revoked authorization','real XHR progress before block acknowledgment','byte-weighted overall progress','100% requires final confirmation','completed rows retained','responsive desktop/mobile dialog','active batch cannot be dismissed']}));
}finally{transferGate.release();confirmationGate.release();await browser.close();await new Promise(r=>server.close(r));}
