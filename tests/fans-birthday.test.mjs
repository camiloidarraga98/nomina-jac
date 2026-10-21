import test,{beforeEach,mock} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {build} from 'esbuild';
import {readFile,readdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

// All identities, pictures, storage and provider responses are synthetic.
const clock=Date.parse('2026-10-21T19:00:00Z');mock.timers.enable({apis:['Date'],now:clock});
globalThis.__birthdayEnv={};
const bundle=await build({stdin:{resolveDir:process.cwd(),contents:"export * from './lib/fans-birthday';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'birthday-isolation',setup(b){
 b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fixture'}));
 b.onResolve({filter:/^\.\/fans-birthday-image$/},()=>({path:'image',namespace:'fixture'}));
 b.onLoad({filter:/.*/,namespace:'fixture'},a=>({loader:'js',contents:a.path==='env'?'export const env=globalThis.__birthdayEnv;':"export const generateBirthdayPhoto=(...a)=>globalThis.__birthdayGenerate(...a);export const normalizeBirthdayUpload=(...a)=>globalThis.__birthdayNormalize(...a);"}));
}}]});
const dir=await mkdtemp(resolve('work/birthday-tests-'));await writeFile(dir+'/bundle.mjs',bundle.outputFiles[0].contents);const m=await import(pathToFileURL(dir+'/bundle.mjs'));await rm(dir,{recursive:true});
const migrations=await Promise.all((await readdir('drizzle')).filter(f=>f.endsWith('.sql')).sort().map(f=>readFile('drizzle/'+f,'utf8')));
const base='https://birthday.example.invalid',png=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jFZkAAAAASUVORK5CYII=','base64'));
let sql,objects,counts,onPut,onGet,onDelete,onRun,generateHook,normalizeHook,verifyHook;
class Query{
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 async first(){return sql.prepare(this.text).get(...this.args)??null;}
 async all(){return {results:sql.prepare(this.text).all(...this.args)};}
 async run(){const statement=sql.prepare(this.text),result=statement.columns().length?{results:statement.all(...this.args),meta:{changes:0}}:{results:[],meta:{changes:Number(statement.run(...this.args).changes)}};if(onRun)await onRun(this,result);return result;}
}
beforeEach(()=>{
 sql?.close();sql=new DatabaseSync(':memory:');for(const migration of migrations)sql.exec(migration);
 objects=new Map();counts={put:0,generate:0,normalize:0,verify:0,get:0};onPut=null;onGet=null;onDelete=null;onRun=null;generateHook=null;normalizeHook=null;verifyHook=null;mock.timers.setTime(clock);
 Object.assign(globalThis.__birthdayEnv,{DB:{prepare:text=>new Query(text)},BUCKET:{
  async put(key,bytes){counts.put++;objects.set(key,new Uint8Array(bytes));if(onPut)await onPut(key);},
  async get(key){counts.get++;if(onGet)await onGet(key);const bytes=objects.get(key);return bytes?{size:bytes.length,body:new Blob([bytes]).stream(),async arrayBuffer(){return bytes.slice().buffer;}}:null;},
  async delete(key){if(onDelete)await onDelete(key);objects.delete(key);}
 },PAYROLL_AUTH_KEY:'birthday-independent-fictitious-authentication-key',OPENAI_API_KEY:'fixture-openai-never-real',JAC_FANS_ENABLED:'1',JAC_FANS_TURNSTILE_SITE_KEY:'fixture-turnstile-public',JAC_FANS_TURNSTILE_SECRET:'fixture-turnstile-private'});
 globalThis.__birthdayNormalize=async(bytes,mime)=>{counts.normalize++;if(normalizeHook)return normalizeHook(bytes,mime);return {bytes:bytes.slice(),mimeType:mime};};
 globalThis.__birthdayGenerate=async(bytes,mime)=>{counts.generate++;if(generateHook)return generateHook(bytes,mime);return png.slice();};
 globalThis.fetch=async(input,options={})=>{assert.equal(String(input),'https://challenges.cloudflare.com/turnstile/v0/siteverify','No actual image provider or other network destinations may be used.');counts.verify++;assert.equal(options.redirect,'manual');assert.equal(options.method,'POST');assert.equal(options.body.get('secret'),'fixture-turnstile-private');if(verifyHook)return verifyHook();return Response.json({success:true,hostname:'birthday.example.invalid',action:'birthday-photo'});};
});
test.after(()=>sql?.close());
function request(method='GET',cookie='',query='',body,extra={}){return new Request(base+'/api/fans/cumpleanos'+query,{method,headers:{cookie,origin:base,'cf-connecting-ip':'192.0.2.1',...extra},...(body?{body}:{})});}
async function browser(){const response=await m.handleBirthdayApi(request());assert.equal(response.status,200);const cookie=response.headers.get('set-cookie').split(';')[0];return {cookie,config:await response.json(),headers:response.headers};}
function form(id=crypto.randomUUID(),photo=png,{adult='true',consent='true',token='fixture-human',filename='portrait.png',fileType='image/png'}={}){const data=new FormData();data.set('id',id);data.set('photo',new File([photo],filename,{type:fileType}));data.set('adult',adult);data.set('consent',consent);data.set('turnstileToken',token);return data;}
async function upload(cookie,{id=crypto.randomUUID(),photo=png,extra={},fields={}}={}){const response=await m.handleBirthdayApi(request('POST',cookie,'',form(id,photo,fields),extra));return {status:response.status,body:await response.json(),headers:response.headers,id};}
async function inspect(cookie,id,method='GET',tail=''){const response=await m.handleBirthdayApi(request(method,cookie,'?id='+id+tail));return {status:response.status,body:await response.json(),headers:response.headers};}
const dbJob=id=>sql.prepare('SELECT * FROM jac_fan_birthday_jobs WHERE id=?').get(id);
const deferred=()=>{let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};};

