import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {build} from 'esbuild';
const output=await build({stdin:{contents:"export * from './lib/agenda-cache';export * from './lib/calendar-core';export * from './lib/agenda-prefetch';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {AgendaCache,AGENDA_CACHE_KEY,AGENDA_SCOPE_KEY,agendaMonth,agendaWindowMonths,prefetchAgendaWindow}=await import('data:text/javascript;base64,'+Buffer.from(output.outputFiles[0].contents).toString('base64'));
const context={scope:'test-scope-A',key:Buffer.alloc(32,1).toString('base64url')};
function fixture(){const values=new Map(),storage={getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};return {values,storage,env:{storage,crypto:webcrypto},cache:new AgendaCache(context,{storage,crypto:webcrypto})};}
function data(month='2026-10',revision=2,title='Evento privado ficticio'){return {connection:{configured:true,connected:true,email:'calendar@example.invalid',selected:{id:'calendar-fixture',name:'Agenda ficticia',primary:false,timeZone:'America/Bogota'},revision,writeAuthorized:true},canEditEvents:true,...agendaMonth(month),today:'2026-10-13',events:[{id:'event-fixture',title,start:month+'-13',end:month+'-14',allDay:true,location:'Lugar ficticio',description:'Descripción privada',url:'',etag:'"fixture-v1"',editable:true,recurring:false}],upcoming:[],upcomingUntil:'2027-01-11',updatedAt:'2026-10-13T15:00:00.000Z',timeZone:'America/Bogota'};}
test('la copia real AES-GCM persiste, restaura por mes y siempre vuelve como consulta',async()=>{
 const f=fixture();assert.equal(await f.cache.write(data()),true);const raw=f.values.get(AGENDA_CACHE_KEY);for(const text of ['Evento privado','Descripción privada','calendar@example.invalid',context.key])assert.ok(!raw.includes(text));
 const restored=await new AgendaCache(context,f.env).read('2026-10');assert.equal(restored.events[0].title,'Evento privado ficticio');assert.equal(restored.canEditEvents,false);assert.equal(restored.events[0].editable,false);assert.equal(await f.cache.read('2026-11'),null);
});
test('otra cuenta/sesión, una clave incorrecta y bytes alterados no pueden restaurar la agenda',async()=>{
 const f=fixture();await f.cache.write(data());const original=f.values.get(AGENDA_CACHE_KEY);
 const bad=new AgendaCache({...context,key:Buffer.alloc(32,2).toString('base64url')},f.env);assert.equal(await bad.read('2026-10'),null);
 f.values.set(AGENDA_CACHE_KEY,original);const box=JSON.parse(original);box.cipher=box.cipher.slice(0,-4)+'AAAA';f.values.set(AGENDA_CACHE_KEY,JSON.stringify(box));assert.equal(await f.cache.read('2026-10'),null);
 await f.cache.write(data());const other=new AgendaCache({scope:'test-scope-B',key:Buffer.alloc(32,3).toString('base64url')},f.env);assert.equal(await other.read('2026-10'),null);assert.equal(await f.cache.read('2026-10'),null);assert.equal(await f.cache.write(data()),false);
});
test('conserva seis meses; nueva revisión/selección y desconexión descartan las copias anteriores',async()=>{
 const f=fixture();for(let month=1;month<=7;month++)await f.cache.write(data('2026-'+String(month).padStart(2,'0')));
 assert.equal(await f.cache.read('2026-01'),null);assert.ok(await f.cache.read('2026-02'));
 const changed=data('2026-08',3);changed.connection.selected.id='other-calendar';await f.cache.write(changed);assert.equal(await f.cache.read('2026-07'),null);assert.equal((await f.cache.read('2026-08')).connection.selected.id,'other-calendar');
 assert.equal(await f.cache.write(data('2026-10',2)),false);
 const disconnected=data('2026-08',4);disconnected.connection.connected=false;disconnected.connection.selected=null;assert.equal(await f.cache.write(disconnected),false);assert.equal(await f.cache.read('2026-08'),null);assert.equal(await f.cache.write(changed),false);
});
test('una respuesta vieja o una operación criptográfica pendiente no reviven datos tras salir',async()=>{
 const f=fixture(),newer=data();newer.updatedAt='2026-10-13T16:00:00.000Z';newer.events[0].title='Versión nueva';await f.cache.write(newer);assert.equal(await f.cache.write(data()),false);assert.equal((await f.cache.read('2026-10')).events[0].title,'Versión nueva');
 let release,started;const began=new Promise(r=>started=r),gate=new Promise(r=>release=r);
 const crypto={getRandomValues:array=>webcrypto.getRandomValues(array),subtle:{importKey:(...a)=>webcrypto.subtle.importKey(...a),decrypt:(...a)=>webcrypto.subtle.decrypt(...a),encrypt:async(...a)=>{started();await gate;return webcrypto.subtle.encrypt(...a);}}};
 const pendingCache=new AgendaCache(context,{storage:f.storage,crypto});const writing=pendingCache.write(data('2026-11'));await began;let stopped=0;pendingCache.subscribe(()=>stopped++);pendingCache.invalidate();release();assert.equal(await writing,false);assert.equal(stopped,1);assert.equal(f.storage.getItem(AGENDA_CACHE_KEY),null);assert.equal(f.storage.getItem(AGENDA_SCOPE_KEY),null);
});
test('lectura pendiente no publica una copia invalidada y almacenamiento bloqueado no lanza errores',async()=>{
 const f=fixture();await f.cache.write(data());let release,started;const began=new Promise(r=>started=r),gate=new Promise(r=>release=r);
 const crypto={getRandomValues:a=>webcrypto.getRandomValues(a),subtle:{importKey:(...a)=>webcrypto.subtle.importKey(...a),decrypt:async(...a)=>{started();await gate;return webcrypto.subtle.decrypt(...a);}}};
 const c=new AgendaCache(context,{storage:f.storage,crypto}),reading=c.read('2026-10');await began;c.invalidate();release();assert.equal(await reading,null);
 const blocked=new AgendaCache(context,{storage:{getItem(){throw Error('blocked');},setItem(){throw Error('blocked');},removeItem(){throw Error('blocked');}},crypto:webcrypto});assert.equal(await blocked.read('2026-10'),null);assert.equal(await blocked.write(data()),false);
});

test('una selección nueva elimina la copia anterior aunque falle cifrar la nueva',async()=>{
 const f=fixture();await f.cache.write(data());const crypto={getRandomValues:a=>webcrypto.getRandomValues(a),subtle:{importKey:(...a)=>webcrypto.subtle.importKey(...a),decrypt:(...a)=>webcrypto.subtle.decrypt(...a),encrypt:async()=>{throw Error('simulated encryption failure');}}};
 const c=new AgendaCache(context,{storage:f.storage,crypto});assert.equal(await c.write(data('2026-11',3)),false);assert.equal(await f.cache.read('2026-10'),null);
});


test('ventana anticipada contiene el mes actual y cinco posteriores, incluso al cambiar de año',()=>{
 assert.deepEqual(agendaWindowMonths('2026-10'),['2026-10','2026-11','2026-12','2027-01','2027-02','2027-03']);assert.deepEqual(agendaWindowMonths('2026-12'),['2026-12','2027-01','2027-02','2027-03','2027-04','2027-05']);assert.throws(()=>agendaWindowMonths('2026-13'));
});
function prefetch(f,overrides={}){return prefetchAgendaWindow({first:'2026-10',revision:2,selected:'calendar-fixture',cache:f.cache,current:()=>true,now:()=>Date.parse(data().updatedAt),fetchMonth:async month=>data(month),...overrides});}
test('precarga cinco meses sin repetir el mes vigente y restaura los seis desde cifrado',async()=>{
 const f=fixture(),calls=[];await f.cache.write(data());assert.equal(await prefetch(f,{fetchMonth:async month=>{calls.push(month);return data(month);}}),'complete');assert.deepEqual(calls,['2026-11','2026-12','2027-01','2027-02','2027-03']);
 const restored=new AgendaCache(context,f.env);for(const month of agendaWindowMonths('2026-10'))assert.equal((await restored.read(month)).month,month);
 calls.length=0;assert.equal(await prefetch(f,{fetchMonth:async month=>{calls.push(month);return data(month);}}),'complete');assert.equal(calls.length,0);
});
test('prefetch actualiza copias vencidas pero no vuelve a descargar meses recientes',async()=>{
 const f=fixture(),calls=[];await prefetch(f);const now=()=>Date.parse(data().updatedAt)+16*60000;assert.equal(await prefetch(f,{now,fetchMonth:async month=>{calls.push(month);return {...data(month),updatedAt:new Date(now()).toISOString()};}}),'complete');assert.equal(calls.length,6);
 calls.length=0;await prefetch(f,{now,fetchMonth:async month=>{calls.push(month);return data(month);}});assert.equal(calls.length,0);
});
test('logout o navegación cancelada durante prefetch no guardan respuestas pendientes',async()=>{
 for(const action of ['logout','navigation','clear']){const f=fixture();await f.cache.write(data());let release,started,active=true;const began=new Promise(r=>started=r),gate=new Promise(r=>release=r),calls=[];
 const downloading=prefetch(f,{current:()=>active,fetchMonth:async month=>{calls.push(month);started();await gate;return data(month);}});await began;if(action==='logout')f.cache.invalidate();else if(action==='clear')f.cache.clearData();else active=false;release();assert.equal(await downloading,'stopped');assert.deepEqual(calls,['2026-11']);assert.equal(await f.cache.read('2026-11'),null);}
});
test('un cambio de calendario retira copias y una falla temporal no borra el mes disponible',async()=>{
 const f=fixture();await f.cache.write(data());await assert.rejects(prefetch(f,{fetchMonth:async()=>{throw new TypeError('simulated offline');}}),/offline/);assert.ok(await f.cache.read('2026-10'));
 assert.equal(await prefetch(f,{fetchMonth:async month=>data(month,3)}),'changed');assert.equal(await f.cache.read('2026-10'),null);assert.equal(await f.cache.read('2026-11'),null);
});
