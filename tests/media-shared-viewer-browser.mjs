// Optional browser QA after npm run build: JAC_PLAYWRIGHT_MODULE and
// JAC_CHROMIUM_EXECUTABLE may select an installed browser environment.
// All media, links, accounts and downloads are disposable local fixtures.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,writeFile,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {build} from 'esbuild';
import {zipSync,unzipSync,strToU8} from 'fflate';
const {chromium}=await import(process.env.JAC_PLAYWRIGHT_MODULE||'playwright');
const directory=resolve('work/local/media-sharing-browser');
await writeFile(directory+'/guest.tsx',"import {createRoot} from 'react-dom/client';import SharedFolder from '../../../app/compartir/[token]/shared-folder';createRoot(document.getElementById('app')!).render(<SharedFolder token={'a'.repeat(43)}/>);");
await build({entryPoints:[directory+'/guest.tsx'],outdir:directory+'/guest-bundle',bundle:true,format:'esm',platform:'browser',jsx:'automatic',define:{'process.env.NODE_ENV':'\"development\"'}});
const builtCSS=await readdir('dist/client/assets'),globalCSS=builtCSS.find(name=>/^index-.*\.css$/.test(name)),sharedCSS=builtCSS.find(name=>/^shared-folder-.*\.css$/.test(name)),root={id:'r2_root',name:'17 Oct - Privado Palmira'},child={id:'r2_child',name:'Después del show'};
const make=(id,name,kind='image')=>({id,name,kind,mimeType:kind==='video'?'video/mp4':'image/jpeg',size:17,modifiedAt:'revision-1',thumbnailAvailable:false});
const photo=make('r2_photo','Escenario.jpg'),video=make('r2_video','Presentación.mp4','video'),last=make('r2_last','Final.jpg'),posts=[];let revoked=false;
const videoBytes=await readFile('tests/fixtures/shared-viewer-video.mp4');let delayPage=false;const pageRequests=[];
const server=createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost');
 const json=(data,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(data));};
 if(url.pathname==='/api/media/shared'){
  if(revoked)return json({error:'Enlace revocado'},410);
  if(url.searchParams.has('id')){const movie=url.searchParams.get('id')===video.id;res.writeHead(200,{'Content-Type':movie?'video/mp4':'image/svg+xml',...(movie?{'Content-Length':videoBytes.length}:{})});return res.end(movie?videoBytes:'<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="#0876b9"/><text x="50" y="200" font-size="36" fill="white">Escenario ficticio</text></svg>');}
  pageRequests.push(url.searchParams.get('pageToken'));if(delayPage&&url.searchParams.get('pageToken')==='last')await new Promise(done=>setTimeout(done,300));
  const nested=url.searchParams.get('folder')===child.id,page=url.searchParams.get('pageToken');return json({folder:nested?child:root,breadcrumbs:nested?[root,child]:[root],expiresAt:'2026-11-18T12:00:00Z',items:nested?[last]:page==='next'?[{...child,kind:'folder'}]:page==='last'?[last]:[{...child,kind:'folder'},photo,video],nextPageToken:nested||page==='last'?'':page==='next'?'last':'next'});
 }
 if(url.pathname==='/api/media/shared/download'){
  let body='';for await(const part of req)body+=part;const values=Object.fromEntries(new URLSearchParams(body)),selection=JSON.parse(values.selection);posts.push({...values,selection});
  const files=values.mode==='selected'?[photo,video,last].filter(item=>selection.some(s=>s.id===item.id)):values.mode==='photos'?[photo,last]:[photo,video,last];
  const zip=zipSync(Object.fromEntries(files.map(item=>[item.name,strToU8(item.id)])),{level:0});res.writeHead(200,{'Content-Type':'application/zip','Content-Disposition':'attachment; filename="recuerdos.zip"'});return res.end(zip);
 }
 if(url.pathname==='/'){res.writeHead(200,{'Content-Type':'text/html'});return res.end('<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/globals.css"><link rel="stylesheet" href="/shared.css"></head><body><main id="app"></main><script type="module" src="/guest.js"></script></body></html>');}
 const file=url.pathname==='/globals.css'?'dist/client/assets/'+globalCSS:url.pathname==='/shared.css'?'dist/client/assets/'+sharedCSS:url.pathname==='/guest.js'?directory+'/guest-bundle/guest.js':null;
 if(!file){res.writeHead(404);return res.end();}res.writeHead(200,{'Content-Type':file.endsWith('.css')?'text/css':'application/javascript'});res.end(await readFile(file));
});
await new Promise(done=>server.listen(0,'127.0.0.1',done));const base='http://127.0.0.1:'+server.address().port,browser=await chromium.launch({headless:true,...(process.env.JAC_CHROMIUM_EXECUTABLE?{executablePath:process.env.JAC_CHROMIUM_EXECUTABLE}:{}),args:['--no-sandbox']});
const context=await browser.newContext({viewport:{width:375,height:950},acceptDownloads:true}),page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await context.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());
async function download(button){
 const callbacks=[];let timeout;
 const pending=new Promise((resolve,reject)=>{const listen=p=>{p.on('download',resolve);callbacks.push(()=>p.off('download',resolve));};listen(page);context.on('page',listen);callbacks.push(()=>context.off('page',listen));timeout=setTimeout(()=>reject(Error('Download did not start')),15000);});
 try{await button.click();const item=await pending;assert.equal(item.suggestedFilename(),'recuerdos.zip');return unzipSync(await readFile(await item.path()));}finally{clearTimeout(timeout);callbacks.forEach(fn=>fn());}
}
// Exercise the minified route stylesheet: esbuild's raw guest.css previously
// hid a production-only double translation of the Radix dialog.
async function assertViewerFits(dialog){
 const layout=await dialog.evaluate(async element=>{
  await new Promise(done=>requestAnimationFrame(()=>requestAnimationFrame(done)));
  const rect=element.getBoundingClientRect(),controls=[...element.querySelectorAll('[data-slot="dialog-title"], [data-slot="dialog-close"], .jac-shared-viewer-navigation, footer a')];
  return {viewport:[innerWidth,innerHeight],rect:{left:rect.left,top:rect.top,right:rect.right,bottom:rect.bottom},center:[Math.abs(rect.left+rect.width/2-innerWidth/2),Math.abs(rect.top+rect.height/2-innerHeight/2)],controls:controls.map(control=>{const r=control.getBoundingClientRect();return {name:control.getAttribute('aria-label')||control.textContent,visible:r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight};})};
 });
 const [width,height]=layout.viewport;
 assert.ok(layout.rect.left>=0&&layout.rect.top>=0&&layout.rect.right<=width&&layout.rect.bottom<=height,JSON.stringify(layout));
 assert.ok(layout.center.every(offset=>offset<=1),JSON.stringify(layout));
 assert.ok(layout.controls.length>=4&&layout.controls.every(control=>control.visible),JSON.stringify(layout));
}
async function swipe(stage,from,to){await stage.evaluate((element,{from,to})=>{for(const [kind,point] of [['touchstart',from],['touchend',to]]){const touch=new Touch({identifier:1,target:element,clientX:point.x,clientY:point.y});element.dispatchEvent(new TouchEvent(kind,{bubbles:true,touches:kind==='touchstart'?[touch]:[],changedTouches:[touch]}));}},{from,to});}
try{
 await page.setViewportSize({width:1280,height:950});await page.goto(base);
 const first=page.getByRole('button',{name:'Abrir Escenario.jpg',exact:true});await first.waitFor();
 assert.equal(await page.locator('.jac-shared-checkbox').first().evaluate(e=>getComputedStyle(e).opacity),'0');
 await page.locator('#app').evaluate(element=>element.style.paddingTop='1400px');await first.scrollIntoViewIfNeeded();
 assert.ok(await page.evaluate(()=>scrollY>0));
 await first.click();const dialog=page.getByRole('dialog');await dialog.getByRole('heading',{name:photo.name,exact:true}).waitFor();
 for(const viewport of [{width:1280,height:950},{width:1920,height:1080},{width:1366,height:768},{width:375,height:667},{width:844,height:390}]){await page.setViewportSize(viewport);await assertViewerFits(dialog);}
 await page.setViewportSize({width:1366,height:768});await page.screenshot({path:directory+'/slideshow-desktop.png'});
 await page.setViewportSize({width:1280,height:950});
 assert.equal(await dialog.getByRole('button',{name:'Archivo anterior',exact:true}).isDisabled(),true);await page.keyboard.press('ArrowRight');await dialog.getByRole('heading',{name:video.name,exact:true}).waitFor();
 await assertViewerFits(dialog);
 await dialog.locator('video').evaluate(async v=>{window.__oldPaused=false;v.addEventListener('pause',()=>window.__oldPaused=true);await v.play();});
 const stage=dialog.locator('.jac-shared-viewer-stage');await swipe(stage,{x:250,y:200},{x:100,y:205});await dialog.getByRole('heading',{name:last.name,exact:true}).waitFor();
 assert.ok(await page.evaluate(()=>window.__oldPaused));assert.ok(pageRequests.includes('next')&&pageRequests.includes('last'));assert.equal(await dialog.getByRole('button',{name:'Archivo siguiente',exact:true}).isDisabled(),true);assert.ok((await dialog.getByRole('link',{name:'Descargar archivo',exact:true}).getAttribute('href')).includes('id='+last.id));
 await swipe(stage,{x:150,y:100},{x:155,y:300});assert.equal(await dialog.getByRole('heading',{name:last.name,exact:true}).count(),1);
 await page.keyboard.press('ArrowLeft');await dialog.getByRole('heading',{name:video.name,exact:true}).waitFor();await page.keyboard.press('ArrowLeft');await dialog.getByRole('heading',{name:photo.name,exact:true}).waitFor();
 await page.setViewportSize({width:375,height:950});await assertViewerFits(dialog);assert.ok(await dialog.evaluate(d=>{const r=d.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight&&getComputedStyle(d).backgroundColor==='rgb(255, 255, 255)';}));await page.screenshot({path:directory+'/slideshow-375.png'});await page.keyboard.press('Escape');assert.equal(await page.getByRole('dialog').count(),0);await page.locator('#app').evaluate(element=>element.style.paddingTop='');
 await page.setViewportSize({width:1280,height:950});await first.hover();await page.getByRole('checkbox',{name:'Seleccionar Escenario.jpg',exact:true}).check();await page.getByRole('checkbox',{name:'Seleccionar Presentación.mp4',exact:true}).check();await page.getByText('2 seleccionados',{exact:true}).waitFor();
 const selected=await download(page.getByRole('button',{name:'Descargar selección (2)',exact:true}));assert.equal(Object.keys(selected).length,2);assert.deepEqual(posts.at(-1).selection,[{id:photo.id,revision:'revision-1'},{id:video.id,revision:'revision-1'}]);await page.getByRole('button',{name:'Terminar selección',exact:true}).click();
 // Closing a viewer cancels a page still in flight and cannot append late media.
 delayPage=true;await page.reload();await page.getByRole('button',{name:'Abrir Presentación.mp4',exact:true}).click();await page.getByRole('button',{name:'Archivo siguiente',exact:true}).click();await page.getByRole('button',{name:'Cerrar visor',exact:true}).click();await page.waitForTimeout(400);assert.equal(await page.getByRole('button',{name:'Abrir Final.jpg',exact:true}).count(),0);delayPage=false;
 const mobile=await browser.newContext({viewport:{width:375,height:950},hasTouch:true,isMobile:true});await mobile.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());const touch=await mobile.newPage();touch.on('pageerror',e=>errors.push(e.message));
 try{
  await touch.goto(base);const card=touch.locator('.jac-shared-file').first();await card.waitFor();assert.equal(await card.locator('.jac-shared-checkbox').evaluate(e=>getComputedStyle(e).opacity),'0');await touch.screenshot({path:directory+'/compact-selection-375.png',fullPage:true});
  await card.dispatchEvent('pointerdown',{pointerType:'touch',isPrimary:true,clientX:100,clientY:800});await touch.getByText('1 seleccionado',{exact:true}).waitFor();await card.dispatchEvent('pointerup',{pointerType:'touch',isPrimary:true});await card.locator('button').dispatchEvent('click');assert.equal(await touch.getByRole('dialog').count(),0);assert.equal(await touch.getByRole('checkbox',{name:'Seleccionar Escenario.jpg',exact:true}).isChecked(),true);
  await touch.getByRole('button',{name:'Seleccionar Presentación.mp4',exact:true}).tap();await touch.getByText('2 seleccionados',{exact:true}).waitFor();await touch.getByRole('button',{name:'Terminar selección',exact:true}).tap();
  await card.dispatchEvent('pointerdown',{pointerType:'touch',isPrimary:true,clientX:100,clientY:700});await card.dispatchEvent('pointermove',{pointerType:'touch',isPrimary:true,clientX:100,clientY:730});await touch.waitForTimeout(520);assert.equal(await touch.getByText('1 seleccionado',{exact:true}).count(),0);
  await touch.getByRole('button',{name:'Abrir Escenario.jpg',exact:true}).tap();await touch.getByRole('dialog').waitFor();revoked=true;await touch.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await touch.getByText('Este enlace ya no está disponible.',{exact:true}).waitFor();assert.equal(await touch.getByRole('dialog').count(),0);
 }finally{await mobile.close();}
 assert.deepEqual(errors,[]);console.log('PASS: production CSS centers photo/video with visible controls on scrolled desktop/mobile/landscape pages; shared photo/video slideshow, swipe/keyboard, next-page traversal, video pause, close cancellation, hover group ZIP selection, mobile long press, scroll cancellation and revocation.');
}finally{await context.close();await browser.close();await new Promise(done=>server.close(done));}
