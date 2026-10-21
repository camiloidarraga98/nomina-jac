import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {readFile,readdir} from 'node:fs/promises';

test('Workerd validates real File/cookie/D1/R2 flow, idempotent generation and private deletion',async()=>{
 const png64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jFZkAAAAASUVORK5CYII=',png=Uint8Array.from(Buffer.from(png64,'base64'));
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {handleBirthdayApi,processBirthdayJobs} from './lib/fans-birthday';
  export default {async fetch(request:Request){const path=new URL(request.url).pathname;if(path==='/__fixture/process'){await processBirthdayJobs();return Response.json({generated:globalThis.__fixtureGenerated??0});}return handleBirthdayApi(request);}};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*'],plugins:[{name:'no-paid-image-service',setup(b){
  b.onResolve({filter:/^\.\/fans-birthday-image$/},()=>({path:'image',namespace:'fixture'}));
  b.onLoad({filter:/.*/,namespace:'fixture'},()=>({loader:'js',contents:`export async function normalizeBirthdayUpload(bytes,mimeType){return {bytes,mimeType};}export async function generateBirthdayPhoto(){globalThis.__fixtureGenerated=(globalThis.__fixtureGenerated??0)+1;return Uint8Array.from(atob('${png64}'),c=>c.charCodeAt(0));}`}));
 }}]});
 let verifications=0;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'birthday-worker-fixture'},r2Buckets:{BUCKET:'birthday-worker-private-fixture'},bindings:{PAYROLL_AUTH_KEY:'birthday-worker-independent-fictitious-authentication-key',OPENAI_API_KEY:'fixture-openai-only',JAC_FANS_ENABLED:'1',JAC_FANS_TURNSTILE_SITE_KEY:'fixture-public-site',JAC_FANS_TURNSTILE_SECRET:'fixture-secret-site',JAC_FANS_INTERNAL_CODE:'4826'},outboundService:async request=>{
  assert.equal(request.url,'https://challenges.cloudflare.com/turnstile/v0/siteverify','All external traffic must stay intercepted; there is no paid API access.');assert.equal(request.method,'POST');const data=await request.formData();assert.equal(data.get('secret'),'fixture-secret-site');assert.equal(data.get('response'),'fixture-human');verifications++;
  return Response.json({success:true,hostname:'birthday.example.invalid',action:'birthday-photo'});
 }});
 try{
  const db=await mf.getD1Database('DB'),bucket=await mf.getR2Bucket('BUCKET');
  for(const file of(await readdir('drizzle')).filter(f=>f.endsWith('.sql')).sort())for(const statement of(await readFile('drizzle/'+file,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
  const base='https://birthday.example.invalid',endpoint=base+'/api/fans/cumpleanos';
  const configuration=await mf.dispatchFetch(endpoint),config=await configuration.json(),cookie=configuration.headers.get('set-cookie').split(';')[0];
  assert.equal(config.enabled,true);assert.match(cookie,/^__Host-jac_fan=[\w-]{43}$/);assert.match(configuration.headers.get('set-cookie'),/HttpOnly; Secure; SameSite=Strict/);
  assert.equal(config.internalAvailable,true);assert.equal(config.internalMode,false);
  const id=crypto.randomUUID(),form=(submissionID=id)=>{const body=new FormData();body.set('id',submissionID);body.set('photo',new File([png],'fixture.png',{type:'image/png'}));body.set('consent','true');body.set('adult','true');body.set('turnstileToken','fixture-human');return body;};
  // Serialize through Node's native Request first: Miniflare's bundled Undici
  // does not recognize Node 24 FormData objects passed directly as its body.
  const submit=async(sessionCookie=cookie,submissionID=id)=>{const multipart=new Request(endpoint,{method:'POST',body:form(submissionID)});return mf.dispatchFetch(endpoint,{method:'POST',headers:{cookie:sessionCookie,Origin:base,'CF-Connecting-IP':'192.0.2.1','Content-Type':multipart.headers.get('content-type')},body:await multipart.arrayBuffer()});};
  let response=await submit(),body=await response.json();assert.equal(response.status,202,body.error);assert.equal(body.job.status,'queued');assert.equal(verifications,1);
  const stored=await db.prepare('SELECT * FROM jac_fan_birthday_jobs WHERE id=?').bind(id).first();assert.equal(stored.status,'queued');assert.equal(stored.claim,'');assert(!JSON.stringify(stored).includes('192.0.2.1'));assert.deepEqual(new Uint8Array(await (await bucket.get(stored.source_key)).arrayBuffer()),png);
  response=await mf.dispatchFetch(base+'/__fixture/process');body=await response.json();assert.equal(response.status,200);assert.equal(body.generated,1);
  const ready=await db.prepare('SELECT * FROM jac_fan_birthday_jobs WHERE id=?').bind(id).first();assert.equal(ready.status,'ready');assert.equal(ready.source_key,'');assert.equal(await bucket.get(stored.source_key),null);
  response=await mf.dispatchFetch(endpoint+'?id='+id+'&image=1&download=1',{headers:{cookie}});assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),'image/png');assert.match(response.headers.get('cache-control'),/private, no-store/);assert.match(response.headers.get('content-disposition'),/^attachment;/);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),png);
  const stranger=await mf.dispatchFetch(endpoint),otherCookie=stranger.headers.get('set-cookie').split(';')[0];assert.notEqual(otherCookie,cookie);response=await mf.dispatchFetch(endpoint+'?id='+id+'&image=1',{headers:{cookie:otherCookie}});assert.equal(response.status,404);
  response=await submit();body=await response.json();assert.equal(response.status,202,body.error);assert.equal(body.job.status,'ready');assert.equal(verifications,1);response=await mf.dispatchFetch(base+'/__fixture/process');assert.equal((await response.json()).generated,1);assert.equal((await db.prepare('SELECT count(*) AS n FROM jac_fan_birthday_jobs').first()).n,1);
  response=await mf.dispatchFetch(endpoint+'?id='+id,{method:'DELETE',headers:{cookie,Origin:base}});assert.equal(response.status,200);assert.equal((await response.json()).job.status,'cancelled');assert.equal(await bucket.get(ready.result_key),null);
  response=await mf.dispatchFetch(endpoint+'?id='+id+'&image=1',{headers:{cookie}});assert.equal(response.status,409);assert.equal((await db.prepare('SELECT count(*) AS n FROM jac_fan_birthday_jobs').first()).n,1,'Deleting the photo retains the quota record.');
  response=await mf.dispatchFetch(endpoint+'?internal=1',{method:'POST',headers:{cookie,Origin:base,'CF-Connecting-IP':'192.0.2.1','Content-Type':'application/json'},body:JSON.stringify({code:'4826'})});
  body=await response.json();assert.equal(response.status,200,body.error);assert.equal(body.internalMode,true);
  const internalHeader=response.headers.get('set-cookie');assert.match(internalHeader,/^__Host-jac_fan_internal=/);assert.match(internalHeader,/HttpOnly; Secure; SameSite=Strict/);assert.match(internalHeader,/Max-Age=28800/);
  const internalCookie=internalHeader.split(';')[0],sessionCookie=cookie+'; '+internalCookie;
  response=await mf.dispatchFetch(endpoint,{headers:{cookie:sessionCookie}});assert.equal((await response.json()).internalMode,true);
  response=await mf.dispatchFetch(endpoint,{headers:{cookie:otherCookie+'; '+internalCookie}});assert.equal((await response.json()).internalMode,false,'Internal access stays bound to the original anonymous owner.');
  const internalID=crypto.randomUUID();response=await submit(sessionCookie,internalID);body=await response.json();assert.equal(response.status,202,body.error);assert.equal(body.job.status,'queued');assert.equal(verifications,2,'Internal jobs still require Turnstile.');
  assert.equal((await db.prepare('SELECT internal_mode FROM jac_fan_birthday_jobs WHERE id=?').bind(internalID).first()).internal_mode,1);assert.equal(stored.internal_mode,0);
  const resetID=crypto.randomUUID(),reset=()=>mf.dispatchFetch(endpoint+'?internal-reset=1',{method:'POST',headers:{cookie:sessionCookie,Origin:base,'Content-Type':'application/json'},body:JSON.stringify({id:resetID})});
  response=await reset();body=await response.json();assert.equal(response.status,200,body.error);assert.equal(body.reset,true);assert.equal(body.quotaGeneration,1);const resetAt=body.resetAt;
  response=await reset();body=await response.json();assert.equal(body.quotaGeneration,1,'The same reset UUID never resets the quota twice.');assert.equal(body.resetAt,resetAt);
  response=await mf.dispatchFetch(endpoint,{headers:{cookie:otherCookie}});assert.equal((await response.json()).quotaGeneration,1,'The new quota generation is shared with every device.');
  assert.equal((await db.prepare('SELECT count(*) AS n FROM jac_fan_birthday_jobs').first()).n,2);assert.equal((await db.prepare('SELECT status FROM jac_fan_birthday_jobs WHERE id=?').bind(internalID).first()).status,'queued');assert.equal(verifications,2,'Resetting quotas never sends photos or starts a generation.');
  response=await mf.dispatchFetch(endpoint+'?internal=1',{method:'DELETE',headers:{cookie:sessionCookie,Origin:base}});assert.equal((await response.json()).internalMode,false);assert.match(response.headers.get('set-cookie'),/Max-Age=0/);
  assert.equal((await db.prepare('SELECT status FROM jac_fan_birthday_jobs WHERE id=?').bind(internalID).first()).status,'queued','Leaving internal mode never cancels or removes a photo.');
 }finally{await mf.dispose();}
});
