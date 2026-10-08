import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {renderToStaticMarkup} from 'react-dom/server';
const result=await build({stdin:{contents:"export * from './lib/payroll-navigation';export {default as Page} from './app/payroll-page';export {default as Section} from './app/[...section]/page';export {default as worker} from './worker/index';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,packages:'external',plugins:[{name:'local-navigation-fixtures',setup(b){b.onResolve({filter:/payroll-access$|payroll-store$|payroll-app$|next\/navigation$|vinext\/server\//},args=>({path:args.path,namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},({path})=>({contents:path.endsWith('payroll-access')?'export const payrollUser=async()=>globalThis.__navUser;':path.endsWith('payroll-store')?'export const readPayroll=async()=>{globalThis.__navReads++;return {data:{periods:[]},version:1};};':path.endsWith('payroll-app')?'export default function App(){return null;}':path==='next/navigation'?'export function notFound(){throw new Error("NOT_FOUND");}export function redirect(url){throw new Error("REDIRECT:"+url);}':path.endsWith('image-optimization')?'export const DEFAULT_DEVICE_SIZES=[],DEFAULT_IMAGE_SIZES=[];export const handleImageOptimization=()=>new Response();':'export default {fetch:async()=>new Response("fixture",{headers:{"X-Fixture":"local"}})};',loader:'js'}));}}]});
// File-based import keeps React package resolution local and avoids browser/network services.
const {mkdtemp,writeFile,rm}=await import('node:fs/promises');const {resolve}=await import('node:path');
const tmp=await mkdtemp(resolve('work/navigation-test-'));const file=resolve(tmp,'bundle.mjs');await writeFile(file,result.outputFiles[0].contents);const m=await import(file);await rm(tmp,{recursive:true});
const owner={displayName:'Fixture local',isOwner:true,username:'fixture',permissions:[]};
test('cada sección y pestaña tiene URL reversible; rutas desconocidas no se aceptan',()=>{
 for(const [view,path] of Object.entries(m.sectionPaths))assert.equal(m.payrollRoute(path).view,view);
 for(const [tab,path] of Object.entries(m.tabPaths))assert.deepEqual(m.payrollRoute(path),{view:'quincena',tab});
 assert.equal(m.payrollHref('agenda'),'/agenda');assert.equal(m.payrollHref('quincena','shows'),'/');
 const url=new URL(m.payrollHref('quincena','pagos','periodo / local'),'https://fixture.invalid');assert.equal(url.searchParams.get('periodo'),'periodo / local');
 for(const path of ['/otra','/agenda/otra','/api/borrar','//externo.invalid'])assert.equal(m.payrollRoute(path),null);
});
test('enlaces directos conservan sección, pestaña y período al renderizar en servidor',async()=>{
 globalThis.__navUser=owner;globalThis.__navReads=0;
 for(const path of new Set([...Object.values(m.sectionPaths),...Object.values(m.tabPaths)])){
 const page=await m.Section({params:Promise.resolve({section:path.split('/').filter(Boolean)}),searchParams:Promise.resolve({periodo:'local-fixture'})});
 const app=await m.Page(page.props);assert.deepEqual(app.props.initialRoute,m.payrollRoute(path));assert.equal(app.props.initialPeriodId,'local-fixture');
 }
 await assert.rejects(()=>m.Section({params:Promise.resolve({section:['desconocida']}),searchParams:Promise.resolve({})}),/NOT_FOUND/);
});
test('sin sesión no se lee nómina; login vuelve a la URL y Usuarios exige propietario',async()=>{
 globalThis.__navUser=null;globalThis.__navReads=0;
 const html=renderToStaticMarkup(await m.Page({route:m.payrollRoute('/agenda')}));assert.match(html,/href="\/acceso\?returnTo=%2Fagenda"/);assert.equal(globalThis.__navReads,0);
 globalThis.__navUser={...owner,isOwner:false};await assert.rejects(()=>m.Page({route:m.payrollRoute('/usuarios')}),/NOT_FOUND/);assert.equal(globalThis.__navReads,0);
 const app=await m.Page({route:m.payrollRoute('/personal')});assert.equal(app.props.access.isOwner,false);
});
test('todas las rutas de nómina conservan cabeceras de privacidad del Worker',async()=>{
 for(const path of new Set([...Object.values(m.sectionPaths),...Object.values(m.tabPaths)])){
 const response=await m.worker.fetch(new Request('https://fixture.invalid'+path),{},{});
 assert.equal(response.headers.get('Cache-Control'),'private, no-store, max-age=0');assert.equal(response.headers.get('X-Robots-Tag'),'noindex, nofollow');assert.equal(response.headers.get('Referrer-Policy'),'same-origin');assert.equal(response.headers.get('X-Content-Type-Options'),'nosniff');assert.equal(response.headers.get('X-Fixture'),'local');
 }
});
test('cuenta de solo itinerarios nunca renderiza ni consulta datos de nómina',async()=>{
 globalThis.__navUser={...owner,isOwner:false,itinerariesOnly:true};globalThis.__navReads=0;
 for(const view of ['quincena','personal','archivo','correos','reglas','usuarios','agenda'])await assert.rejects(()=>m.Page({route:{view,tab:'shows'}}),/REDIRECT:\/itinerarios/);
 for(const view of ['itinerarios','cuenta','notificaciones','configuracion']){const page=await m.Page({route:{view,tab:'shows'}});assert.deepEqual(page.props.initial.data.employees,[]);assert.deepEqual(page.props.initial.data.periods,[]);}
 assert.equal(globalThis.__navReads,0);
});
