import {database} from '@/db/raw';
import {calendarClientCredentials,ensureCalendarConfig,calendarConfig,calendarGooglePost,storeCalendarCredentials,CalendarFailure} from './calendar';
import {mailKey} from './payroll-mail';
import {GMAIL_CALLBACK,base64Url,encryptMail,decryptMail} from './payroll-mail-core';
import {tokenHash,sessionToken} from './payroll-auth-crypto';
import {isOwnerEmail} from './payroll-policy';
import {CALENDAR_SCOPE,CALENDAR_ACCOUNT} from './calendar-core';
import type {AccessUser} from './payroll-permissions';
type Context={kind:'calendar';mode:'web'|'native';state:string;url:string;actor:string;userId:string;sessionId:string;nonce:string;guardHash:string;verifier:string;credentials:{clientId:string;clientSecret:string};revision:number};
const random=()=>base64Url(crypto.getRandomValues(new Uint8Array(32)));
const valid=(v:string|null|undefined):v is string=>!!v&&/^[A-Za-z0-9_-]{43}$/.test(v);
const cookieName='__Host-jac_calendar_oauth';
export const calendarCookie=(value:string,age=600)=>`${cookieName}=${value}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${age}`;
async function activeOwner(c:Context){
 const row=await database().prepare('SELECT u.id,u.email,u.owner FROM payroll_sessions s JOIN payroll_users u ON u.id=s.user_id AND u.version=s.user_version WHERE s.id=? AND s.expires_at>? AND u.active=1 AND u.password_hash<>? AND u.id=?').bind(c.sessionId,new Date().toISOString(),'',c.userId).first<{id:string;email:string;owner:number}>();
 return !!row&&row.owner===1&&isOwnerEmail(row.email)&&row.email===c.actor;
}
export async function startCalendarOauth(user:AccessUser,cookies:string,native=false){
 if(!user.isOwner||user.legacy||!isOwnerEmail(user.email))throw new CalendarFailure('Solo Camilo puede conectar Agenda.',403);
 const session=sessionToken(cookies,true);if(!valid(session))throw new CalendarFailure('Inicia sesión de nuevo.',401);
 const credentials=await calendarClientCredentials(),config=await ensureCalendarConfig(),state=random(),verifier=random(),guard=random(),nonce=random();
 const challenge=base64Url(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))));
 const url=new URL('https://accounts.google.com/o/oauth2/v2/auth');url.search=new URLSearchParams({client_id:credentials.clientId,redirect_uri:GMAIL_CALLBACK,response_type:'code',scope:'openid email '+CALENDAR_SCOPE,access_type:'offline',prompt:'consent',include_granted_scopes:'false',login_hint:CALENDAR_ACCOUNT,state,code_challenge:challenge,code_challenge_method:'S256'}).toString();
 const c:Context={kind:'calendar',mode:native?'native':'web',state,url:url.toString(),actor:user.email,userId:user.id,sessionId:tokenHash(session),nonce,guardHash:tokenHash(guard),verifier,credentials,revision:config.version};
 if(!await activeOwner(c))throw new CalendarFailure('La sesión cambió. Inicia sesión de nuevo.',401);
 await database().prepare('DELETE FROM payroll_oauth WHERE expires_at<?').bind(new Date().toISOString()).run();
 if(native){
  const ticket=random();await database().prepare('INSERT INTO payroll_oauth (id,payload,expires_at) VALUES (?,?,?)').bind('calendar-ticket:'+tokenHash(ticket),await encryptMail(c,mailKey()),new Date(Date.now()+120000).toISOString()).run();
  const target=new URL('/api/calendar/connect',GMAIL_CALLBACK);target.searchParams.set('ticket',ticket);return {url:target.toString(),nonce};
 }
 await saveContext(c);return {url:c.url,cookie:calendarCookie(guard)};
}
async function saveContext(c:Context){await database().prepare('INSERT INTO payroll_oauth (id,payload,expires_at) VALUES (?,?,?)').bind('calendar:'+c.state,await encryptMail(c,mailKey()),new Date(Date.now()+600000).toISOString()).run();}
export async function authorizeCalendarTicket(ticket:string|null){
 if(!valid(ticket))throw new CalendarFailure('La autorización no es válida. Vuelve a conectar Agenda.');
 const row=await database().prepare('DELETE FROM payroll_oauth WHERE id=? AND expires_at>=? RETURNING payload').bind('calendar-ticket:'+tokenHash(ticket),new Date().toISOString()).first<{payload:string}>();
 if(!row)throw new CalendarFailure('La autorización venció o ya se utilizó. Vuelve a conectar Agenda.');
 const c=await decryptMail<Context>(row.payload,mailKey());if(c.kind!=='calendar'||c.mode!=='native'||!await activeOwner(c))throw new CalendarFailure('Tu sesión cambió. Inicia sesión de nuevo.');
 const guard=random();c.guardHash=tokenHash(guard);await saveContext(c);return {url:c.url,cookie:calendarCookie(guard)};
}
export async function finishCalendarCallback(req:Request){
 const url=new URL(req.url),state=url.searchParams.get('state');if(!valid(state))return null;
 const db=database(),id='calendar:'+state,row=await db.prepare('SELECT payload,expires_at FROM payroll_oauth WHERE id=?').bind(id).first<{payload:string;expires_at:string}>();if(!row)return null;
 const c=await decryptMail<Context>(row.payload,mailKey());if(c.kind!=='calendar'||c.state!==state)return null;
 const guard=req.headers.get('cookie')?.split(';').map(s=>s.trim()).find(s=>s.startsWith(cookieName+'='))?.slice(cookieName.length+1);
 let result='error';
 const browserSession=c.mode==='native'||tokenHash(sessionToken(req.headers.get('cookie')||'',true)||'')===c.sessionId;
 if(valid(guard)&&tokenHash(guard)===c.guardHash&&browserSession){
  const claimed=await db.prepare('DELETE FROM payroll_oauth WHERE id=? AND payload=? RETURNING payload').bind(id,row.payload).first();
  if(claimed&&row.expires_at>=new Date().toISOString()&&await activeOwner(c)&&!url.searchParams.has('error')){
   const code=url.searchParams.get('code');
   if(code&&code.length<=4096){try{
    const current=await calendarConfig(),client=await calendarClientCredentials();
    if(current?.version!==c.revision||JSON.stringify(client)!==JSON.stringify(c.credentials))throw new Error('Configuración cambiada');
    const token=await calendarGooglePost({client_id:c.credentials.clientId,client_secret:c.credentials.clientSecret,code,code_verifier:c.verifier,grant_type:'authorization_code',redirect_uri:GMAIL_CALLBACK});
    if(typeof token.access_token!=='string'||typeof token.refresh_token!=='string'||!String(token.scope||'').split(' ').includes(CALENDAR_SCOPE))throw new Error('Permiso incompleto');
    const response=await fetch('https://openidconnect.googleapis.com/v1/userinfo',{headers:{Authorization:'Bearer '+token.access_token},redirect:'error',signal:AbortSignal.timeout(15000)});
    if(!response.ok)throw new Error('Cuenta no verificada');
    const account=await response.json() as {email?:string;email_verified?:boolean};
    if(account.email?.toLowerCase()!==CALENDAR_ACCOUNT||!account.email_verified||!await activeOwner(c))throw new Error('Cuenta o sesión inválida');
    if(JSON.stringify(await calendarClientCredentials())!==JSON.stringify(c.credentials))throw new Error('Configuración cambiada');
    await storeCalendarCredentials({...c.credentials,refreshToken:token.refresh_token},c.revision);result='connected';
   }catch{result='error';}}
  }
 }
 const target=new URL(c.mode==='native'?'jacnomina://calendar':'https://jhonalexcastano.com/');target.search=new URLSearchParams({...(c.mode==='native'?{result,nonce:c.nonce}:{calendar:result})}).toString();
 return {url:target.toString(),cookie:calendarCookie('',0)};
}
