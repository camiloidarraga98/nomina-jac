// Real web components, synthetic accounts/folders, loopback requests only.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {build} from 'esbuild';
const {chromium}=await import(process.env.JAC_PLAYWRIGHT_MODULE||'playwright');
const out=resolve('work/local/media-folder-notice-browser');await mkdir(out,{recursive:true});
const compiled=await build({stdin:{resolveDir:process.cwd(),sourcefile:'photo-notice-fixture.tsx',loader:'tsx',contents:`import {createRoot} from 'react-dom/client';import MediaPanel from './app/media-panel';import NotificationSettings from './app/notification-settings';createRoot(document.getElementById('app')!).render(location.pathname==='/fotografia'?<MediaPanel/>:<NotificationSettings userID="synthetic-media-user" owner={false} view="notificaciones"/>);`},bundle:true,write:false,platform:'browser',format:'iife',jsx:'automatic',define:{'process.env.NODE_ENV':'"production"'},plugins:[{name:'fixture-assets',setup(b){b.onLoad({filter:/\.css$/},()=>({contents:'',loader:'js'}));b.onResolve({filter:/\?url$/},a=>({path:a.path,namespace:'fixture-url'}));b.onLoad({filter:/.*/,namespace:'fixture-url'},()=>({contents:'export default "/unused-worker.js"',loader:'js'}));}}]});
const bundle=compiled.outputFiles.find(f=>f.path.endsWith('.js'))?.text??compiled.outputFiles[0].text;
const a='r2_77777777-7777-4777-8777-777777777777',b='r2_88888888-8888-4888-8888-888888888888',root={id:'jac_r2_root',name:'Archivo JAC'},names={[a]:'Concierto de muestra',[b]:'Segunda carpeta'};
const requests=[],posts=[],errors=[],external=[];let auth=200,noticeAuth=200,passed=false,assertions=0,browser,context;
const eq=(actual,expected,message)=>{assert.deepEqual(actual,expected,message);assertions++};
const server=createServer(async(req,res)=>{try{const u=new URL(req.url,'http://localhost');const json=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'private,no-store'});res.end(JSON.stringify(data))};
 if(u.pathname==='/fixture.js'){res.writeHead(200,{'Content-Type':'text/javascript'});return res.end(bundle)}
 if(u.pathname==='/fixture.css'){res.writeHead(200,{'Content-Type':'text/css'});return res.end(await readFile('app/media.css','utf8'))}
 if(u.pathname==='/favicon.ico'){res.writeHead(204);return res.end()}
 if(u.pathname==='/api/media'){
  requests.push(u.pathname+u.search);if(auth!==200)return json(auth,{error:auth===404?'La carpeta ya no está disponible.':'Acceso retirado.'});
  const id=u.searchParams.get('folder')||root.id,folder=id===root.id?root:{id,name:names[id]||'Carpeta inválida'};
  return json(200,{connected:true,canRead:true,canUpload:false,canDelete:false,canConnect:false,provider:'r2',root,folder,breadcrumbs:id===root.id?[root]:[root,folder],items:[],nextPageToken:null});
 }
 if(u.pathname==='/api/notices'){
  requests.push(u.pathname+u.search);if(noticeAuth!==200)return json(noticeAuth,{error:'Acceso retirado.'});
  if(req.method==='POST'){let raw='';for await(const chunk of req)raw+=chunk;posts.push(JSON.parse(raw));return json(200,{ok:true})}
  assert.equal(u.searchParams.get('push'),'1','Media-only setup must use the small push settings endpoint');return json(200,{settings:{webPublicKey:'BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'}});
 }
 if(u.pathname==='/fotografia'||u.pathname==='/configuracion/notificaciones'){res.writeHead(200,{'Content-Type':'text/html'});return res.end('<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/fixture.css"><body><div id="app"></div><script src="/fixture.js"></script></body></html>')}
 if(u.pathname==='/acceso'){res.writeHead(200,{'Content-Type':'text/html'});return res.end('<h1>Acceso de muestra</h1>')}
 throw new Error('Unexpected local request: '+req.url);
 }catch(e){errors.push(String(e));res.writeHead(500);res.end('Fixture error')}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;
