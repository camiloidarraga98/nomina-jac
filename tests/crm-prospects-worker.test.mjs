import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {readFile,readdir} from 'node:fs/promises';

test('Workerd privately previews and queues individual proposals, streams the brochure once per recipient and preserves campaign idempotency',async()=>{
 const brochure='%PDF-1.4\nSYNTHETIC BROCHURE FOR ISOLATED TEST ONLY\n%%EOF';
 const output=await build({stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
  import {env} from 'cloudflare:workers';
  import {GET,POST} from './app/api/crm/prospects/route';
  import {bootstrapOwner,makeSession} from './lib/payroll-auth-store';
  import {encryptMail} from './lib/payroll-mail-core';
  import {processProspectQueue,processProspectReplyQueue} from './lib/crm-prospects-store';
  import {createHash} from 'node:crypto';
  export default {async fetch(req:Request){
   const path=new URL(req.url).pathname;
   if(path==='/__fixture/setup'){
    const owner=await bootstrapOwner('prospect-worker-fixture','fixture-only-password'),token=await makeSession(owner),time=new Date().toISOString();
    const ids=[crypto.randomUUID(),crypto.randomUUID(),crypto.randomUUID()],emails=['cultura@municipio-a.example.invalid','cultura@municipio-b.example.invalid','CULTURA@municipio-a.example.invalid'];
    for(let i=0;i<ids.length;i++)await env.DB.prepare('INSERT INTO jac_crm_prospects(id,source_id,department,municipality,festival,period,month,email,emails_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)').bind(ids[i],'synthetic:'+i,'Departamento Ficticio','Municipio Ficticio '+i,'Fiesta Ficticia '+i,'Julio de2027, por confirmar',7,emails[i],JSON.stringify([emails[i]]),time,time).run();
    const pdf=new TextEncoder().encode(${JSON.stringify(brochure)}),brochureID=createHash('sha256').update(pdf).digest('hex'),key='crm/prospects/brochures/'+brochureID+'.pdf';
    await env.BUCKET.put(key,pdf,{httpMetadata:{contentType:'application/pdf'}});
    await env.DB.prepare('INSERT INTO jac_crm_prospect_brochures(id,file_key,filename,size,sha256,created_at) VALUES(?,?,?,?,?,?)').bind(brochureID,key,'Brochure-ficticio.pdf',pdf.length,brochureID,time).run();
    const credentials=await encryptMail({clientId:'fixture-client',clientSecret:'fixture-secret',refreshToken:'fixture-refresh'},env.PAYROLL_MAIL_KEY);
    await env.DB.prepare("INSERT INTO payroll_gmail(id,credentials,connected_email,enabled,error,updated_at) VALUES('jac',?,'jacmusicestudios@gmail.com',1,'',?)").bind(credentials,time).run();
    return Response.json({token,ids,brochureID});
   }
   if(path==='/__fixture/process'){await processProspectQueue();await processProspectReplyQueue();return Response.json({ok:true});}
   globalThis.__prospectFixtureRequest=req;
   return req.method==='POST'?POST(req):GET(req);
  }};
 `},bundle:true,platform:'browser',format:'esm',write:false,external:['cloudflare:workers','node:*'],plugins:[{name:'isolated-request-context',setup(b){
  b.onResolve({filter:/^@\/lib\/payroll-access$/},()=>({path:'context',namespace:'fixture'}));
  b.onLoad({filter:/.*/,namespace:'fixture'},()=>({loader:'ts',resolveDir:process.cwd(),contents:`import {authenticatedSession} from './lib/payroll-auth-store';import {sessionToken} from './lib/payroll-auth-crypto';export const payrollUser=async()=>authenticatedSession(sessionToken(globalThis.__prospectFixtureRequest.headers.get('cookie')??'',true));export const payrollHeaders={'Cache-Control':'private, no-store','Vary':'Cookie','X-Content-Type-Options':'nosniff'};`}));
  b.onResolve({filter:/^next\/headers$/},()=>({path:'headers',namespace:'next-fixture'}));
  b.onLoad({filter:/.*/,namespace:'next-fixture'},()=>({loader:'js',contents:'export const headers=async()=>new Headers();'}));
 }}]});
 const sent=[];let outgoing=0;
 const mf=new Miniflare({modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],script:output.outputFiles[0].text,d1Databases:{DB:'crm-prospects-worker-fixture'},r2Buckets:{BUCKET:'crm-prospects-private-fixture'},bindings:{PAYROLL_AUTH_KEY:'crm-prospects-independent-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,67).toString('base64url')},outboundService:async req=>{
  outgoing++;
  if(req.url==='https://oauth2.googleapis.com/token'){const form=await req.formData();assert.equal(form.get('refresh_token'),'fixture-refresh');return Response.json({access_token:'fixture-access',expires_in:3600});}
  assert.equal(req.url,'https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/send?uploadType=media','Every provider request remains intercepted.');assert.equal(req.method,'POST');assert.equal(req.headers.get('content-type'),'message/rfc822');assert.equal(req.headers.get('authorization'),'Bearer fixture-access');
  const bytes=new Uint8Array(await req.arrayBuffer()),text=new TextDecoder().decode(bytes),headers=text.slice(0,text.indexOf('\r\n\r\n'));
  assert.equal(bytes.length,Number(req.headers.get('content-length')));assert.equal((headers.match(/^To:/gm)??[]).length,1);assert(!/^Bcc:|^Cc:/gim.test(headers));assert.match(headers,/To: cultura@municipio-[ab]\.example\.invalid/i);assert.match(text,/Content-Type: application\/pdf/);assert(text.includes(Buffer.from(brochure).toString('base64')),'The complete original fixture PDF is attached.');
  sent.push(text);return Response.json({id:'fixture-message-'+sent.length,threadId:'fixture-thread-'+sent.length});
 }});
 try{
  const db=await mf.getD1Database('DB');
  for(const file of(await readdir('drizzle')).filter(file=>file.endsWith('.sql')).sort())for(const sql of(await readFile('drizzle/'+file,'utf8')).split('--> statement-breakpoint').map(sql=>sql.trim()).filter(Boolean))await db.prepare(sql).run();
  const base='https://crm.example.invalid',endpoint=base+'/api/crm/prospects';
  let response=await mf.dispatchFetch(endpoint);assert.equal(response.status,401);assert.equal(outgoing,0);
  const setup=await(await mf.dispatchFetch(base+'/__fixture/setup')).json(),session='__Host-jac_session='+setup.token;
  const get=query=>mf.dispatchFetch(endpoint+(query??''),{headers:{cookie:session}});
  const post=(action,record)=>mf.dispatchFetch(endpoint,{method:'POST',headers:{cookie:session,Origin:base,'Content-Type':'application/json'},body:JSON.stringify({action,record})});
  response=await get();let data=await response.json();assert.equal(response.status,200,data.error);assert.equal(data.summary.total,3);assert.equal(data.mail.connected,true);assert.equal(data.mail.trackingConnected,false);assert.equal(data.brochure.ready,true);assert.equal(sent.length,0);
  const template={subject:'Propuesta {{anio}} para {{municipio}}',body:'{{saludo}}\nProponemos Jhon Alex para {{fiesta}}. Escríbanos: {{whatsapp}}'};
  response=await post('preview',{ids:setup.ids,...template});const preview=await response.json();assert.equal(response.status,200,preview.error);assert.equal(preview.messages.length,2);assert.equal(preview.excluded.length,1);assert.equal(sent.length,0,'Preview cannot contact recipients.');assert.match(preview.messages[0].body,/Señor alcalde y equipo/);assert.match(preview.messages[0].body,/https:\/\/wa\.me\/573125064091/);
  const batchID=crypto.randomUUID(),record={id:batchID,ids:setup.ids,...template,brochureId:data.brochure.id,previewHash:preview.previewHash};
  response=await post('queueBatch',record);data=await response.json();assert.equal(response.status,200,data.error);assert.equal(data.batch.total,2);assert.equal(data.batch.pending,2);assert.equal(sent.length,0,'Only a durable confirmed batch is prepared; the runner sends it later.');
  response=await post('queueBatch',record);assert.equal((await response.json()).batch.total,2);assert.equal((await db.prepare('SELECT count(*) AS n FROM jac_crm_prospect_deliveries').first()).n,2);
  response=await mf.dispatchFetch(base+'/__fixture/process');assert.equal(response.status,200);assert.equal(sent.length,2);
  response=await get('?batch='+batchID);data=await response.json();assert.equal(data.batch.sent,2);assert.equal(data.batch.pending,0);for(const delivery of data.deliveries){assert.match(delivery.messageId,/^fixture-message-/);assert.match(delivery.threadId,/^fixture-thread-/);assert.equal(delivery.replyStatus,'none');}
  response=await post('queueBatch',record);assert.equal((await response.json()).batch.sent,2);await mf.dispatchFetch(base+'/__fixture/process');assert.equal(sent.length,2,'Lost acknowledgement retries and overlapping maintenance cannot resend the batch.');
  response=await post('markReply',{id:data.deliveries[0].id,status:'received'});assert.equal(response.status,200);response=await get('?id='+data.deliveries[0].prospectId);data=await response.json();assert.equal(data.prospect.stage,'contacted','A reply is never converted into commercial interest automatically.');assert.equal(data.deliveries[0].replyStatus,'received');
  response=await get('?brochure='+setup.brochureID+'&download=1');assert.equal(response.status,200);assert.equal(await response.text(),brochure);assert.match(response.headers.get('content-disposition'),/^attachment;/);
  response=await mf.dispatchFetch(endpoint+'?brochure='+setup.brochureID,{headers:{cookie:'__Host-jac_session=invalid'}});assert.equal(response.status,401,'An invalid cookie cannot read the stored brochure.');
 }finally{await mf.dispose();}
});
