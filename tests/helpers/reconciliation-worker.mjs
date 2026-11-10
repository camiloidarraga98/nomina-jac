import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {readFile,readdir} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';

// Only an isolated runtime uses this entry. No fixture routes enter the product.
export async function reconciliationFixture({readReceipt,workerBundle}={}){
 const compiled=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {env} from 'cloudflare:workers';
  import * as api from './app/api/reconciliation/[...path]/route';
  import {GET as view} from './app/crm/reconciliation/route';
  import {bootstrapOwner,makeSession} from './lib/payroll-auth-store';
  export default {async fetch(req:Request){
   globalThis.fixtureHeaders=req.headers;
   const path=new URL(req.url).pathname;
   if(path==='/fixture/dispatch'&&env.COMPILED_APP){
    // Drain the local HTTP upload before forwarding within Workerd. Otherwise
    // the Node transport can reset while an early 401/403 response is returned.
    const bytes=await req.arrayBuffer(),method=req.headers.get('x-fixture-method');
    return env.COMPILED_APP.fetch(new Request(req.headers.get('x-fixture-url'),{method,headers:JSON.parse(req.headers.get('x-fixture-headers')),...(!['GET','HEAD'].includes(method)?{body:bytes}:{})}));
   }
   if(path==='/fixture/setup'){
    const owner=await bootstrapOwner('reconciliation-fixture','only-a-synthetic-password'),token=await makeSession(owner);
    await env.DB.prepare("INSERT INTO jac_crm_shows (id,calendar_id,event_id,title,municipality,show_date,sale_cents,paid_cents,entrepreneur,created_at,updated_at) VALUES ('fixture-show','fixture-calendar','fixture-event','SHOW FICTICIO · PEREIRA','Pereira','2027-01-15',9000000000,100000000,'Empresario ficticio','fixture','fixture')").run();
    return Response.json({token,owner});
   }
   if(path==='/crm/reconciliation')return view(req);
   if(path.startsWith('/api/reconciliation/'))return api[req.method](req);
   return new Response('Not found',{status:404});
  }};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*'],plugins:[{name:'fixture-context',setup(b){b.onResolve({filter:/^next\/headers$/},()=>({path:'headers',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const headers=async()=>globalThis.fixtureHeaders;',loader:'js'}));}}]});
 let outgoing=0;
 const runtime={modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],d1Databases:{DB:'reconciliation-isolated'},r2Buckets:{BUCKET:'reconciliation-isolated'},bindings:{PAYROLL_AUTH_KEY:'reconciliation-fixture-not-a-production-secret',...(readReceipt?{OPENAI_API_KEY:'synthetic-ocr-fixture-key'}:{})},outboundService:request=>{outgoing++;if(readReceipt&&request.url==='https://api.openai.com/v1/responses')return readReceipt(request);throw Error('External network forbidden in tests.');}};
 const root=workerBundle?dirname(resolve(workerBundle)):null;
 const modules=root?[resolve(workerBundle),...(await readdir(root,{recursive:true})).filter(path=>path.endsWith('.js')).map(path=>resolve(root,path)).filter(path=>path!==resolve(workerBundle))].map(path=>({type:'ESModule',path})):null;
 const mf=new Miniflare(workerBundle?{workers:[{...runtime,name:'deployed-app',modules,modulesRoot:root,bindings:{...runtime.bindings,JAC_READY:'1',JAC_HOSTING:'cloudflare'},serviceBindings:{ASSETS:()=>new Response('Fixture assets not configured',{status:404})}},{...runtime,name:'fixture-setup',script:compiled.outputFiles[0].text,serviceBindings:{COMPILED_APP:'deployed-app'}}]}:{...runtime,script:compiled.outputFiles[0].text});
 try{
  const db=await mf.getD1Database('DB');
  for(const f of(await readdir('drizzle')).filter(f=>f.endsWith('.sql')).sort())for(const sql of(await readFile('drizzle/'+f,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(sql).run();
  const setup=workerBundle?await mf.getWorker('fixture-setup'):null;
  const {token,owner}=await(await(setup?setup.fetch('http://localhost/fixture/setup'):mf.dispatchFetch('http://localhost/fixture/setup'))).json();
  // Keep compiled-Worker requests separate from the setup worker, whose fixture
  // routes must never be used to claim verification of the hosting entry.
  const dispatchFetch=async(url,options)=>{
   if(!setup)return mf.dispatchFetch(url,options);
   const req=new Request(url,options);
   return setup.fetch('http://localhost/fixture/dispatch',{method:'POST',headers:{'x-fixture-url':req.url,'x-fixture-method':req.method,'x-fixture-headers':JSON.stringify(Object.fromEntries(req.headers))},body:new Uint8Array(await req.arrayBuffer())});
  };
  const request=async(path,{method='GET',data,authenticated=true}={})=>{
   const req=new Request('http://localhost'+path,{method,headers:{host:'localhost',origin:'http://localhost',...(authenticated?{cookie:'jac_session='+token}:{}),...(data&&!(data instanceof FormData)?{'Content-Type':'application/json'}:{})},...(data?{body:data instanceof FormData?data:JSON.stringify(data)}:{})});
   return dispatchFetch(req.url,{method,headers:Object.fromEntries(req.headers),...(req.body?{body:new Uint8Array(await req.arrayBuffer())}:{})});
  };
  return {mf,db,request,dispatchFetch,owner,token,outgoing:()=>outgoing,close:()=>mf.dispose()};
 }catch(error){await mf.dispose();throw error;}
}

export const syntheticImport=(count=296)=>({name:'MOVIMIENTOS FICTICIOS.xlsx',fileHash:'f'.repeat(64),rows:Array.from({length:count},(_,i)=>({sourceRow:i+2,sheet:'PRUEBA',date:`2026-11-${String(i%28+1).padStart(2,'0')}`,amount:1250000.25+i,description:'Consignación ficticia '+i,reference:'REF-'+i,thirdParty:'Tercero ficticio '+i,receipt:'RC-PRUEBA-'+i,invoice:i%2?'':'FV-PRUEBA-'+i,original:{CUENTA:'FICTICIA',MES:'NOVIEMBRE',FECHA:`${i%28+1}/11/2026`,'VALOR [D]':1250000.25+i,DETALLE:'Solo pruebas','LUGAR DEL SHOW':'Referencia original ficticia',RECIBO:'RC-PRUEBA-'+i,'TERCERO [H]':'Tercero ficticio '+i,'TERCERO [I]':'Ficticio','FAC.SIIGO':i%2?'':'FV-PRUEBA-'+i,'VALOR [K]':0}}))});
