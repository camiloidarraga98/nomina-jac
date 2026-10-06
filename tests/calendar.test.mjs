import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

// Only in-memory D1 and simulated Google responses; no real events or payroll.
const sql=new DatabaseSync(':memory:');
for(const file of (await readdir('drizzle')).filter(x=>x.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+file,'utf8'));
class Query {
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const q=sql.prepare(this.text);if(q.columns().length)return {results:q.all(...this.args),meta:{changes:Number(sql.prepare('SELECT changes() AS n').get().n)}};return {results:[],meta:{changes:Number(q.run(...this.args).changes)}};}
 async run(){return this.execute();}async all(){return this.execute();}async first(){return sql.prepare(this.text).get(...this.args)||null;}
}
globalThis.__calendarEnv={DB:{prepare:s=>new Query(s),batch:async qs=>{sql.exec('BEGIN');try{const result=qs.map(q=>q.execute());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}},PAYROLL_AUTH_KEY:'calendar-independent-test-authentication-key-only',PAYROLL_MAIL_KEY:Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url')};
globalThis.__calendarHeaders=new Headers();
const bundle=await build({stdin:{contents:"export * as api from './app/api/calendar/route';export * as handoff from './app/api/calendar/connect/route';export * as callback from './app/api/payroll/gmail/callback/route';export * from './lib/calendar';export * from './lib/calendar-core';export * from './lib/calendar-oauth';export * from './lib/calendar-oauth-errors';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export * from './lib/payroll-mail';export * from './lib/payroll-mail-core';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'platform',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='cloudflare:workers'?'export const env=globalThis.__calendarEnv;export const waitUntil=p=>p.catch(()=>{});':'export const headers=async()=>globalThis.__calendarHeaders;',loader:'js'}));}}]});
const dir=await mkdtemp(resolve('work/calendar-tests-')),moduleFile=dir+'/bundle.mjs';await writeFile(moduleFile,bundle.outputFiles[0].contents);
const m=await import(pathToFileURL(moduleFile).href);await rm(dir,{recursive:true});
const {calendarOAuthMessage}=m;
const base='https://calendar.example.invalid',owner=await m.bootstrapOwner('calendar-owner','1');
let ownerToken=await m.makeSession(owner),readerToken;
let calls=[],tokenScope=m.CALENDAR_SCOPE,googleEmail=m.CALENDAR_ACCOUNT,googleHook=null;
const available={id:'concerts@group.calendar.google.com',summary:'Conciertos de prueba',timeZone:'America/Bogota',accessRole:'reader'};
const concert={id:'recurring-instance',summary:'Concierto simulado',start:{dateTime:'2026-10-07T04:30:00Z'},end:{dateTime:'2026-10-07T06:00:00Z'},description:'<p>Prueba &amp; ensayo</p><br>Agenda',location:'Teatro simulado',htmlLink:'https://calendar.google.com/calendar/event?eid=simulado'};
globalThis.fetch=async(input,options={})=>{
 const url=new URL(String(input));calls.push({url,options});
 if(googleHook){const reply=await googleHook(url,options);if(reply)return reply;}
 if(url.href==='https://oauth2.googleapis.com/token')return Response.json({access_token:'simulated-calendar-access',refresh_token:'simulated-calendar-refresh',scope:tokenScope});
 if(url.href==='https://openidconnect.googleapis.com/v1/userinfo')return Response.json({email:googleEmail,email_verified:true});
 if(url.origin==='https://www.googleapis.com'&&url.pathname==='/calendar/v3/users/me/calendarList')return Response.json({items:[available,{id:m.CALENDAR_ACCOUNT,summary:'Principal',primary:true,timeZone:'America/Bogota',accessRole:'owner'},{id:'busy-only',summary:'Sin detalles',accessRole:'freeBusyReader'}]});
 if(url.origin==='https://www.googleapis.com'&&url.pathname==='/calendar/v3/calendars/'+encodeURIComponent(available.id)+'/events')return Response.json({items:[concert,{id:'trip',summary:'Viaje simulado',start:{date:'2026-10-06'},end:{date:'2026-10-08'}},{...concert,id:'cancelled',status:'cancelled'}]});
 throw new Error('La prueba no admite tráfico real, escritura de eventos ni correo.');
};
async function api(token,{action,month='2026-10',query='',origin=base,...body}={}){
 const cookie=token?'__Host-jac_session='+token:'';globalThis.__calendarHeaders=new Headers({host:'calendar.example.invalid',cookie});
 const req=new Request(base+'/api/calendar'+(action?'':'?month='+month+query),action?{method:'POST',headers:{cookie,origin,'Content-Type':'application/json'},body:JSON.stringify({action,...body})}:{headers:{cookie}});
 const response=await m.api[action?'POST':'GET'](req);return {status:response.status,body:await response.json(),headers:response.headers};
}
async function start(native=false){
 const result=await api(ownerToken,{action:'connect',native});assert.equal(result.status,200,result.body.error);
 let response;
 if(native){response=await m.handoff.GET(new Request(result.body.url));assert.equal(response.status,303);}
 const google=new URL(native?response.headers.get('location'):result.body.url),guard=(native?response.headers:result.headers).get('set-cookie').split(';')[0];
 return {url:result.body.url,nonce:result.body.nonce,state:google.searchParams.get('state'),google,guard,cookie:guard+(native?'':'; __Host-jac_session='+ownerToken)};
}
function callbackRequest(c,cookie=c.cookie,query='code=simulated-code'){return new Request(m.GMAIL_CALLBACK+'?state='+c.state+'&'+query,{headers:{cookie}});}
async function connect(native=false){const c=await start(native),result=await m.callback.GET(callbackRequest(c));assert.equal(result.status,303);assert.equal(new URL(result.headers.get('location')).searchParams.get(native?'result':'calendar'),'connected');return c;}
const gmailRow=()=>sql.prepare('SELECT * FROM payroll_gmail WHERE id=?').get('jac');

test('agenda exige sesión; solo el propietario prepara conexión y selección con origen válido',async()=>{
 assert.equal((await api('')).status,401);
 const now=new Date().toISOString();sql.prepare('INSERT INTO payroll_users (id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)').run('reader','calendar-reader','reader@example.invalid','Lector',m.hashPassword('1',globalThis.__calendarEnv.PAYROLL_AUTH_KEY),'[]',now,now);
 readerToken=await m.makeSession('reader');
 const disconnected=await api(readerToken);assert.equal(disconnected.status,200);assert.equal(disconnected.body.connection.connected,false);assert.equal(disconnected.body.events.length,0);assert.match(disconnected.headers.get('cache-control'),/private, no-store/);assert.equal(disconnected.headers.get('vary'),'Cookie');
 assert.equal((await api(readerToken,{action:'connect'})).status,403);
 assert.equal((await api(readerToken,{query:'&action=calendars'})).status,403);
 assert.equal((await api(ownerToken,{action:'connect',origin:'https://other.example.invalid'})).status,403);
 assert.equal((await api(ownerToken,{month:'2026-13'})).status,400);
 assert.equal((await api(ownerToken,{action:'connect'})).status,400,'Faltan las credenciales de Google configuradas en Correos');assert.equal(calls.length,0);
 await m.saveMailCredentials('simulated.apps.googleusercontent.com','simulated-client-secret');
 sql.prepare('UPDATE payroll_gmail SET credentials=?,connected_email=?,enabled=1 WHERE id=?').run(await m.encryptMail({clientId:'simulated.apps.googleusercontent.com',clientSecret:'simulated-client-secret',refreshToken:'simulated-gmail-refresh'},m.mailKey()),m.CALENDAR_ACCOUNT,'jac');
});

test('OAuth web usa PKCE, guard y sesión; cifra el permiso de lectura sin alterar Gmail',async()=>{
 calls=[];const gmail=gmailRow(),c=await start();
 assert.equal(c.google.searchParams.get('redirect_uri'),m.GMAIL_CALLBACK);assert.equal(c.google.searchParams.get('scope'),'openid email '+m.CALENDAR_SCOPE);assert.equal(c.google.searchParams.get('include_granted_scopes'),'false');assert.equal(c.google.searchParams.get('code_challenge_method'),'S256');assert.ok(!c.google.searchParams.get('scope').includes('gmail.send'));assert.equal(calls.length,0);
 const missingSession=new URL((await m.finishCalendarCallback(callbackRequest(c,c.guard))).url);assert.equal(missingSession.searchParams.get('calendar'),'error','El callback web también exige la sesión del propietario');assert.equal(missingSession.searchParams.get('reason'),'web_session');assert.equal(calls.length,0);
 assert.ok(sql.prepare('SELECT id FROM payroll_oauth WHERE id=?').get('calendar:'+c.state));
 const result=await m.callback.GET(callbackRequest(c));assert.equal(new URL(result.headers.get('location')).searchParams.get('calendar'),'connected');assert.equal(result.headers.get('referrer-policy'),'no-referrer');assert.equal(calls.length,2);
 assert.match(new URLSearchParams(calls[0].options.body).get('code_verifier'),/^[A-Za-z0-9_-]{43}$/);
 assert.equal(await m.finishCalendarCallback(callbackRequest(c)),null);assert.equal(calls.length,2);
 const row=await m.calendarConfig();assert.ok(!row.credentials.includes('simulated-calendar-refresh'));assert.equal((await m.decryptMail(row.credentials,m.mailKey())).refreshToken,'simulated-calendar-refresh');
 assert.deepEqual(gmailRow(),gmail);assert.equal((await m.mailConnection()).connected,true);
 const visible=await api(readerToken);assert.ok(!JSON.stringify(visible.body).includes('simulated-'));assert.equal(visible.body.connection.selected,null);
});

test('OAuth iPhone entrega un ticket de un uso; valida nonce, guard, expiración y sesión activa',async()=>{
 calls=[];const c=await start(true);assert.match(c.nonce,/^[A-Za-z0-9_-]{43}$/);assert.ok(!c.url.includes(ownerToken));assert.equal((await m.handoff.GET(new Request(c.url))).status,400);
 const missingGuard=new URL((await m.finishCalendarCallback(callbackRequest(c,''))).url);assert.equal(missingGuard.searchParams.get('result'),'error');assert.equal(missingGuard.searchParams.get('reason'),'browser_guard');assert.equal(calls.length,0);
 const result=await m.callback.GET(callbackRequest(c)),target=new URL(result.headers.get('location'));assert.equal(target.protocol,'jacnomina:');assert.equal(target.host,'calendar');assert.equal(target.searchParams.get('nonce'),c.nonce);assert.equal(target.searchParams.get('result'),'connected');assert.ok(!target.href.includes('simulated-'));
 calls=[];const expired=await api(ownerToken,{action:'connect',native:true});sql.prepare('UPDATE payroll_oauth SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z','calendar-ticket:'+m.tokenHash(new URL(expired.body.url).searchParams.get('ticket')));assert.equal((await m.handoff.GET(new Request(expired.body.url))).status,400);
 const stale=await start(true);sql.prepare('UPDATE payroll_oauth SET expires_at=? WHERE id=?').run('2000-01-01T00:00:00Z','calendar:'+stale.state);assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(stale))).url).searchParams.get('reason'),'expired');
 const revoked=await start(true);sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(ownerToken));assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(revoked))).url).searchParams.get('reason'),'session_revoked');ownerToken=await m.makeSession(owner);
 const pending=await api(ownerToken,{action:'connect',native:true});sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(owner);assert.equal((await m.handoff.GET(new Request(pending.body.url))).status,400);ownerToken=await m.makeSession(owner);assert.equal(calls.length,0);
});

