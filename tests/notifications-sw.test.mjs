import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createContext,runInContext} from 'node:vm';
const source=await readFile('public/jac-push-sw.js','utf8');
const offlineSource=await readFile('public/jac-music-offline.js','utf8');
function fixture(){const listeners={},notices=[],opened=[];let windows=[];const self={location:{origin:'https://fixture.example.invalid'},addEventListener:(type,callback)=>listeners[type]=callback,skipWaiting:async()=>{},registration:{showNotification:async(title,options)=>notices.push({title,options})},clients:{claim:async()=>{},matchAll:async()=>windows,openWindow:async url=>opened.push(url)}};const publicRequests=[];const caches={open:async()=>({addAll:async requests=>publicRequests.push(...requests)}),match:async()=>new Response('offline shell')};const fetch=async()=>new Response('public shell');
 const context=createContext({self,URL,TextEncoder,TextDecoder,Request:class extends Request{constructor(input,options){super(new URL(input,self.location.origin),options);}},Response,caches,fetch,importScripts:path=>{assert.equal(path,'/jac-music-offline.js');runInContext(offlineSource,context);}});runInContext(source,context);return {listeners,notices,opened,publicRequests,setWindows:value=>windows=value};}
const id='33333333-3333-4333-8333-333333333333';
test('service worker muestra título y descripción recibidos, sin guardar ni interceptar API/PDF',async()=>{
 const f=fixture();assert.deepEqual(Object.keys(f.listeners),['install','activate','fetch','push','notificationclick']);let task;
 f.listeners.push({data:{json:()=>({id,title:'Mensaje privado',body:'Datos privados',url:'https://untrusted.example.invalid'})},waitUntil:p=>task=p});await task;
 assert.equal(f.notices.length,1);const notice=f.notices[0];assert.equal(notice.title,'Mensaje privado');assert.equal(notice.options.body,'Datos privados');assert.ok(!JSON.stringify(notice).includes('untrusted'));f.listeners.install({waitUntil:p=>task=p});await task;assert.deepEqual(f.publicRequests.map(r=>new URL(r.url).pathname),['/fotografia-offline.html','/jac-media-offline.js','/musica-offline.html','/jac-music-offline.js','/jac-music-offline-shell.js']);assert.ok(f.publicRequests.every(r=>r.credentials==='omit'));
 for(const path of ['/api/media/file?id=private','/api/media/offline','/fotografia','/payroll/print'])f.listeners.fetch({request:new Request('https://fixture.example.invalid'+path),respondWith:()=>assert.fail('Private content must never enter the service worker cache')});assert.equal(notice.options.data.id,id);assert.equal(notice.options.renotify,false);
 for(const value of ['https://untrusted.example.invalid','-'.repeat(36),'../archivo'])f.listeners.push({data:{json:()=>({id:value})},waitUntil:()=>assert.fail('ID no válido')});assert.equal(f.notices.length,1);
});
test('tocar el aviso abre únicamente JAC con su ID y reutiliza una ventana propia',async()=>{
 const f=fixture();let task,closed=0;const click=()=>f.listeners.notificationclick({notification:{data:{id,url:'https://untrusted.example.invalid'},close:()=>closed++},waitUntil:p=>task=p});
 click();await task;assert.deepEqual(f.opened,['https://fixture.example.invalid/?jac-notice='+id]);assert.equal(closed,1);
 let navigated,focused=false;f.setWindows([{url:'https://other.example.invalid/'},{url:'https://fixture.example.invalid/archivo',navigate:async url=>navigated=url,focus:async()=>focused=true}]);click();await task;assert.equal(navigated,f.opened[0]);assert.equal(focused,true);assert.equal(f.opened.length,1);
});

test('service worker conserva compatibilidad con envíos antiguos y valida el texto del aviso',async()=>{
 const f=fixture();let task;
 for(const data of [{id},{id,title:{bad:true},body:42},{id,title:'JAC',body:'Ya llegó tu itinerario para el día de hoy'}]){f.listeners.push({data:{json:()=>data},waitUntil:p=>task=p});await task;}
 assert.equal(f.notices[0].title,'JAC');assert.equal(f.notices[0].options.body,'Tienes un aviso nuevo. Abre JAC para consultarlo.');
 assert.equal(f.notices[1].title,'JAC');assert.equal(f.notices[1].options.body,f.notices[0].options.body);
 assert.equal(f.notices[2].options.body,'Ya llegó tu itinerario para el día de hoy');
 f.listeners.push({data:{json:()=>{throw new Error('invalid json');}},waitUntil:()=>assert.fail('No push without data')});assert.equal(f.notices.length,3);
});

test('fotografía abre la carpeta exacta en JAC, reutiliza la ventana y no confía en URLs del payload',async()=>{
 const f=fixture(),folderId='r2_77777777-7777-4777-8777-777777777777';let task,closed=0;
 f.listeners.push({data:{json:()=>({id,kind:'media_folder',folderId,title:'¡Nuevas fotos disponibles!',body:'Ya está disponible la carpeta «Evento».',url:'https://untrusted.example.invalid'})},waitUntil:p=>task=p});await task;
 const notice=f.notices[0];assert.equal(notice.title,'¡Nuevas fotos disponibles!');assert.equal(notice.options.body,'Ya está disponible la carpeta «Evento».');assert.equal(notice.options.data.folderId,folderId);assert.equal(notice.options.data.kind,'media_folder');assert.ok(!JSON.stringify(notice).includes('untrusted'));
 const click=()=>f.listeners.notificationclick({notification:{data:notice.options.data,close:()=>closed++},waitUntil:p=>task=p});click();await task;
 assert.deepEqual(f.opened,['https://fixture.example.invalid/fotografia?carpeta='+folderId]);assert.equal(closed,1);
 let navigated,focused=false;f.setWindows([{url:'https://fixture.example.invalid/agenda',navigate:async url=>navigated=url,focus:async()=>focused=true}]);click();await task;
 assert.equal(navigated,f.opened[0]);assert.equal(focused,true);assert.equal(f.opened.length,1);
});

test('fotografía rechaza destinos malformados tanto al mostrar como al tocar el aviso',()=>{
 const f=fixture();for(const folderId of [undefined,'jac_r2_root','../archivo','https://untrusted.example.invalid','r2_not-a-uuid',['r2_77777777-7777-4777-8777-777777777777']]){
  f.listeners.push({data:{json:()=>({id,kind:'media_folder',folderId})},waitUntil:()=>assert.fail('No mostrar destinos no válidos')});
  f.listeners.notificationclick({notification:{data:{id,kind:'media_folder',folderId},close:()=>{}},waitUntil:()=>assert.fail('No navegar a destinos no válidos')});
 }assert.equal(f.notices.length,0);assert.equal(f.opened.length,0);
});
