import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';

test('Workerd consulta Google simulado y rechaza redirecciones sin reenviar credenciales',async()=>{
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {calendarGoogleFetch,calendarGooglePost} from './lib/calendar';
  export default {async fetch(req:Request){
   try{
    const path=new URL(req.url).pathname;
    if(path==='/token')return Response.json(await calendarGooglePost({client_id:'fixture.apps.googleusercontent.com',client_secret:'fixture-client-secret',code:'fixture-code',code_verifier:'fixture-verifier',grant_type:'authorization_code',redirect_uri:'https://fixture.example.invalid/callback'}));
    const urls={userinfo:'https://openidconnect.googleapis.com/v1/userinfo',calendars:'https://www.googleapis.com/calendar/v3/users/me/calendarList',events:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events',create:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events?sendUpdates=none',update:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events/fixture-event?sendUpdates=none',remove:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events/fixture-event?sendUpdates=none'};
    const url=urls[path.slice(1) as keyof typeof urls];if(!url)return new Response(null,{status:404});
    return Response.json(await (await calendarGoogleFetch(url,{method:path==='/create'?'POST':path==='/update'?'PATCH':path==='/remove'?'DELETE':'GET',headers:{Authorization:'Bearer fixture-calendar-token',...(['/update','/remove'].includes(path)?{'If-Match':'fixture-etag'}:{})},...(['/create','/update'].includes(path)?{body:JSON.stringify({summary:'Simulado'})}:{})})).json());
   }catch(e){return Response.json({error:e instanceof Error?e.message:'Error simulado'},{status:502});}
  }};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['node:*','cloudflare:*'],plugins:[{name:'no-request-context',setup(b){b.onResolve({filter:/^next\/headers$/},()=>({path:'headers',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:"export const headers=()=>{throw new Error('La prueba no usa sesiones ni datos reales.');};",loader:'js'}));}}]});
 let redirectStatus=0;const calls=[];
 const targets={token:'https://oauth2.googleapis.com/token',userinfo:'https://openidconnect.googleapis.com/v1/userinfo',calendars:'https://www.googleapis.com/calendar/v3/users/me/calendarList',events:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events',create:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events?sendUpdates=none',update:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events/fixture-event?sendUpdates=none',remove:'https://www.googleapis.com/calendar/v3/calendars/fixture%40example.invalid/events/fixture-event?sendUpdates=none'};
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,outboundService:async req=>{
  assert.ok(Object.values(targets).includes(req.url),'Todo el tráfico se intercepta; nunca se consulta un destino real o de redirección.');
  calls.push({url:req.url,authorization:req.headers.get('authorization'),method:req.method,body:await req.text()});
  if(redirectStatus)return new Response(null,{status:redirectStatus,headers:{location:'https://untrusted.example.invalid/collect'}});
  return Response.json({fixture:true,access_token:'fixture-calendar-token',scope:'https://www.googleapis.com/auth/calendar.events'});
 }});
 try{
  for(const path of Object.keys(targets)){
   const before=calls.length,response=await mf.dispatchFetch('https://local.example.invalid/'+path);
   assert.equal(response.status,200);assert.equal((await response.json()).fixture,true);assert.equal(calls.length,before+1);assert.equal(calls.at(-1).url,targets[path]);
   if(path==='token'){assert.equal(calls.at(-1).method,'POST');assert.equal(new URLSearchParams(calls.at(-1).body).get('code'),'fixture-code');assert.equal(calls.at(-1).authorization,null);}
   else assert.equal(calls.at(-1).authorization,'Bearer fixture-calendar-token');
   if(path==='remove')assert.equal(calls.at(-1).method,'DELETE');
   if(path==='create'||path==='update'){assert.equal(calls.at(-1).method,path==='create'?'POST':'PATCH');assert.equal(JSON.parse(calls.at(-1).body).summary,'Simulado');}
  }
  for(const status of [301,302,303,307,308]){
   redirectStatus=status;
   for(const path of Object.keys(targets)){
    const before=calls.length,response=await mf.dispatchFetch('https://local.example.invalid/'+path);
    assert.equal(response.status,502);assert.match((await response.json()).error,/redirección inesperada/);assert.equal(calls.length,before+1,'Solo se consulta el endpoint de Google; ninguna credencial se reenvía.');
   }
  }
 }finally{await mf.dispose();}
});