test('cuenta incorrecta, permiso incompleto, cancelación o conexión obsoleta no guardan tokens',async()=>{
 const before=await m.calendarConfig(),gmail=gmailRow();
 googleEmail='wrong@example.invalid';let c=await start();assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(c))).url).searchParams.get('reason'),'wrong_account');googleEmail=m.CALENDAR_ACCOUNT;
 tokenScope='https://www.googleapis.com/auth/gmail.send';c=await start();assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(c))).url).searchParams.get('reason'),'calendar_scope');tokenScope=m.CALENDAR_SCOPE;
 calls=[];c=await start();assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(c,c.cookie,'error=access_denied'))).url).searchParams.get('reason'),'google_denied');assert.equal(calls.length,0);
 c=await start();sql.prepare('UPDATE payroll_calendar SET version=version+1 WHERE id=?').run('jac');assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(c))).url).searchParams.get('reason'),'configuration_changed');assert.equal(calls.length,0);
 assert.equal((await m.calendarConfig()).credentials,before.credentials);assert.deepEqual(gmailRow(),gmail);assert.ok(!calls.some(x=>x.url.pathname==='/revoke'));
});

test('el callback distingue fallos de Google y de guardado sin filtrar secretos ni aceptar permisos incompletos',async()=>{
 const before=await m.calendarConfig(),gmail=gmailRow(),logs=[],originalError=console.error;
 console.error=(...args)=>logs.push(args);
 const tokenURL='https://oauth2.googleapis.com/token',accountURL='https://openidconnect.googleapis.com/v1/userinfo';
 const token={access_token:'simulated-calendar-access',refresh_token:'simulated-calendar-refresh',scope:m.CALENDAR_SCOPE};
 const cases=[
  ['calendar_scope',url=>url.href===tokenURL?Response.json({...token,scope:'openid email'}):null],
  ['missing_refresh_token',url=>url.href===tokenURL?Response.json({...token,refresh_token:undefined}):null],
  ['google_token',url=>url.href===tokenURL?Response.json({...token,access_token:''}):null],
  ['google_code_expired',url=>url.href===tokenURL?Response.json({error:'invalid_grant',error_description:'simulated-client-secret'},{status:400}):null],
  ['google_client',url=>url.href===tokenURL?Response.json({error:'invalid_client'},{status:401}):null],
  ['google_client',url=>url.href===tokenURL?Response.json({error:'unauthorized_client'},{status:400}):null],
  ['google_scope',url=>url.href===tokenURL?Response.json({error:'invalid_scope'},{status:400}):null],
  ['google_denied',url=>url.href===tokenURL?Response.json({error:'access_denied'},{status:400}):null],
  ['google_token',url=>url.href===tokenURL?Response.json({error:'untrusted-provider-message simulated-client-secret'},{status:500}):null],
  ['google_token',url=>{if(url.href===tokenURL)throw new Error('simulated-client-secret');return null;}],
  ['account_verification',url=>url.href===accountURL?Response.json({email:m.CALENDAR_ACCOUNT,email_verified:false}):null],
  ['account_verification',url=>url.href===accountURL?Response.json({error:'simulated-calendar-access'},{status:401}):null],
  ['connection_storage',url=>{if(url.href===accountURL){sql.exec("CREATE TEMP TRIGGER reject_calendar_save BEFORE UPDATE ON payroll_calendar BEGIN SELECT RAISE(ABORT,'simulated-storage-secret'); END;");}return null;}],
 ];
 try{
  for(const [reason,hook] of cases){
   const c=await start();calls=[];googleHook=hook;
   const response=await m.callback.GET(callbackRequest(c)),target=new URL(response.headers.get('location'));
   googleHook=null;sql.exec('DROP TRIGGER IF EXISTS reject_calendar_save');
   assert.equal(response.status,303);assert.equal(target.origin,'https://jhonalexcastano.com');assert.equal(target.searchParams.get('calendar'),'error');assert.equal(target.searchParams.get('reason'),reason);
   assert.match(response.headers.get('set-cookie'),/Max-Age=0/);assert.match(response.headers.get('cache-control'),/no-store/);
   assert.equal(sql.prepare('SELECT id FROM payroll_oauth WHERE id=?').get('calendar:'+c.state),undefined);
   const count=calls.length;assert.equal(await m.finishCalendarCallback(callbackRequest(c)),null);assert.equal(calls.length,count);
   assert.deepEqual(await m.calendarConfig(),before);assert.deepEqual(gmailRow(),gmail);
   assert.deepEqual(logs.at(-1),['Calendar authorization failed',{reason,mode:'web'}]);
   for(const secret of [c.state,ownerToken,'simulated-code','simulated-client-secret','simulated-calendar-access','simulated-calendar-refresh','simulated-storage-secret']){assert.ok(!target.href.includes(secret));assert.ok(!JSON.stringify(logs).includes(secret));}
   assert.ok(!calls.some(x=>x.url.pathname==='/revoke'));
  }
 }finally{googleHook=null;console.error=originalError;sql.exec('DROP TRIGGER IF EXISTS reject_calendar_save');}
 assert.match(calendarOAuthMessage('calendar_scope'),/marca la casilla/);
 for(const value of [null,'untrusted-provider-message','__proto__','constructor','toString'])assert.equal(calendarOAuthMessage(value),calendarOAuthMessage(null));
});

