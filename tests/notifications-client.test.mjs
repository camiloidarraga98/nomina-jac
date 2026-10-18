import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const bundle=await build({entryPoints:['lib/web-push-client.ts'],bundle:true,platform:'node',format:'esm',write:false});
const {WebPushClient}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
function fixture(){const saved=new Map(),calls=[];let permission='default',requested=0,release,delay=false;const env={permission:()=>permission,requestPermission:()=>{requested++;return Promise.resolve(permission='granted');},storage:{getItem:k=>saved.get(k)??null,setItem:(k,v)=>saved.set(k,v)},deviceID:()=> 'fixture-device',subscribe:async()=>{calls.push('subscribe');return {endpoint:'https://push.example.invalid'};},unsubscribe:async()=>{calls.push('unsubscribe');},post:async b=>{calls.push(b.action);if(delay&&b.action==='register')await new Promise(resolve=>release=resolve);}};return {env,saved,calls,get requested(){return requested;},grant:()=>permission='granted',deny:()=>{permission='denied';env.requestPermission=async()=>{requested++;return 'denied';};},delay:()=>delay=true,release:()=>release(),client:id=>new WebPushClient(id,env)};}
test('login solo vuelve a registrar permisos concedidos; solicitar permiso conserva el gesto del botón',async()=>{
 const f=fixture(),c=f.client('a');assert.equal(await c.bind('key'),false);assert.equal(f.requested,0);const enabling=c.enable('key');assert.equal(f.requested,1);assert.equal(await enabling,true);assert.deepEqual(f.calls,['subscribe','register']);assert.equal(f.saved.get(c.preferenceKey),'enabled');
});
test('desactivar persiste, no se revierte al volver a entrar y no cambia la preferencia de otra cuenta',async()=>{
 const f=fixture();f.grant();const c=f.client('a');assert.equal(await c.bind('key'),true);await c.disable();assert.equal(await f.client('a').bind('key'),false);assert.equal(await f.client('b').bind('key'),true);assert.deepEqual(f.calls,['subscribe','register','unregister','unsubscribe','subscribe','register']);
});
test('desactivar espera un registro pendiente y deja la última operación del servidor en unregister',async()=>{
 const f=fixture();f.grant();f.delay();const c=f.client('a'),binding=c.bind('key');await new Promise(setImmediate);const disabling=c.disable();f.release();await Promise.all([binding,disabling]);assert.deepEqual(f.calls,['subscribe','register','unregister','unsubscribe']);assert.equal(await c.bind('key'),false);
});
test('rechazo y sesión desmontada no suscriben ni registran el navegador',async()=>{
 const f=fixture();f.deny();const c=f.client('a');assert.equal(await c.enable('key'),false);assert.deepEqual(f.calls,[]);
 f.grant();c.stop();assert.equal(await c.bind('key'),false);assert.deepEqual(f.calls,[]);
});
test('una suscripción pendiente no puede revivir avisos desactivados ni una sesión cerrada',async()=>{
 const f=fixture();f.grant();let release;f.env.subscribe=()=>new Promise(resolve=>release=()=>resolve({}));const c=f.client('a'),binding=c.bind('key');await new Promise(setImmediate);c.stop();release();assert.equal(await binding,false);assert.deepEqual(f.calls,[]);
});