test('public configuration creates an isolated private browser cookie and never exposes credentials',async()=>{
 const b=await browser();assert.equal(b.config.enabled,true);assert.equal(b.config.retentionHours,24);assert.equal(b.config.turnstileSiteKey,'fixture-turnstile-public');assert.match(b.headers.get('set-cookie'),/^__Host-jac_fan=[\w-]{43}; Path=\/; HttpOnly; Secure; SameSite=Strict; Max-Age=86400$/);assert.match(b.headers.get('cache-control'),/private, no-store/);assert(!JSON.stringify(b.config).includes('fixture-openai'));assert(!JSON.stringify(b.config).includes('fixture-turnstile-private'));
 const refresh=await m.handleBirthdayApi(request('GET',b.cookie));assert.equal(refresh.headers.get('set-cookie').split(';')[0],b.cookie);assert.match(refresh.headers.get('set-cookie'),/Max-Age=86400/);
 for(const key of ['OPENAI_API_KEY','JAC_FANS_TURNSTILE_SECRET','PAYROLL_AUTH_KEY']){const old=globalThis.__birthdayEnv[key];delete globalThis.__birthdayEnv[key];assert.equal((await browser()).config.enabled,false);assert.equal((await upload(b.cookie)).status,503);globalThis.__birthdayEnv[key]=old;}
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,0);assert.equal(counts.generate,0);
});
test('upload validates consent, normalizes the photo, stores only a private source and reserves the queue',async()=>{
 const b=await browser(),r=await upload(b.cookie);assert.equal(r.status,202,r.body.error);assert.equal(r.body.job.status,'queued');assert.equal(counts.generate,0);assert.equal(counts.normalize,1);assert.equal(counts.verify,1);const job=dbJob(r.id);assert.equal(job.status,'queued');assert.match(job.owner_hash,/^[a-f0-9]{64}$/);assert.match(job.ip_hash,/^[a-f0-9]{64}$/);assert(!JSON.stringify(job).includes('192.0.2.1'));assert(!JSON.stringify(job).includes(b.cookie));assert.deepEqual(objects.get(job.source_key),png);assert.equal(job.result_key,'');assert.equal(Date.parse(job.expires_at)-Date.parse(job.created_at),24*3600_000);
});
test('API identifies HEIC from bytes despite missing or generic MIME, stores only JPEG and keeps retries idempotent',async()=>{
 const fixture=major=>{const bytes=new Uint8Array(36),view=new DataView(bytes.buffer),text=new TextEncoder();view.setUint32(0,24);bytes.set(text.encode('ftyp'),4);bytes.set(text.encode(major),8);bytes.set(text.encode('mif1'),16);bytes.set(text.encode(major==='mif1'?'heic':major),20);view.setUint32(24,12);bytes.set(text.encode('mdat'),28);return bytes;};
 const heic=fixture('heic'),jpeg=new Uint8Array([255,216,255,192,0,17,8,0,2,0,3,3,1,17,0,2,17,0,3,17,0,255,217]),b=await browser(),id=crypto.randomUUID();
 normalizeHook=async(bytes,mime)=>{assert.deepEqual(bytes,heic);assert.equal(mime,'image/heic');return {bytes:jpeg.slice(),mimeType:'image/jpeg'};};
 const first=await upload(b.cookie,{id,photo:heic,fields:{filename:'sin-extension',fileType:''}});assert.equal(first.status,202,first.body.error);let stored=dbJob(id);assert.equal(stored.source_mime,'image/jpeg');assert.deepEqual(objects.get(stored.source_key),jpeg);assert.notDeepEqual(objects.get(stored.source_key),heic);
 const before={...counts},retry=await upload(b.cookie,{id,photo:heic,fields:{filename:'extension-equivocada.mp4',fileType:'application/octet-stream'}});assert.equal(retry.status,202,retry.body.error);assert.equal(retry.body.job.id,id);assert.deepEqual(counts,before,'Changed filename/MIME does not duplicate a byte-identical HEIC attempt.');
 const second=await upload(b.cookie,{photo:heic,fields:{filename:'foto-no-es-png.png',fileType:'application/octet-stream'}});assert.equal(second.status,202,second.body.error);stored=dbJob(second.id);assert.equal(stored.source_mime,'image/jpeg');assert.deepEqual(objects.get(stored.source_key),jpeg);
 const normalized=counts.normalize;for(const bytes of [fixture('avif'),fixture('isom'),heic.subarray(0,12)])assert.equal((await upload(b.cookie,{photo:bytes,fields:{filename:'aparenta.HEIC',fileType:'image/heic'}})).status,415);
 assert.equal(counts.normalize,normalized,'Invalid BMFF containers stop before normalization or queue reservation.');assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,2);assert.equal(counts.generate,0);
 generateHook=async(bytes,mime)=>{assert.deepEqual(bytes,jpeg,'The image pipeline receives normalized JPEG, never the original HEIC.');assert.equal(mime,'image/jpeg');return png.slice();};await m.processBirthdayJobs();assert.equal(counts.generate,1);
});
test('reopening a closed tab recovers only its own unexpired attempt without another generation',async()=>{
 const owner=await browser(),other=await browser(),uploaded=await upload(owner.cookie);
 const config=async cookie=>(await (await m.handleBirthdayApi(request('GET',cookie))).json());
 assert.equal((await config(owner.cookie)).activeJobId,uploaded.id);
 assert.equal((await config(other.cookie)).activeJobId,'');
 await m.processBirthdayJobs();assert.equal((await config(owner.cookie)).activeJobId,uploaded.id);assert.equal(counts.generate,1);
 await inspect(owner.cookie,uploaded.id,'DELETE');assert.equal((await config(owner.cookie)).activeJobId,'');assert.equal(counts.generate,1);
});
test('same request ID recovers a lost POST response without another verification, upload or paid call',async()=>{
 const b=await browser(),id=crypto.randomUUID(),first=await upload(b.cookie,{id}),before={...counts};assert.equal(first.status,202);
 assert.equal(first.headers.get('set-cookie').split(';')[0],b.cookie,'Accepting a job refreshes the same browser capability for its 24-hour lifetime.');
 const retry=await upload(b.cookie,{id,fields:{token:'already-consumed'}});assert.equal(retry.status,202);assert.equal(retry.body.job.id,id);assert.deepEqual(counts,before);
 const changed=png.slice();changed[changed.length-1]^=1;assert.equal((await upload(b.cookie,{id,photo:changed})).status,409);assert.equal((await upload((await browser()).cookie,{id})).status,404);assert.equal(objects.size,1);assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,1);
});
test('invalid origins, absent browser, wrong consent and malformed images never reserve a job',async()=>{
 const b=await browser();assert.equal((await upload(b.cookie,{extra:{origin:'https://other.example.invalid'}})).status,403);assert.equal((await upload(b.cookie,{extra:{'sec-fetch-site':'cross-site'}})).status,403);assert.equal((await upload('')).status,403);
 for(const fields of [{adult:'false'},{consent:'false'}])assert.equal((await upload(b.cookie,{fields})).status,400);
 assert.equal((await upload(b.cookie,{photo:new TextEncoder().encode('<html>not an image</html>')})).status,415);
 normalizeHook=()=>{throw Error('Untrusted malformed decoder details');};assert.equal((await upload(b.cookie)).status,415);assert.equal(objects.size,0);assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,0);
});
test('Turnstile failures distinguish expired tokens, rejection, outages and configuration without consuming an attempt',async()=>{
 const b=await browser(),id=crypto.randomUUID(),required=await upload(b.cookie,{id,fields:{token:''}});
 assert.equal(required.status,403);assert.equal(required.body.code,'verification_required');assert.equal(counts.verify,0);
 const valid={success:true,hostname:'birthday.example.invalid',action:'birthday-photo'},diagnostic='fixture-provider-diagnostic-never-public';
 const cases=[
  ...['timeout-or-duplicate','missing-input-response'].map(code=>({name:code,status:403,code:'verification_expired',data:{success:false,'error-codes':[code]}})),
  ...['invalid-input-secret','missing-input-secret','bad-request'].map(code=>({name:code,status:503,code:'verification_configuration',data:{success:false,'error-codes':[code],detail:diagnostic}})),
  ...[{success:false},{success:false,'error-codes':['invalid-input-response']},{...valid,success:'true'},{...valid,success:1},{...valid,hostname:'other.example.invalid'},{...valid,action:'other-action'}].map((data,i)=>({name:'rejected-'+i,status:403,code:'verification_rejected',data})),
  {name:'network',status:503,code:'verification_unavailable',response:()=>{throw Error(diagnostic+' fixture-turnstile-private');}},
  {name:'redirect',status:503,code:'verification_unavailable',response:()=>new Response(null,{status:307,headers:{location:'https://evil.example.invalid'}})},
  {name:'http-error',status:503,code:'verification_unavailable',response:()=>new Response(diagnostic,{status:503})},
  {name:'malformed-json',status:503,code:'verification_unavailable',response:()=>new Response(diagnostic)},
  {name:'null-json',status:503,code:'verification_unavailable',data:null},
  {name:'internal-error',status:503,code:'verification_unavailable',data:{success:false,'error-codes':['internal-error'],detail:diagnostic}}
 ];
 for(const fixture of cases){
  verifyHook=fixture.response??(()=>Response.json(fixture.data));const r=await upload(b.cookie,{id});
  assert.equal(r.status,fixture.status,fixture.name);assert.equal(r.body.code,fixture.code,fixture.name);
  assert.equal(typeof r.body.error,'string');assert(!JSON.stringify(r.body).includes(diagnostic),fixture.name);assert(!JSON.stringify(r.body).includes('fixture-turnstile-private'),fixture.name);assert(!('error-codes' in r.body),fixture.name);
 }
 assert.equal(counts.normalize,0);assert.equal(counts.put,0);assert.equal(counts.generate,0);assert.equal(objects.size,0);assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,0);
 verifyHook=()=>Response.json(valid);const accepted=await upload(b.cookie,{id});assert.equal(accepted.status,202,accepted.body.error);assert.equal(counts.normalize,1);assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,1,'The same photo and request ID remain usable after correcting verification.');
});
test('oversized multipart bodies are rejected before reading or storing them',async()=>{
 const b=await browser(),r=await upload(b.cookie,{extra:{'content-length':String(m.BIRTHDAY_LIMITS.photoBytes+65537)}});assert.equal(r.status,413);assert.equal(counts.verify,0);assert.equal(counts.normalize,0);assert.equal(objects.size,0);
});
test('five browser attempts include cancelled jobs despite changing networks and reset only at midnight in Colombia',async()=>{
 const a=await browser(),first=await upload(a.cookie,{extra:{'cf-connecting-ip':'192.0.2.1'}});assert.equal(first.status,202);assert.equal((await inspect(a.cookie,first.id,'DELETE')).status,200);
 for(let i=2;i<=5;i++)assert.equal((await upload(a.cookie,{extra:{'cf-connecting-ip':'192.0.2.'+i}})).status,202);
 const before={...counts},blocked=await upload(a.cookie,{extra:{'cf-connecting-ip':'192.0.2.99'}});assert.equal(blocked.status,429);assert.equal(blocked.body.code,'daily_browser_limit');assert.deepEqual(counts,before,'An exhausted budget is detected before Turnstile or image decoding.');assert.equal(dbJob(first.id).status,'cancelled');assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,5);
 mock.timers.setTime(Date.parse('2026-10-22T00:00:01Z'));const sameDay=await upload(a.cookie,{extra:{'cf-connecting-ip':'192.0.2.99'}});assert.equal(sameDay.status,429,'Midnight UTC is still 19:00 in Colombia, so the budget must not reset.');assert.equal(sameDay.body.code,'daily_browser_limit');
 mock.timers.setTime(Date.parse('2026-10-22T05:00:01Z'));assert.equal((await upload(a.cookie,{extra:{'cf-connecting-ip':'192.0.2.99'}})).status,202,'The budget resets at midnight in Colombia.');
});
test('five connection attempts include cancelled jobs even when each request uses a different browser',async()=>{
 let first;for(let i=0;i<5;i++){const b=await browser(),r=await upload(b.cookie);assert.equal(r.status,202);if(i===0)first={...r,cookie:b.cookie};}
 assert.equal((await inspect(first.cookie,first.id,'DELETE')).status,200);const other=await browser(),before={...counts},blocked=await upload(other.cookie);
 assert.equal(blocked.status,429);assert.equal(blocked.body.code,'daily_ip_limit');assert.deepEqual(counts,before);assert.equal(dbJob(first.id).status,'cancelled');assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,5);assert.equal(sql.prepare('SELECT count(DISTINCT owner_hash) n FROM jac_fan_birthday_jobs').get().n,5);
});
test('simultaneous submissions cannot exceed the browser cap',async()=>{
 const b=await browser(),gate=deferred();let arrivals=0;normalizeHook=async bytes=>{if(++arrivals===6)gate.resolve();await gate.promise;return {bytes,mimeType:'image/png'};};
 const result=await Promise.all(Array.from({length:6},(_,i)=>upload(b.cookie,{extra:{'cf-connecting-ip':'192.0.2.'+(i+1)}})));assert.deepEqual(result.map(r=>r.status).sort(),[202,202,202,202,202,429]);assert.equal(result.find(r=>r.status===429).body.code,'capacity_limit');assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,5);assert.equal(objects.size,5);
});
test('global daily and waiting limits cannot be bypassed by changing browser or network',async()=>{
 const a=await browser(),first=await upload(a.cookie),seed=dbJob(first.id),columns=Object.keys(seed),insert=sql.prepare('INSERT INTO jac_fan_birthday_jobs('+columns.join(',')+') VALUES('+columns.map(()=>'?').join(',')+')');
 for(let i=1;i<25;i++){const fixture={...seed,id:crypto.randomUUID(),owner_hash:'synthetic-owner-'+i,ip_hash:'synthetic-ip-'+i,status:'failed',source_key:''};insert.run(...columns.map(k=>fixture[k]));}
 const other=await browser(),before={...counts},globalLimit=await upload(other.cookie,{extra:{'cf-connecting-ip':'198.51.100.1'}});assert.equal(globalLimit.status,429);assert.equal(globalLimit.body.code,'daily_global_limit');assert.deepEqual(counts,before);assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,25);
 sql.prepare("DELETE FROM jac_fan_birthday_jobs WHERE status='failed'").run();
 for(let i=1;i<10;i++){const fixture={...seed,id:crypto.randomUUID(),owner_hash:'queued-owner-'+i,ip_hash:'queued-ip-'+i,source_key:''};insert.run(...columns.map(k=>fixture[k]));}
 const queueLimit=await upload(other.cookie,{extra:{'cf-connecting-ip':'198.51.100.1'}});assert.equal(queueLimit.status,429);assert.equal(queueLimit.body.code,'queue_full');assert.deepEqual(counts,before);assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,10);assert.equal(counts.generate,0);
});
test('generation processes a durable request once, discards input, and requires ownership to view or download',async()=>{
 const b=await browser(),r=await upload(b.cookie);generateHook=async(bytes,mime)=>{assert.deepEqual(bytes,png);assert.equal(mime,'image/png');return png.slice();};await m.processBirthdayJobs();assert.equal(counts.generate,1);const job=dbJob(r.id);assert.equal(job.status,'ready');assert.equal(job.source_key,'');assert(objects.has(job.result_key));assert.equal(objects.size,1);
 assert.equal((await inspect((await browser()).cookie,r.id)).status,404);const image=await m.handleBirthdayApi(request('GET',b.cookie,'?id='+r.id+'&image=1&download=1'));assert.equal(image.status,200);assert.equal(image.headers.get('content-type'),'image/png');assert.match(image.headers.get('content-disposition'),/^attachment;/);assert.match(image.headers.get('cache-control'),/private, no-store/);assert.deepEqual(new Uint8Array(await image.arrayBuffer()),png);await m.processBirthdayJobs();assert.equal(counts.generate,1);
});
test('concurrent cron invocations run only one paid image generation globally',async()=>{
 const b=await browser();await upload(b.cookie);await upload(b.cookie);const entered=deferred(),finish=deferred();generateHook=async()=>{entered.resolve();await finish.promise;return png;};const first=m.processBirthdayJobs();await entered.promise;await m.processBirthdayJobs();assert.equal(counts.generate,1);assert.equal(sql.prepare("SELECT count(*) n FROM jac_fan_birthday_jobs WHERE status='processing'").get().n,1);finish.resolve();await first;assert.equal(counts.generate,1);generateHook=null;await m.processBirthdayJobs();assert.equal(counts.generate,2);
});
test('uncertain provider outcome is sanitized and is never retried automatically',async()=>{
 const b=await browser(),r=await upload(b.cookie);generateHook=()=>{throw Error('fixture-openai-never-real: private provider response');};await m.processBirthdayJobs();assert.equal(dbJob(r.id).status,'uncertain');assert.equal(objects.size,0);assert.equal(counts.generate,1);const state=await inspect(b.cookie,r.id);assert.equal(state.body.job.status,'uncertain');assert(!JSON.stringify(state.body).includes('fixture-openai'));await m.processBirthdayJobs();assert.equal(counts.generate,1);assert.equal(sql.prepare('SELECT count(*) n FROM jac_fan_birthday_jobs').get().n,1);
});
test('safe pre-provider failure is terminal without incurring a provider attempt',async()=>{
 const b=await browser(),r=await upload(b.cookie);objects.delete(dbJob(r.id).source_key);await m.processBirthdayJobs();assert.equal(counts.generate,0);assert.equal(dbJob(r.id).status,'failed');await m.processBirthdayJobs();assert.equal(counts.generate,0);
});
test('cancel during generation removes the source and prevents publishing the late result',async()=>{
 const b=await browser(),r=await upload(b.cookie);mock.timers.setTime(clock+1000);const second=await upload(b.cookie),entered=deferred(),finish=deferred();generateHook=async()=>{entered.resolve();await finish.promise;return png;};const process=m.processBirthdayJobs();await entered.promise;assert.equal((await inspect(b.cookie,r.id,'DELETE')).status,200);assert(dbJob(r.id).claim,'Cancellation keeps the running global lease.');await m.processBirthdayJobs();assert.equal(counts.generate,1);assert.equal(dbJob(second.id).status,'queued');finish.resolve();await process;assert.equal(dbJob(r.id).status,'cancelled');assert.equal(dbJob(r.id).claim,'');assert.equal(objects.size,1,'Only the second queued source remains.');assert.equal(counts.generate,1);assert.equal((await inspect(b.cookie,r.id)).body.job.status,'cancelled');generateHook=null;await m.processBirthdayJobs();assert.equal(counts.generate,2);assert.equal(dbJob(second.id).status,'ready');
});
test('lost final database acknowledgement preserves the ready image and never repeats the provider call',async()=>{
 const b=await browser(),r=await upload(b.cookie);let injected=false;onRun=async q=>{if(!injected&&q.text.includes("SET status='ready'")){injected=true;throw Error('Lost D1 response after commit');}};
 await m.processBirthdayJobs();assert.equal(dbJob(r.id).status,'ready');assert.equal(counts.generate,1);const response=await m.handleBirthdayApi(request('GET',b.cookie,'?id='+r.id+'&image=1'));assert.equal(response.status,200);await response.arrayBuffer();await m.processBirthdayJobs();assert.equal(counts.generate,1);assert.equal(objects.size,1);
});
test('uncertain R2 result acknowledgement is cleaned using its reserved deterministic key',async()=>{
 const b=await browser(),r=await upload(b.cookie);onPut=async key=>{if(key.includes('/result/'))throw Error('Lost result storage response after upload');};await m.processBirthdayJobs();assert.equal(dbJob(r.id).status,'uncertain');assert.equal(objects.size,0);await m.processBirthdayJobs();assert.equal(counts.generate,1);
});
test('cancel during source PUT retains its key until a late write with lost acknowledgement is reconciled',async()=>{
 const b=await browser(),id=crypto.randomUUID(),entered=deferred(),finish=deferred();onPut=async key=>{if(key.includes('/source/')){entered.resolve();await finish.promise;objects.set(key,png.slice());throw Error('Source committed after cancellation; response lost');}};
 const pending=upload(b.cookie,{id});await entered.promise;assert.equal((await inspect(b.cookie,id,'DELETE')).status,200);assert(dbJob(id).source_key);assert(dbJob(id).claim);await m.processBirthdayJobs();assert(dbJob(id).source_key,'A cron pass must not forget a still-running write.');finish.resolve();assert.equal((await pending).status,502);assert.equal(dbJob(id).status,'cancelled');assert.equal(dbJob(id).claim,'');assert.equal(dbJob(id).source_key,'');assert.equal(objects.size,0);assert.equal(counts.generate,0);
});
test('cancel during result PUT retains its key until a late write with lost acknowledgement is reconciled',async()=>{
 const b=await browser(),r=await upload(b.cookie),entered=deferred(),finish=deferred();onPut=async key=>{if(key.includes('/result/')){entered.resolve();await finish.promise;objects.set(key,png.slice());throw Error('Result committed after cancellation; response lost');}};
 const pending=m.processBirthdayJobs();await entered.promise;assert.equal((await inspect(b.cookie,r.id,'DELETE')).status,200);assert(dbJob(r.id).result_key);assert(dbJob(r.id).claim);finish.resolve();await pending;assert.equal(dbJob(r.id).status,'cancelled');assert.equal(dbJob(r.id).claim,'');assert.equal(dbJob(r.id).result_key,'');assert.equal(objects.size,0);assert.equal(counts.generate,1);
});
test('result read revalidates cancellation after private storage returns',async()=>{
 const b=await browser(),r=await upload(b.cookie);await m.processBirthdayJobs();onGet=async key=>{if(key.includes('/result/')){onGet=null;await inspect(b.cookie,r.id,'DELETE');}};const response=await m.handleBirthdayApi(request('GET',b.cookie,'?id='+r.id+'&image=1'));assert.equal(response.status,410);assert.equal(objects.size,0);
});
test('expiry removes photos even while generation is disabled and retains quota metadata for seven days',async()=>{
 const b=await browser(),r=await upload(b.cookie);await m.processBirthdayJobs();assert.equal(objects.size,1);globalThis.__birthdayEnv.JAC_FANS_ENABLED='0';mock.timers.setTime(clock+24*3600_000+1);assert.equal((await inspect(b.cookie,r.id)).status,410);await m.processBirthdayJobs();assert.equal(objects.size,0);assert(dbJob(r.id));mock.timers.setTime(clock+7*24*3600_000+1);await m.processBirthdayJobs();assert.equal(dbJob(r.id),undefined);
});
test('abandoned processing becomes uncertain without another provider request',async()=>{
 const b=await browser(),r=await upload(b.cookie);sql.prepare("UPDATE jac_fan_birthday_jobs SET status='processing',claim='fixture-abandoned',started_at=? WHERE id=?").run(new Date(clock-11*60000).toISOString(),r.id);await m.processBirthdayJobs();assert.equal(dbJob(r.id).status,'uncertain');assert.equal(counts.generate,0);assert.equal(objects.size,0);
});
test('failed private cleanup retains object keys so the following cron can finish deletion',async()=>{
 const b=await browser(),r=await upload(b.cookie);onDelete=()=>{throw Error('Temporary private storage outage');};await inspect(b.cookie,r.id,'DELETE');assert.equal(dbJob(r.id).status,'cancelled');assert(dbJob(r.id).source_key);assert.equal(objects.size,1);onDelete=null;await m.processBirthdayJobs();assert.equal(objects.size,0);assert.equal(dbJob(r.id).source_key,'');assert.equal(counts.generate,0);
});
