import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const source=await readFile('public/jac-push-sw.js','utf8');
function fixture(){const listeners={},notices=[],opened=[];let windows=[];const self={location:{origin:'https://fixture.example.invalid'},addEventListener:(type,callback)=>listeners[type]=callback,skipWaiting:async()=>{},registration:{showNotification:async(title,options)=>notices.push({title,options})},clients:{matchAll:async()=>windows,openWindow:async url=>opened.push(url)}};runInNewContext(source,{self,URL});return {listeners,notices,opened,setWindows:value=>windows=value};}
const id='33333333-3333-4333-8333-333333333333';
test('service worker muestra título y descripción recibidos, sin guardar ni interceptar API/PDF',async()=>{
 const f=fixture();assert.deepEqual(Object.keys(f.listeners),['install','push','notificationclick']);let task;
 f.listeners.push({data:{json:()=>({id,title:'Mensaje privado',body:'Datos privados',url:'https://untrusted.example.invalid'})},waitUntil:p=>task=p});await task;
 assert.equal(f.notices.length,1);const notice=f.notices[0];assert.equal(notice.title,'Mensaje privado');assert.equal(notice.options.body,'Datos privados');assert.ok(!JSON.stringify(notice).includes('untrusted'));await f.listeners.install();assert.equal(notice.options.data.id,id);assert.equal(notice.options.renotify,false);
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