try{
 browser=await chromium.launch({headless:true,...(process.env.JAC_CHROMIUM_EXECUTABLE?{executablePath:process.env.JAC_CHROMIUM_EXECUTABLE}:{}),args:['--no-sandbox']});context=await browser.newContext({viewport:{width:1280,height:900}});context.setDefaultTimeout(9000);
 await context.route('**/*',route=>{const url=new URL(route.request().url());if(url.origin===origin)return route.continue();external.push(url.origin+url.pathname);return route.abort()});
 await context.addInitScript(()=>{class Notice{static permission='granted';static requestPermission=async()=>'granted'}Object.defineProperty(window,'Notification',{value:Notice});Object.defineProperty(window,'PushManager',{value:class{}});const subscription={toJSON:()=>({endpoint:'https://web.push.apple.com/synthetic-only',keys:{p256dh:'synthetic',auth:'synthetic'}}),unsubscribe:async()=>true};const registration={update:async()=>{},pushManager:{getSubscription:async()=>subscription,subscribe:async()=>subscription}};Object.defineProperty(navigator,'serviceWorker',{value:{register:async()=>registration,getRegistration:async()=>registration}})});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(origin+'/fotografia?carpeta='+a);await page.getByRole('heading',{name:names[a],exact:true}).waitFor();eq(requests.find(x=>x.startsWith('/api/media')),'/api/media?folder='+a,'A tap requests the exact folder as its first gallery read');eq(await page.getByRole('button',{name:'Subir fotos y videos',exact:true}).count(),0,'A read-only recipient gets no upload controls');
 await page.screenshot({path:out+'/desktop-folder.png',fullPage:true});
 await page.getByRole('button',{name:'Archivo JAC',exact:true}).click();await page.getByRole('heading',{name:'Shows y jornadas',exact:true}).waitFor();eq(new URL(page.url()).pathname+new URL(page.url()).search,'/fotografia','Breadcrumb navigation clears the deep link');
 await page.goBack();await page.getByRole('heading',{name:names[a],exact:true}).waitFor();eq(new URL(page.url()).search,'?carpeta='+a,'Back restores the exact folder');
 await page.goto(origin+'/fotografia?carpeta='+b);await page.getByRole('heading',{name:names[b],exact:true}).waitFor();await page.setViewportSize({width:390,height:844});await page.screenshot({path:out+'/phone-folder.png',fullPage:true});eq(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'The destination fits a phone viewport');
 await page.goto(origin+'/fotografia?carpeta='+encodeURIComponent('//evil.invalid'));await page.getByRole('heading',{name:'Shows y jornadas',exact:true}).waitFor();eq(requests.at(-1),'/api/media','An invalid notification destination is ignored');
 auth=404;await page.goto(origin+'/fotografia?carpeta='+a);await page.getByRole('alert').filter({hasText:'La carpeta ya no está disponible.'}).waitFor();eq(await page.getByRole('heading',{name:names[a],exact:true}).count(),0,'Deleted folders never appear as successfully opened');
 auth=401;await page.goto(origin+'/fotografia?carpeta='+a);await page.waitForURL('**/acceso?**');eq(new URL(page.url()).searchParams.get('returnTo'),'/fotografia?carpeta='+a,'Session expiry preserves the folder through login');
 auth=200;await page.goto(origin+'/configuracion/notificaciones');await page.getByText('Activadas en este navegador.',{exact:true}).waitFor();eq(posts.length,1,'Media-only browser setup binds exactly this device');eq(posts[0].action,'register','Only the existing registration contract is used');eq(requests.filter(x=>x==='/api/notices').length,1,'Media-only setup never requests the full notice feed');
 await page.getByRole('button',{name:'Desactivar en este navegador',exact:true}).click();await page.getByText('Desactivadas en este navegador.',{exact:true}).waitFor();eq(posts.at(-1).action,'unregister','Existing opt-out remains available');
 noticeAuth=403;await page.reload();await page.getByRole('alert').filter({hasText:'Tu sesión o tus permisos cambiaron.'}).waitFor();eq(await page.getByRole('button',{name:'Permitir notificaciones',exact:true}).count(),0,'Revocation removes permission actions');eq(external,[],'No production or provider traffic');eq(errors,[],'No runtime errors');passed=true;
}finally{await context?.close();await browser?.close();await new Promise(r=>server.close(r));const hashes={};for(const path of ['app/media-panel.tsx','app/payroll-page.tsx','app/[...section]/page.tsx','app/notification-settings.tsx','public/jac-push-sw.js','lib/payroll-navigation.ts','lib/media-notification-link.ts'])hashes[path]=createHash('sha256').update(await readFile(path)).digest('hex');await writeFile(out+'/report.json',JSON.stringify({status:passed?'passed':'failed',assertions,errors,external,requests,posts:posts.length,hashes,network:'loopback only'},null,2));}
console.log(JSON.stringify({passed,assertions,requests:requests.length,posts:posts.length}));
