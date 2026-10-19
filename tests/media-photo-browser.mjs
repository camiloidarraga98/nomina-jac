// Optional browser QA: supply JAC_PLAYWRIGHT_MODULE/JAC_CHROMIUM_EXECUTABLE
// when Playwright is provided by the development environment. No remote hosts,
// real accounts, photos, cookies or service credentials are used.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {build} from 'esbuild';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const {chromium}=await import(process.env.JAC_PLAYWRIGHT_MODULE||'playwright');
const directory=resolve('work/local/photo-actions-browser');await mkdir(directory,{recursive:true});
const entry=directory+'/entry.tsx';
await writeFile(entry,"import {createRoot} from 'react-dom/client';import MediaPanel from '../../../app/media-panel';createRoot(document.getElementById('app')!).render(<MediaPanel/>);");
await build({entryPoints:[entry],outdir:directory+'/bundle',bundle:true,format:'esm',platform:'browser',jsx:'automatic',define:{'process.env.NODE_ENV':'"development"'}});
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64');
const previewJPEG=execFileSync('ffmpeg',['-loglevel','error','-f','lavfi','-i','color=c=blue:s=16x16','-frames:v','1','-f','image2pipe','-c:v','mjpeg','pipe:1']);
const root={id:'jac_r2_root',name:'Archivo ficticio'},revision='2026-10-18T12:00:00Z';
const photos=[1,2].map((n)=>({id:'r2_'+String(n).repeat(8)+'-1111-4111-8111-111111111111',name:n===1?'Uno.png':'Dos.png',kind:'image',mimeType:'image/png',size:png.length,createdAt:revision,modifiedAt:revision,thumbnailAvailable:true}));
let removed=new Set(),revoked=false,scope=Buffer.alloc(32,7).toString('base64url'),deleteCalls=0,administrator=true;
const requests=[];
const server=createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost');requests.push(req.url);
 function json(data,status=200){res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'private, no-store'});res.end(JSON.stringify(data));}
 if(url.pathname.startsWith('/api/')&&revoked)return json({error:'Sin acceso'},403);
 if(url.pathname==='/api/media/offline')return json({scope,key:Buffer.alloc(32,5).toString('base64url')});
 if(url.pathname==='/api/media'){
  if(req.method==='POST'){let body='';for await(const part of req)body+=part;const input=JSON.parse(body);assert.equal(input.action,'deleteFile');deleteCalls++;if(!administrator)return json({error:'Sin permiso'},403);assert.equal(input.revision,revision);removed.add(input.id);return json({id:input.id,parentId:root.id,name:'Uno.png',removed:1,complete:true});}
  return json({connected:true,canRead:true,canUpload:false,canConnect:false,canDelete:administrator,provider:'r2',collectionID:'jac-r2-browser-fixture',root,folder:root,breadcrumbs:[root],items:photos.filter(p=>!removed.has(p.id)),deletedFiles:[...removed],deletedFolders:[],pendingFileDeletions:[]});
 }
 if(url.pathname==='/api/media/file'){
  const item=photos.find(p=>p.id===url.searchParams.get('id'));if(!item||removed.has(item.id))return json({error:'Foto eliminada'},410);
  if(url.searchParams.has('metadata'))return json({item});
  if(url.searchParams.get('preview')==='1'){res.writeHead(200,{'Content-Type':'image/jpeg','Content-Length':previewJPEG.length});return res.end(previewJPEG);}
  res.writeHead(200,{'Content-Type':'image/png','Content-Length':png.length,'Cache-Control':'private, no-store'});return res.end(png);
 }
 let path;
 if(url.pathname==='/'){res.writeHead(200,{'Content-Type':'text/html'});return res.end('<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/entry.css"></head><body><main id="app"></main><script type="module" src="/entry.js"></script></body></html>');}
 if(['/entry.js','/entry.css'].includes(url.pathname))path=directory+'/bundle'+url.pathname;
 else if(['/jac-media-offline.js','/jac-push-sw.js','/fotografia-offline.html'].includes(url.pathname))path=resolve('public'+url.pathname);
 else {res.writeHead(404);return res.end();}
 res.writeHead(200,{'Content-Type':path.endsWith('.html')?'text/html; charset=utf-8':path.endsWith('.css')?'text/css':'application/javascript'});res.end(await readFile(path));
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,...(process.env.JAC_CHROMIUM_EXECUTABLE?{executablePath:process.env.JAC_CHROMIUM_EXECUTABLE}:{})});
const context=await browser.newContext({viewport:{width:1280,height:900}}),page=await context.newPage();
await context.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());
const errors=[];page.on('pageerror',e=>errors.push(e.message));
async function until(fn){for(let n=0;n<100;n++){if(await fn())return;await new Promise(r=>setTimeout(r,50));}throw Error('Browser condition timed out');}
async function moduleCall(fn){return page.evaluate(fn);}
try{
 await page.goto(base);await page.getByRole('button',{name:'Abrir Uno.png',exact:true}).waitFor();
 await page.getByRole('button',{name:'Abrir Uno.png',exact:true}).click();await until(()=>page.locator('.media-preview-stage img').evaluate(image=>image.complete&&image.naturalWidth>0));
 assert.ok(requests.some(url=>url.includes('preview=1')));assert.ok(!requests.some(value=>{const url=new URL(value,base);return url.pathname==='/api/media/file'&&!url.searchParams.has('thumbnail')&&!url.searchParams.has('preview')&&!url.searchParams.has('metadata');}));
 assert.equal(await page.locator('.media-file-caption').first().evaluate(element=>getComputedStyle(element).display),'none');
 assert.ok(await page.locator('.media-file-entry').first().evaluate(entry=>{const card=entry.querySelector('.media-file-card').getBoundingClientRect(),menu=entry.querySelector('summary').getBoundingClientRect();return menu.top>=card.top&&menu.bottom<=card.bottom&&entry.getBoundingClientRect().height<=card.height+1;}),'The options control stays over the image without a white strip below.');
 await page.keyboard.press('Escape');

 await page.getByLabel('Opciones de Uno.png',{exact:true}).click();
 const save=page.getByRole('button',{name:'Guardar sin conexión',exact:true}).first();await until(()=>save.isEnabled());await save.click();
 await page.getByText('Foto disponible sin conexión en este navegador.',{exact:true}).waitFor();
 assert.equal(await moduleCall(async()=>{const m=await import('/jac-media-offline.js');return (await m.listMediaOffline()).length;}),1);
 const stored=await moduleCall(async()=>{const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('jac-media-offline-v1');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});const tx=db.transaction(['vault','photos']);return new Promise(resolve=>{let key,photos;const a=tx.objectStore('vault').get('active'),b=tx.objectStore('photos').getAll();a.onsuccess=()=>key=a.result.key;b.onsuccess=()=>photos=b.result;tx.oncomplete=()=>resolve({extractable:key.extractable,algorithm:key.algorithm.name,plaintext:JSON.stringify(photos),count:photos.length});});});
 assert.equal(stored.extractable,false);assert.equal(stored.algorithm,'AES-GCM');assert.equal(stored.count,1);assert.ok(!stored.plaintext.includes('Uno.png'));
 // Cancel leaves the original; a confirmed operation removes only its ID.
 await page.getByRole('button',{name:'Eliminar foto',exact:true}).click();await page.getByRole('button',{name:'Cancelar',exact:true}).click();assert.equal(deleteCalls,0);
 await page.goto(base+'/fotografia-offline.html');await page.locator('article img').waitFor();assert.equal(await page.locator('article').count(),1);
 await context.setOffline(true);await page.reload();await page.getByText(/Sin conexión ·/).waitFor();await page.locator('article img').waitFor();
 await page.screenshot({path:directory+'/offline.png',fullPage:true});
 await page.close();const reopened=await context.newPage();await reopened.goto(base+'/fotografia-offline.html');await reopened.locator('article img').waitFor();
 assert.equal(await reopened.locator('article').count(),1,'An explicitly saved photo survives closing and reopening the page without network');
 const download=reopened.waitForEvent('download');await reopened.getByRole('link',{name:'Descargar foto',exact:true}).click();const file=await download;assert.equal(file.suggestedFilename(),'Uno.png');const downloaded=await readFile(await file.path());assert.equal(createHash('sha256').update(downloaded).digest('hex'),createHash('sha256').update(png).digest('hex'));
 // Reconnecting must check the server before displaying a revoked copy.
 revoked=true;await context.setOffline(false);await reopened.getByText(/Inicia sesión|ya no tienes acceso/).waitFor();await until(async()=>await reopened.locator('article').count()===0);
 const active=await reopened.evaluate(()=>localStorage.getItem('jac.media.offline.scope.v1'));assert.equal(active,null);
 revoked=false;await reopened.close();const live=await context.newPage();await live.goto(base);await live.getByRole('button',{name:'Abrir Uno.png',exact:true}).waitFor();
 await live.getByLabel('Opciones de Uno.png',{exact:true}).click();await live.getByRole('button',{name:'Eliminar foto',exact:true}).click();
 await live.getByRole('dialog').getByRole('button',{name:'Eliminar archivo',exact:true}).click();await live.getByText('Archivo eliminado.',{exact:true}).waitFor();
 assert.equal(deleteCalls,1);assert.equal(await live.getByRole('button',{name:'Abrir Uno.png',exact:true}).count(),0);assert.equal(await live.getByRole('button',{name:'Abrir Dos.png',exact:true}).count(),1);
 // The photographer keeps download/offline actions without the delete command.
 administrator=false;await live.reload();await live.getByLabel('Opciones de Dos.png',{exact:true}).click();assert.equal(await live.getByRole('button',{name:'Eliminar foto',exact:true}).count(),0);
 const download2=live.waitForEvent('download');await live.getByRole('link',{name:'Descargar foto',exact:true}).click();const second=await download2;assert.equal(second.suggestedFilename(),'Dos.png');assert.deepEqual(await readFile(await second.path()),png);
 await live.setViewportSize({width:390,height:844});
 await until(()=>live.getByRole('button',{name:'Guardar sin conexión',exact:true}).isEnabled());
 assert.ok(await live.evaluate(()=>{const menu=document.querySelector('.media-photo-menu').getBoundingClientRect();return document.documentElement.scrollWidth<=window.innerWidth&&menu.left>=0&&menu.right<=window.innerWidth;}),'The individual menu must fit a narrow browser');
 await live.screenshot({path:directory+'/individual-menu.png',fullPage:true});
 // Ciphertext tampering, account switches and logout during encryption cannot
 // expose an old photo or write it back into a newly cleared cache.
 await live.evaluate(async item=>{
  const m=await import('/jac-media-offline.js');await m.connectMediaOffline('jac-r2-browser-fixture');const blob=await m.fetchMediaPhoto(item);
  await m.saveMediaPhoto(item,blob,[],'jac-r2-browser-fixture');
  const db=await new Promise(resolve=>{const r=indexedDB.open('jac-media-offline-v1');r.onsuccess=()=>resolve(r.result);});
  await new Promise((resolve,reject)=>{const tx=db.transaction('bytes','readwrite'),store=tx.objectStore('bytes'),r=store.get(item.id);r.onsuccess=()=>{const record=r.result;new Uint8Array(record.data.cipher)[0]^=1;store.put(record);};tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});
  let refused=false;try{await m.readMediaPhoto(item.id);}catch{refused=true;}if(!refused)throw Error('Tampered ciphertext was not rejected');
  await m.saveMediaPhoto(item,blob,[],'jac-r2-browser-fixture');
 },photos[1]);
 scope=Buffer.alloc(32,9).toString('base64url');
 assert.equal(await live.evaluate(async()=>{const m=await import('/jac-media-offline.js');await m.connectMediaOffline('jac-r2-browser-fixture');return(await m.listMediaOffline()).length;}),0);
 const race=await live.evaluate(async item=>{
  const m=await import('/jac-media-offline.js'),blob=await m.fetchMediaPhoto(item),encrypt=crypto.subtle.encrypt.bind(crypto.subtle);let resume,entered;
  const started=new Promise(resolve=>{entered=resolve;}),pause=new Promise(resolve=>{resume=resolve;});let first=true;
  crypto.subtle.encrypt=(...args)=>{if(first){first=false;entered();return pause.then(()=>encrypt(...args));}return encrypt(...args);};
  try{const pending=m.saveMediaPhoto(item,blob,[],'jac-r2-browser-fixture').then(()=>false,()=>true);await started;await m.clearMediaOffline();resume();const refused=await pending;return{refused,count:(await m.listMediaOffline()).length};}
  finally{crypto.subtle.encrypt=encrypt;}
 },photos[1]);assert.deepEqual(race,{refused:true,count:0});
 assert.deepEqual(errors,[]);assert.ok(requests.every(url=>url.startsWith('/')));
 await writeFile(directory+'/report.json',JSON.stringify({passed:true,checks:['individual selection','encrypted IndexedDB with non-extractable key','cancel deletion','offline reload','offline page reopen','byte-identical download','revocation on reconnect','delete exactly one photo','photographer cannot delete','ciphertext tampering rejected','account isolation','logout during encryption'],requests:requests.length},null,2));
 console.log('Browser QA passed: individual actions, encrypted offline reload/reopen, original downloads, cancellation and revocation.');
}finally{await context.close();await browser.close();await new Promise(resolve=>server.close(resolve));}
