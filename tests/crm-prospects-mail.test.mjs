import test,{beforeEach,after} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {build} from 'esbuild';
import {mkdtemp,readdir,readFile,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const migrations=await Promise.all((await readdir('drizzle')).filter(file=>file.endsWith('.sql')).sort().map(file=>readFile('drizzle/'+file,'utf8')));
let db,hook,calls,uploadMode,threadMessages,account,tokenScopes;
class Q {
 constructor(sql,args=[]){this.sql=sql;this.args=args;}
 bind(...args){return new Q(this.sql,args);}
 execute(){const statement=db.prepare(this.sql);return statement.columns().length?{results:statement.all(...this.args),meta:{changes:Number(db.prepare('SELECT changes() n').get().n)}}:{results:[],meta:{changes:Number(statement.run(...this.args).changes)}};}
 async first(){return this.execute().results[0]??null;}
 async all(){return this.execute();}
 async run(){return this.execute();}
}
globalThis.__prospectMailEnv={DB:{prepare:sql=>new Q(sql),batch:async queries=>queries.map(query=>query.execute())},PAYROLL_AUTH_KEY:'prospect-mail-independent-fictitious-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,49).toString('base64url')};
const compiled=await build({stdin:{resolveDir:process.cwd(),contents:"export * from './lib/crm-prospects-mail';export * from './lib/crm-prospects-oauth';export * from './lib/payroll-mail';export * from './lib/payroll-mail-core';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/crm-access';"},bundle:true,format:'esm',platform:'node',write:false,plugins:[{name:'synthetic-cloud',setup(builder){builder.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fixture'}));builder.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const env=globalThis.__prospectMailEnv;'}));}}]});
const directory=await mkdtemp(resolve('work/prospect-mail-tests-'));await writeFile(directory+'/module.mjs',compiled.outputFiles[0].contents);const m=await import(pathToFileURL(directory+'/module.mjs'));await rm(directory,{recursive:true});
let user,session;
globalThis.fetch=async(input,options={})=>{
 const url=new URL(String(input));calls.push({url,options});
 if(hook){const result=await hook(url,options);if(result)return result;}
 if(url.href==='https://oauth2.googleapis.com/token')return Response.json({access_token:'fixture-prospect-access',refresh_token:'fixture-tracking-refresh',scope:tokenScopes});
 if(url.href==='https://openidconnect.googleapis.com/v1/userinfo')return Response.json({email:account,email_verified:true});
 if(url.origin==='https://gmail.googleapis.com'&&url.pathname==='/upload/gmail/v1/users/me/messages/send'){
  const raw=new Uint8Array(await new Response(options.body).arrayBuffer());calls.at(-1).raw=raw;
  if(uploadMode==='network')throw Error('Simulated socket loss after request');
  if(uploadMode==='5xx')return new Response('{}',{status:503});
  if(uploadMode==='4xx')return new Response('{}',{status:429});
  if(uploadMode==='json')return new Response('not-json');
  if(uploadMode==='incomplete')return Response.json({id:'fixture-delivery'});
  return Response.json({id:'fixture-delivery',threadId:'fixture-thread'});
 }
 if(url.origin==='https://gmail.googleapis.com'&&url.pathname==='/gmail/v1/users/me/threads/fixture-thread')return Response.json({id:'fixture-thread',messages:threadMessages});
 throw Error('The fixture forbids external mail, revocation, lookup and all unmocked traffic: '+url.origin+url.pathname);
};
beforeEach(async()=>{
 db?.close();db=new DatabaseSync(':memory:');for(const migration of migrations)db.exec(migration);hook=null;calls=[];uploadMode='ok';threadMessages=[];account=m.GMAIL_SENDER;tokenScopes='openid email '+m.PROSPECT_SEND_SCOPE+' '+m.PROSPECT_METADATA_SCOPE;
 const now=new Date().toISOString(),id='fixture-prospect-administrator';db.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)').run(id,'fixture-prospect-admin','crm-admin@example.invalid','Administrador ficticio','fixture-not-a-real-password-hash','["administrator"]',now,now);
 session=await m.makeSession(id);user=await m.authenticatedSession(session);
 await m.saveMailCredentials('fixture.apps.googleusercontent.com','fixture-only-client-secret');
 const credentials=await m.encryptMail({clientId:'fixture.apps.googleusercontent.com',clientSecret:'fixture-only-client-secret',refreshToken:'fixture-payroll-refresh'},m.mailKey());db.prepare("UPDATE payroll_gmail SET credentials=?,connected_email=?,enabled=1 WHERE id='jac'").run(credentials,m.GMAIL_SENDER);
});
after(()=>db?.close());
const snapshot=()=>({id:crypto.randomUUID(),email:'alcaldia@example.invalid',subject:'Jhon Alex Castaño para las ferias de Municipio Ficticio2027',body:'Señor alcalde:\n\nDesde el equipo de management le presentamos el show de Jhon Alex Castaño.\n\nConversemos por WhatsApp: https://wa.me/573125064091',rfcMessageId:'<jac-prospect-fixture@jhonalexcastano.com>'});
function attachment(bytes=new TextEncoder().encode('%PDF-1.7\nSynthetic fixture only.')){
 let cursor=0,cancelled=false;const sizes=[1,2,7,58,64000];let part=0;
 return {filename:'Brochure de prueba.pdf',size:bytes.length,body:new ReadableStream({pull(controller){if(cursor===bytes.length){controller.close();return;}const end=Math.min(bytes.length,cursor+sizes[Math.min(part++,sizes.length-1)]);controller.enqueue(bytes.slice(cursor,end));cursor=end;},cancel(){cancelled=true;}}),wasCancelled:()=>cancelled};
}
async function start(){const value=await m.startProspectMailOauth(user,'__Host-jac_session='+session),url=new URL(value.url);return {...value,state:url.searchParams.get('state'),google:url,guard:value.cookie.split(';')[0]};}
const callback=(value,cookie=value.guard+'; __Host-jac_session='+session,query='code=fixture-authorization-code')=>new Request(m.GMAIL_CALLBACK+'?state='+value.state+'&'+query,{headers:{cookie}});
async function connect(){const value=await start(),result=await m.finishProspectMailOauth(callback(value));assert.equal(new URL(result.url).searchParams.get('tracking'),'connected');return value;}
const gmailRow=()=>db.prepare("SELECT * FROM payroll_gmail WHERE id='jac'").get();
const sends=()=>calls.filter(call=>call.url.pathname==='/upload/gmail/v1/users/me/messages/send');