test('revalida sesión, cliente y revisión tras consultar Google antes de guardar la conexión',async()=>{
 const before=await m.calendarConfig(),gmail=gmailRow();
 try{
  let c=await start();googleHook=async url=>{if(url.href==='https://openidconnect.googleapis.com/v1/userinfo')sql.prepare('DELETE FROM payroll_sessions WHERE id=?').run(m.tokenHash(ownerToken));return null;};
  assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(c))).url).searchParams.get('reason'),'session_revoked');googleHook=null;ownerToken=await m.makeSession(owner);
  c=await start();googleHook=async url=>{if(url.href==='https://openidconnect.googleapis.com/v1/userinfo')await m.saveMailCredentials('changed.apps.googleusercontent.com','simulated-new-secret');return null;};
  assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(c))).url).searchParams.get('reason'),'configuration_changed');googleHook=null;
  sql.prepare('UPDATE payroll_gmail SET credentials=?,connected_email=?,enabled=? WHERE id=?').run(gmail.credentials,gmail.connected_email,gmail.enabled,'jac');
  c=await start();googleHook=async url=>{if(url.href==='https://openidconnect.googleapis.com/v1/userinfo')sql.prepare('UPDATE payroll_calendar SET version=version+1 WHERE id=?').run('jac');return null;};
  assert.equal(new URL((await m.finishCalendarCallback(callbackRequest(c))).url).searchParams.get('reason'),'configuration_changed');googleHook=null;
  assert.equal((await m.calendarConfig()).credentials,before.credentials);
 }finally{googleHook=null;sql.prepare('UPDATE payroll_gmail SET credentials=?,connected_email=?,enabled=? WHERE id=?').run(gmail.credentials,gmail.connected_email,gmail.enabled,'jac');}
});

