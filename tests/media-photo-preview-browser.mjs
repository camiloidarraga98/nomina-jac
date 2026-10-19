// Focused viewer QA: synthetic JPEGs, intercepted local APIs, no production data.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {build} from 'esbuild';
const {chromium}=await import(process.env.JAC_PLAYWRIGHT_MODULE||'playwright');
const directory=resolve('work/local/photo-preview-browser');await mkdir(directory,{recursive:true});
const jpeg=edge=>execFileSync('ffmpeg',['-loglevel','error','-f','lavfi','-i',`testsrc2=s=${edge}x${Math.floor(edge*0.75)}`,'-frames:v','1','-f','image2pipe','-c:v','mjpeg','pipe:1'],{maxBuffer:4*1024*1024});
const preview=jpeg(2400),thumbnail=jpeg(360),root={id:'jac_r2_root',name:'Carpeta ficticia'};
const photos=['heic','jpeg'].map((extension,index)=>({id:'r2_'+String(index+1).repeat(8)+'-1111-4111-8111-111111111111',name:'Foto.'+extension,kind:'image',mimeType:'image/'+extension,size:1234567,createdAt:'2026-10-19T00:00:00Z',modifiedAt:'fixture-revision',thumbnailAvailable:true}));
const feed={connected:true,canRead:true,canUpload:false,canConnect:false,canDelete:false,provider:'r2',collectionID:'preview-fixture',root,folder:root,breadcrumbs:[root],items:photos,nextPageToken:'',expiresAt:'2026-11-19T00:00:00Z'};
await writeFile(directory+'/entry.tsx',`import {createRoot} from 'react-dom/client';import MediaPanel from '../../../app/media-panel';import SharedViewer from '../../../app/compartir/[token]/shared-viewer';const feed=${JSON.stringify(feed)};createRoot(document.getElementById('app')!).render(location.pathname==='/shared'?<SharedViewer token="fixture" initial={feed.items[0]} feed={feed} onPage={()=>{}} onRevoked={()=>{}} onClose={()=>{}}/>:<MediaPanel/>);`);
await build({entryPoints:[directory+'/entry.tsx'],outfile:directory+'/bundle.js',bundle:true,platform:'browser',format:'esm',jsx:'automatic',define:{'process.env.NODE_ENV':'"development"'}});
let failPreview=false;const requests=[];
const server=createServer(async(req,res)=>{
 const url=new URL(req.url,'http://fixture.invalid');requests.push(url.pathname+url.search);
 const json=(data,status=200)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'private, no-store'});res.end(JSON.stringify(data));};
 if(url.pathname==='/api/media')return json(feed);
 if(url.pathname==='/api/media/offline')return json({scope:Buffer.alloc(32,1).toString('base64url'),key:Buffer.alloc(32,2).toString('base64url')});
 if(['/api/media/file','/api/media/shared'].includes(url.pathname)){
  const item=photos.find(photo=>photo.id===url.searchParams.get('id'));if(!item)return json({error:'No disponible'},404);
  if(url.searchParams.get('metadata')==='1')return json({item});
  if(url.searchParams.get('preview')==='1'){
   if(failPreview)return json({error:'Vista previa pendiente'},503);
   res.writeHead(200,{'Content-Type':'image/jpeg','Content-Length':preview.length,'Cache-Control':'private, no-store'});return res.end(preview);
  }
  if(url.searchParams.get('thumbnail')==='1'){res.writeHead(200,{'Content-Type':'image/jpeg','Content-Length':thumbnail.length});return res.end(thumbnail);}
  return json({error:'Original bytes must never be requested by the viewer'},500);
 }
 if(['/','/shared'].includes(url.pathname)){res.writeHead(200,{'Content-Type':'text/html'});return res.end('<!doctype html><html lang="es"><head><meta charset="utf-8"><style>.media-thumbnail img{width:100px}.media-preview-stage img,.jac-shared-viewer-stage img{max-width:100%;max-height:65vh}button{min-height:35px}</style></head><body><div id="app"></div><script type="module" src="/bundle.js"></script></body></html>');}
 if(url.pathname==='/bundle.js'){res.writeHead(200,{'Content-Type':'text/javascript'});return res.end(await readFile(directory+'/bundle.js'));}
 res.writeHead(404);res.end();
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,...(process.env.JAC_CHROMIUM_EXECUTABLE?{executablePath:process.env.JAC_CHROMIUM_EXECUTABLE}:{})});
const context=await browser.newContext({viewport:{width:1280,height:900},serviceWorkers:'block'}),page=await context.newPage();
await context.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());
const errors=[];page.on('pageerror',error=>errors.push(error.message));
const originalReads=()=>requests.filter(value=>{const url=new URL(value,base);return ['/api/media/file','/api/media/shared'].includes(url.pathname)&&url.searchParams.has('id')&&!['preview','thumbnail','metadata'].some(key=>url.searchParams.has(key));});
async function displayed(selector){await page.waitForFunction(selector=>{const image=document.querySelector(selector);return image?.complete&&image.naturalWidth===2400;},selector);}
try{
 await page.goto(base);await page.getByRole('button',{name:'Abrir Foto.heic',exact:true}).click();await displayed('.media-preview-stage img');
 assert.ok(requests.some(value=>value.includes('preview=1')));assert.equal(originalReads().length,0);
 await page.keyboard.press('Escape');failPreview=true;const baseline=requests.length;
 await page.getByRole('button',{name:'Abrir Foto.jpeg',exact:true}).click();await page.locator('.media-preview-error').filter({hasText:'No pudimos cargar esta vista previa.'}).waitFor();
 assert.equal(requests.slice(baseline).some(value=>value.includes('thumbnail=1')),false,'Viewer failure must not enlarge a grid thumbnail');
 failPreview=false;await page.getByRole('button',{name:'Reintentar',exact:true}).click();await displayed('.media-preview-stage img');assert.equal(originalReads().length,0);
 await page.goto(base+'/shared');await displayed('.jac-shared-viewer-stage img');assert.ok(requests.some(value=>value.startsWith('/api/media/shared?')&&value.includes('preview=1')));
 failPreview=true;await page.reload();await page.getByText('No pudimos mostrar la vista previa.',{exact:false}).waitFor();
 failPreview=false;await page.getByRole('button',{name:'Reintentar',exact:true}).click();await displayed('.jac-shared-viewer-stage img');
 assert.equal(requests.filter(value=>value.startsWith('/api/media/shared?')&&value.includes('thumbnail=1')).length,0);assert.equal(originalReads().length,0);assert.deepEqual(errors,[]);
 await page.screenshot({path:directory+'/shared-preview.png'});console.log('PASS: private HEIC/JPEG previews, explicit retry, shared HEIC preview and retry; 2400px, no original or thumbnail fallback.');
}finally{await context.close();await browser.close();await new Promise(resolve=>server.close(resolve));}