test('prospect transport reuses send-only Gmail, sends one personalized RFC822 recipient and preserves deterministic message ID and PDF bytes',async()=>{
 const before=gmailRow(),status=await m.prospectMailConnection();assert.deepEqual(status,{sender:m.GMAIL_SENDER,connected:true,trackingConnected:false,error:''});
 const prospect=snapshot(),pdf=new TextEncoder().encode('%PDF-1.7\nSynthetic fixture only.');let validated=0;assert.deepEqual(await m.sendProspectEmail(prospect,attachment(pdf),async()=>{validated++;}),{messageId:'fixture-delivery',threadId:'fixture-thread'});assert.equal(validated,1);assert.equal(sends().length,1);
 const sent=sends()[0],raw=new TextDecoder().decode(sent.raw);assert.equal(sent.url.searchParams.get('uploadType'),'media');assert.equal(sent.options.headers['Content-Type'],'message/rfc822');assert.equal(Number(sent.options.headers['Content-Length']),sent.raw.length);assert(sent.options.body instanceof ReadableStream);assert.equal(sent.options.redirect,'manual');assert.equal((raw.match(/^To:/gm)||[]).length,1);assert(!/^Cc:|^Bcc:/m.test(raw));assert.match(raw,/Message-ID: <jac-prospect-fixture@jhonalexcastano.com>/);assert(raw.includes('To: '+prospect.email));assert(raw.includes('Content-Type: text/html'));
 const plain=raw.split('Content-Type: text/plain; charset=UTF-8')[1].split('\r\n\r\n')[1].split('\r\n--')[0];assert.equal(Buffer.from(plain,'base64').toString(),prospect.body);
 const html=Buffer.from(raw.split('Content-Type: text/html; charset=UTF-8')[1].split('\r\n\r\n')[1].split('\r\n--')[0],'base64').toString();assert.match(html,/<a href="https:\/\/wa.me\/573125064091"/);
 const pdfPart=raw.split('Content-Disposition: attachment;')[1].split('\r\n\r\n')[1].split('\r\n--')[0];assert.deepEqual(new Uint8Array(Buffer.from(pdfPart,'base64')),pdf);assert.deepEqual(gmailRow(),before,'The transport does not change payroll credentials or scopes.');
});
test('the original brochure size streams as bounded base64 chunks without a second JSON/base64 envelope',async()=>{
 const pdf=new Uint8Array(7823266).fill(109);pdf.set(new TextEncoder().encode('%PDF-1.7\n'));await m.sendProspectEmail(snapshot(),attachment(pdf));const sent=sends()[0],raw=new TextDecoder().decode(sent.raw);assert.equal(Number(sent.options.headers['Content-Length']),sent.raw.length);assert(sent.raw.length<11*1024*1024);const encoded=raw.split('Content-Disposition: attachment;')[1].split('\r\n\r\n')[1].split('\r\n--')[0];assert.deepEqual(new Uint8Array(Buffer.from(encoded,'base64')),pdf);assert(!raw.startsWith('{"raw":'));assert.equal(sends().length,1);
});
test('invalid input, lost authorization and the final session guard fail before sending and cancel the attachment',async()=>{
 for(const patch of [{email:'bad\r\nCc: victim@example.invalid'},{subject:'Bad\r\nBcc: victim@example.invalid'},{rfcMessageId:'<fake@example.invalid>\r\nBcc: victim@example.invalid'}]){const file=attachment();await assert.rejects(()=>m.sendProspectEmail({...snapshot(),...patch},file),error=>error instanceof m.ProspectMailFailure&&!error.uncertain);assert(file.wasCancelled());}
 let file=attachment();await assert.rejects(()=>m.sendProspectEmail(snapshot(),file,async()=>{throw Error('Fixture permission revoked');}),error=>error instanceof m.ProspectMailFailure&&!error.uncertain);assert.equal(sends().length,0);
 file=attachment(new TextEncoder().encode('not a PDF'));await assert.rejects(()=>m.sendProspectEmail(snapshot(),file),error=>!error.uncertain);assert.equal(sends().length,0);
 file=attachment();await assert.rejects(()=>m.sendProspectEmail(snapshot(),file,async()=>{db.prepare("UPDATE payroll_gmail SET enabled=0 WHERE id='jac'").run();}),error=>!error.uncertain&&error.status===403);assert.equal(sends().length,0);
});
test('provider failures distinguish safe rejection from uncertain outcomes without automatic retries',async()=>{
 for(const mode of ['4xx','5xx','network','json','incomplete']){uploadMode=mode;const before=sends().length;await assert.rejects(()=>m.sendProspectEmail(snapshot(),attachment()),error=>error instanceof m.ProspectMailFailure&&error.uncertain===(mode!=='4xx'));assert.equal(sends().length,before+1,'No outcome triggers another provider call.');}
});
test('provider abort cancels an attachment stalled after its PDF header without deadlocking stream cleanup',async()=>{
 let cancelled=false;const stalled={filename:'Fixture.pdf',size:100,body:new ReadableStream({start(controller){controller.enqueue(new TextEncoder().encode('%PDF-'));},pull(){return new Promise(()=>{});},cancel(){cancelled=true;}})};
 hook=async(url,options)=>{if(url.pathname!=='/upload/gmail/v1/users/me/messages/send')return null;const reader=options.body.getReader();await reader.read();reader.read().catch(()=>{});await Promise.resolve();throw Error('Fixture network failed while attachment read was pending');};
 let timer;try{await assert.rejects(()=>Promise.race([m.sendProspectEmail(snapshot(),stalled),new Promise((resolve,reject)=>{timer=setTimeout(()=>reject(Error('Attachment cleanup deadlocked')),1000);})]),error=>error instanceof m.ProspectMailFailure&&error.uncertain);assert.equal(cancelled,true);assert.equal(sends().length,1);}finally{clearTimeout(timer);}
});
test('tracking OAuth uses the registered callback and CRM PKCE/session guard, stores its own grant and leaves send-only payroll untouched',async()=>{
 const before=gmailRow(),value=await start();assert.equal(value.google.searchParams.get('redirect_uri'),m.GMAIL_CALLBACK);assert.equal(value.google.searchParams.get('include_granted_scopes'),'false');assert.equal(value.google.searchParams.get('scope'),tokenScopes);assert.equal(value.google.searchParams.get('code_challenge_method'),'S256');assert.equal(value.google.searchParams.get('login_hint'),m.GMAIL_SENDER);assert(!value.google.searchParams.get('scope').includes('gmail.readonly'));assert.match(value.cookie,/HttpOnly; Secure; SameSite=Lax/);
 const absent=await m.finishProspectMailOauth(callback(value,value.guard));assert.equal(new URL(absent.url).searchParams.get('tracking'),'error');assert.equal(calls.length,0);assert(db.prepare('SELECT id FROM payroll_oauth WHERE id=?').get('crm-prospects:'+value.state));
 const result=await m.finishProspectMailOauth(callback(value));assert.equal(new URL(result.url).pathname,'/crm');assert.equal(new URL(result.url).searchParams.get('seccion'),'prospectos');assert.equal(new URL(result.url).searchParams.get('tracking'),'connected');assert.match(result.cookie,/Max-Age=0/);assert.equal(await m.finishProspectMailOauth(callback(value)),null);assert.equal(calls.length,2);
 const own=await m.prospectMailConfig();assert(!own.credentials.includes('fixture-tracking-refresh'));assert.equal((await m.decryptMail(own.credentials,m.mailKey())).refreshToken,'fixture-tracking-refresh');assert.deepEqual(gmailRow(),before);assert.equal((await m.prospectMailConnection()).trackingConnected,true);
 calls=[];await m.sendProspectEmail(snapshot(),attachment());const tokenCall=calls.find(call=>call.url.href==='https://oauth2.googleapis.com/token');assert.equal(new URLSearchParams(tokenCall.options.body).get('refresh_token'),'fixture-tracking-refresh');
 await m.disconnectProspectMail(own.version,m.crmStoredGuard(m.tokenHash(session),user.id));assert.equal((await m.prospectMailConnection()).trackingConnected,false);assert.equal((await m.prospectMailConnection()).connected,true);assert.deepEqual(gmailRow(),before);assert(!calls.some(call=>call.url.pathname==='/revoke'));
});
test('tracking OAuth rejects wrong account, missing scope, expired/revoked sessions, cancellation and stale configuration',async()=>{
 const before=gmailRow();
 account='wrong-account@example.invalid';let value=await start();assert.equal(new URL((await m.finishProspectMailOauth(callback(value))).url).searchParams.get('tracking'),'error');assert.equal((await m.prospectMailConnection()).trackingConnected,false);account=m.GMAIL_SENDER;
 tokenScopes=m.PROSPECT_SEND_SCOPE;value=await start();assert.equal(new URL((await m.finishProspectMailOauth(callback(value))).url).searchParams.get('tracking'),'error');tokenScopes='openid email '+m.PROSPECT_SEND_SCOPE+' '+m.PROSPECT_METADATA_SCOPE;
 value=await start();let count=calls.length;assert.equal(new URL((await m.finishProspectMailOauth(callback(value,undefined,'error=access_denied'))).url).searchParams.get('tracking'),'error');assert.equal(calls.length,count);
 value=await start();db.prepare('UPDATE payroll_oauth SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z','crm-prospects:'+value.state);count=calls.length;assert.equal(new URL((await m.finishProspectMailOauth(callback(value))).url).searchParams.get('tracking'),'error');assert.equal(calls.length,count);
 value=await start();db.prepare("UPDATE jac_crm_prospect_mail SET version=version+1 WHERE id='jac'").run();assert.equal(new URL((await m.finishProspectMailOauth(callback(value))).url).searchParams.get('tracking'),'error');assert.equal(calls.length,count);
 value=await start();db.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(session));assert.equal(new URL((await m.finishProspectMailOauth(callback(value))).url).searchParams.get('tracking'),'error');assert.equal(calls.length,count);assert.deepEqual(gmailRow(),before);assert(!calls.some(call=>call.url.pathname==='/revoke'));
});
test('reply tracking reads only the stored thread metadata and distinguishes human replies, automatic notices and bounces',async()=>{
 await connect();const sentAt=new Date(Date.now()-60000).toISOString(),original={id:'fixture-delivery',internalDate:String(Date.parse(sentAt)),labelIds:['SENT'],payload:{headers:[{name:'From',value:m.GMAIL_SENDER},{name:'To',value:'alcaldia@example.invalid'}]}},reply={id:'fixture-reply',internalDate:String(Date.parse(sentAt)+1000),labelIds:['INBOX'],payload:{headers:[{name:'From',value:'Alcaldía ficticia <alcaldia@example.invalid>'},{name:'To',value:m.GMAIL_SENDER},{name:'Subject',value:'Re: Propuesta ficticia'}],body:{data:'NEVER_EXPOSE_BODY'}}};
 const request={threadId:'fixture-thread',messageId:'fixture-delivery',email:'alcaldia@example.invalid',sentAt,rfcMessageId:'<jac-prospect-fixture@jhonalexcastano.com>'};
 for(const [headers,status] of [[[],'received'],[[{name:'Auto-Submitted',value:'auto-replied'}],'automatic'],[[{name:'Subject',value:'Fuera de la oficina'}],'automatic'],[[{name:'From',value:'Mailer-Daemon <mailer-daemon@example.invalid>'}],'bounced']]){
  const replace=new Set(headers.map(header=>header.name.toLowerCase()));threadMessages=[original,{...reply,payload:{...reply.payload,headers:[...reply.payload.headers.filter(header=>!replace.has(header.name.toLowerCase())),...headers]}}];const result=await m.checkProspectReplies(request);assert.equal(result.status,status);assert.equal(result.repliedAt,new Date(Number(reply.internalDate)).toISOString());assert(!JSON.stringify(result).includes('NEVER_EXPOSE_BODY'));
 }
 const assistant={...reply,payload:{headers:[{name:'From',value:'secretaria@example.invalid'},{name:'To',value:m.GMAIL_SENDER}]}};threadMessages=[original,assistant];assert.equal((await m.checkProspectReplies(request)).status,'none','An unrelated sender grouped into the thread is not a proposal reply.');assistant.payload.headers.push({name:'In-Reply-To',value:request.rfcMessageId});assert.equal((await m.checkProspectReplies(request)).status,'received','An assistant can answer from another address when referencing the exact original proposal.');
 threadMessages=[original,{...reply,internalDate:String(Date.parse(sentAt)-1000)}];assert.equal((await m.checkProspectReplies(request)).status,'none');threadMessages=[original,{...reply,labelIds:['SENT']}];assert.equal((await m.checkProspectReplies(request)).status,'none');
 const lookups=calls.filter(call=>call.url.pathname.includes('/threads/'));assert(lookups.length);for(const call of lookups){assert.equal(call.url.searchParams.get('format'),'metadata');assert.equal(call.url.searchParams.has('q'),false);assert(!call.url.searchParams.get('fields').includes('body'));assert(call.url.searchParams.getAll('metadataHeaders').includes('Auto-Submitted'));assert.equal(call.options.redirect,'manual');}
});