test('selección comprueba acceso real y revisión; calendario compartido expande recurrencias y pagina eventos',async()=>{
 const list=await api(ownerToken,{query:'&action=calendars'});assert.equal(list.status,200);assert.equal(list.body.calendars.length,2);assert.equal(list.body.calendars[0].primary,true);
 let revision=(await m.agendaConnection()).revision;
 assert.equal((await api(ownerToken,{action:'select',revision,calendarId:'unknown@group.calendar.google.com'})).status,400);
 assert.equal((await api(ownerToken,{action:'select',revision:revision-1,calendarId:available.id})).status,409);
 const selected=await api(ownerToken,{action:'select',revision,calendarId:available.id});assert.equal(selected.status,200);assert.equal(selected.body.connection.selected.id,available.id);
 calls=[];googleHook=async url=>url.pathname.endsWith('/events')?Response.json(url.searchParams.has('pageToken')?{items:[concert,{...concert,id:'another-instance'}]}:{items:[concert,{id:'cancelled',status:'cancelled'}],nextPageToken:'second'}):null;
 const data=await api(readerToken,{query:'&calendarId=untrusted'});googleHook=null;assert.equal(data.status,200);assert.equal(data.body.events.length,2);assert.equal(data.body.upcoming.length,2);assert.equal(data.body.connection.selected.id,available.id);assert.equal(data.body.days.length,42);assert.equal(data.body.events[0].description,'Prueba & ensayo\n\nAgenda');
 for(const {url,options} of calls.filter(x=>x.url.pathname.endsWith('/events'))){assert.equal(url.pathname,'/calendar/v3/calendars/'+encodeURIComponent(available.id)+'/events');assert.equal(url.searchParams.get('singleEvents'),'true');assert.equal(url.searchParams.get('timeZone'),'America/Bogota');assert.equal(url.searchParams.get('showDeleted'),'false');assert.equal(url.searchParams.get('maxResults'),'100');assert.ok(url.searchParams.get('fields').includes('items(id,status'));assert.equal(options.redirect,'error');assert.equal(options.headers.Authorization,'Bearer simulated-calendar-access');}
 assert.ok(!JSON.stringify(data.body).includes('simulated-calendar-access'));
});

