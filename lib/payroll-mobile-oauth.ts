import {database} from '@/db/raw';
import {startMailOauth,finishMailOauth,mailKey} from './payroll-mail';
import {encryptMail,decryptMail,base64Url,GMAIL_CALLBACK} from './payroll-mail-core';
import {sessionToken,tokenHash} from './payroll-auth-crypto';
import {accountAdministrator,type UserRow} from './payroll-auth-store';
import type {AccessUser} from './payroll-permissions';

type NativeContext={kind:'native-gmail';state:string;url:string;actor:string;userId:string;sessionId:string;nonce:string;guardHash?:string};
const random=()=>base64Url(crypto.getRandomValues(new Uint8Array(32)));
const valid=(value:string|null):value is string=>!!value&&/^[A-Za-z0-9_-]{43}$/.test(value);
const browserCookie='__Host-jac_native_gmail';
export const nativeGmailCookie=(value:string,maxAge=600)=>`${browserCookie}=${value}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAge}`;

async function activeOwner(context:NativeContext){
 const row=await database().prepare('SELECT u.* FROM payroll_sessions s JOIN payroll_users u ON u.id=s.user_id AND u.version=s.user_version WHERE s.id=? AND (s.persistent=1 OR s.expires_at>?) AND u.active=1 AND u.password_hash<>? AND u.id=?').bind(context.sessionId,new Date().toISOString(),'',context.userId).first<UserRow>();
 return !!row&&accountAdministrator(row)&&row.email===context.actor;
}

export async function startNativeMailOauth(user:AccessUser,cookies:string){
 if(!user.isOwner||user.legacy||user.itinerariesOnly||user.mediaOnly)throw new Error('Solo un administrador puede conectar Gmail.');
 const token=sessionToken(cookies,true);if(!valid(token))throw new Error('Inicia sesión de nuevo.');
 const oauth=await startMailOauth(user.email),ticket=random(),nonce=random();
 const context:NativeContext={kind:'native-gmail',...oauth,actor:user.email,userId:user.id,sessionId:tokenHash(token),nonce};
 if(!await activeOwner(context))throw new Error('Tu sesión cambió. Inicia sesión de nuevo.');
 await database().prepare('INSERT INTO payroll_oauth (id,payload,expires_at) VALUES (?,?,?)').bind('handoff:'+tokenHash(ticket),await encryptMail(context,mailKey()),new Date(Date.now()+120000).toISOString()).run();
 const url=new URL('/api/mobile/gmail',GMAIL_CALLBACK);url.searchParams.set('ticket',ticket);
 return {url:url.toString(),nonce};
}

// A one-time two-minute ticket gives the browser a Gmail-only guard cookie.
// It never gives Safari a payroll session or exposes any session/Google token.
export async function authorizeNativeMail(ticket:string|null){
 if(!valid(ticket))throw new Error('La autorización no es válida. Vuelve a conectar Gmail.');
 const row=await database().prepare('DELETE FROM payroll_oauth WHERE id=? AND expires_at>=? RETURNING payload').bind('handoff:'+tokenHash(ticket),new Date().toISOString()).first<{payload:string}>();
 if(!row)throw new Error('La autorización venció o ya se utilizó. Vuelve a conectar Gmail.');
 const context=await decryptMail<NativeContext>(row.payload,mailKey());
 if(context.kind!=='native-gmail'||!await activeOwner(context))throw new Error('La sesión cambió. Inicia sesión de nuevo.');
 const guard=random();context.guardHash=tokenHash(guard);
 await database().prepare('INSERT INTO payroll_oauth (id,payload,expires_at) VALUES (?,?,?)').bind('native:'+context.state,await encryptMail(context,mailKey()),new Date(Date.now()+600000).toISOString()).run();
 return {url:context.url,cookie:nativeGmailCookie(guard)};
}

export async function finishNativeMailOauth(req:Request){
 const url=new URL(req.url),state=url.searchParams.get('state');if(!valid(state))return null;
 const db=database(),id='native:'+state;
 const row=await db.prepare('SELECT payload,expires_at FROM payroll_oauth WHERE id=?').bind(id).first<{payload:string;expires_at:string}>();
 if(!row)return null;
 const context=await decryptMail<NativeContext>(row.payload,mailKey());
 if(context.kind!=='native-gmail'||context.state!==state||!valid(context.nonce))return null;
 const guard=req.headers.get('cookie')?.split(';').map(x=>x.trim()).find(x=>x.startsWith(browserCookie+'='))?.slice(browserCookie.length+1)??'';
 let result='error';
 // Do not consume another browser's valid context when its guard is absent.
 if(valid(guard)&&tokenHash(guard)===context.guardHash){
  const claimed=await db.prepare('DELETE FROM payroll_oauth WHERE id=? AND payload=? RETURNING payload').bind(id,row.payload).first<{payload:string}>();
  if(claimed&&row.expires_at>=new Date().toISOString()&&await activeOwner(context)&&!url.searchParams.has('error')){
   const code=url.searchParams.get('code');
   if(code&&code.length<=4096){try{await finishMailOauth(state,code,context.actor);result='connected';}catch{result='error';}}
  }
 }
 const callback=new URL('jacnomina://gmail');callback.search=new URLSearchParams({result,nonce:context.nonce}).toString();
 return {url:callback.toString(),cookie:nativeGmailCookie('',0)};
}