test('cambio concurrente de selección descarta consultas y Google API desactivada muestra solución',async()=>{
 googleHook=async url=>{if(url.pathname.endsWith('/events')){sql.prepare('UPDATE payroll_calendar SET version=version+1 WHERE id=?').run('jac');return Response.json({items:[concert]});}return null;};
 const stale=await api(readerToken);googleHook=null;assert.equal(stale.status,409);
 googleHook=async url=>url.pathname.endsWith('/events')?Response.json({error:{errors:[{reason:'accessNotConfigured'}]}},{status:403}):null;
 const disabled=await api(readerToken);googleHook=null;assert.equal(disabled.status,502);assert.match(disabled.body.error,/Activa Google Calendar API/);
 googleHook=async url=>url.href==='https://oauth2.googleapis.com/token'?Response.json({error:'invalid_grant'},{status:400}):null;
 const expired=await api(readerToken);googleHook=null;assert.match(expired.body.error,/vuelvas a conectar Agenda/);
});

test('desconectar agenda requiere CAS y no revoca ni modifica Gmail ni los eventos',async()=>{
 calls=[];const before=gmailRow(),revision=(await m.agendaConnection()).revision;
 assert.equal((await api(readerToken,{action:'disconnect',revision})).status,403);
 assert.equal((await api(ownerToken,{action:'disconnect',revision:revision-1})).status,409);
 assert.equal((await api(ownerToken,{action:'disconnect',revision})).status,200);
 const result=await api(readerToken);assert.equal(result.body.connection.connected,false);assert.equal(result.body.connection.selected,null);assert.deepEqual(result.body.events,[]);assert.equal(calls.length,0);assert.deepEqual(gmailRow(),before);assert.equal((await m.mailConnection()).connected,true);
});

test('fechas, huso horario, fin exclusivo, texto plano y enlaces limitados evitan agenda engañosa',()=>{
 const grid=m.agendaMonth('2026-10');assert.equal(grid.days[0],'2026-09-28');assert.equal(grid.days[41],'2026-11-08');assert.equal(grid.from,'2026-09-28T00:00:00-05:00');assert.equal(grid.to,'2026-11-09T00:00:00-05:00');
 assert.equal(m.agendaDate(new Date('2026-10-07T04:30:00Z')),'2026-10-06');
 const timed=m.normalizeAgendaEvent(concert);assert.ok(m.agendaEventOnDay(timed,'2026-10-06'));assert.ok(m.agendaEventOnDay(timed,'2026-10-07'));assert.equal(m.agendaEventOnDay(timed,'2026-10-08'),false);
 const trip=m.normalizeAgendaEvent({id:'trip',start:{date:'2026-10-06'},end:{date:'2026-10-08'},htmlLink:'javascript:alert(1)'});assert.ok(m.agendaEventOnDay(trip,'2026-10-07'));assert.equal(m.agendaEventOnDay(trip,'2026-10-08'),false);assert.equal(trip.url,'');
 assert.equal(m.normalizeAgendaEvent({...concert,start:{dateTime:'2026-02-31T12:00:00Z'}}),null);
 assert.equal(m.normalizeAgendaEvent({...concert,end:concert.start}),null);assert.equal(m.normalizeAgendaEvent({...concert,status:'cancelled'}),null);
 for(const url of ['http://calendar.google.com/calendar/','https://other.example.invalid/calendar/','https://calendar.google.com:444/calendar/','https://user:password@calendar.google.com/calendar/'])assert.equal(m.agendaGoogleLink(url),'');
 assert.equal(m.agendaGoogleLink(concert.htmlLink),concert.htmlLink);
});
