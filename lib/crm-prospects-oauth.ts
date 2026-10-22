import {database} from '@/db/raw';
import {calendarClientCredentials,calendarGooglePost,calendarGoogleFetch} from './calendar';
import {mailKey} from './payroll-mail';
import {GMAIL_SENDER,GMAIL_CALLBACK,base64Url,encryptMail,decryptMail} from './payroll-mail-core';
import {tokenHash,sessionToken} from './payroll-auth-crypto';
import {crmStoredGuard} from './crm-access';
import {guardActive} from './crm-store';
import {CrmFailure,canCrm} from './crm-core';
import type {AccessUser} from './payroll-permissions';
import {PROSPECT_SEND_SCOPE,PROSPECT_METADATA_SCOPE,prospectMailConfig,ensureProspectMailConfig,storeProspectMailCredentials} from './crm-prospects-mail';

type Context={kind:'crm-prospects-mail';state:string;actorID:string;sessionID:string;guardHash:string;verifier:string;credentials:{clientId:string;clientSecret:string};revision:number};
const random=()=>base64Url(crypto.getRandomValues(new Uint8Array(32)));
const valid=(value:unknown):value is string=>typeof value==='string'&&/^[A-Za-z0-9_-]{43}$/.test(value);
const cookieName='__Host-jac_crm_prospects_oauth';
const cookie=(value:string,age=600)=>`${cookieName}=${value}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${age}`;
function browserGuard(cookies:string){const values=cookies.split(';').map(value=>value.trim()).filter(value=>value.startsWith(cookieName+'='));return values.length===1?values[0].slice(cookieName.length+1):'';}

export async function startProspectMailOauth(user:AccessUser,cookies:string){
 if(!canCrm(user))throw new CrmFailure('Solo administradores del CRM pueden conectar el seguimiento.',403);
 const session=sessionToken(cookies,true);if(!valid(session))throw new CrmFailure('Inicia sesión de nuevo para autorizar el seguimiento.',401);
 const sessionID=tokenHash(session),actor=crmStoredGuard(sessionID,user.id);if(!await guardActive(actor))throw new CrmFailure('Tu sesión cambió.',403);
 const credentials=await calendarClientCredentials(),config=await ensureProspectMailConfig(actor),state=random(),verifier=random(),guard=random();
 const challenge=base64Url(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier)))),url=new URL('https://accounts.google.com/o/oauth2/v2/auth');
 url.search=new URLSearchParams({client_id:credentials.clientId,redirect_uri:GMAIL_CALLBACK,response_type:'code',scope:'openid email '+PROSPECT_SEND_SCOPE+' '+PROSPECT_METADATA_SCOPE,access_type:'offline',prompt:'consent',include_granted_scopes:'false',login_hint:GMAIL_SENDER,state,code_challenge:challenge,code_challenge_method:'S256'}).toString();
 const context:Context={kind:'crm-prospects-mail',state,actorID:user.id,sessionID,guardHash:tokenHash(guard),verifier,credentials,revision:config.version};
 actor.bindings=[actor.bindings[0],actor.bindings[1],new Date().toISOString()];
 const inserted=await database().prepare(`INSERT INTO payroll_oauth(id,payload,expires_at) SELECT ?,?,? WHERE ${actor.sql}`).bind('crm-prospects:'+state,await encryptMail(context,mailKey()),new Date(Date.now()+600000).toISOString(),...actor.bindings).run();
 if(inserted.meta.changes!==1)throw new CrmFailure('Tu sesión cambió.',403);
 return {url:url.toString(),cookie:cookie(guard)};
}
export async function finishProspectMailOauth(req:Request){
 const url=new URL(req.url),state=url.searchParams.get('state');if(!valid(state))return null;
 const db=database(),id='crm-prospects:'+state,row=await db.prepare('SELECT payload,expires_at FROM payroll_oauth WHERE id=?').bind(id).first<{payload:string;expires_at:string}>();if(!row)return null;
 const context=await decryptMail<Context>(row.payload,mailKey());if(context.kind!=='crm-prospects-mail'||context.state!==state)return null;
 let result='error',reason='authorization';
 try{
  const guard=browserGuard(req.headers.get('cookie')??'');if(!valid(guard)||tokenHash(guard)!==context.guardHash||tokenHash(sessionToken(req.headers.get('cookie')??'',true))!==context.sessionID)throw new CrmFailure('El navegador o la sesión cambió.');
  const claimed=await db.prepare('DELETE FROM payroll_oauth WHERE id=? AND payload=? RETURNING id').bind(id,row.payload).first();if(!claimed||row.expires_at<=new Date().toISOString())throw new CrmFailure('La autorización venció o ya fue utilizada.');
  const actor=crmStoredGuard(context.sessionID,context.actorID);if(!await guardActive(actor))throw new CrmFailure('Tu sesión cambió.',403);
  if(url.searchParams.has('error'))throw new CrmFailure('Google no autorizó el seguimiento.');
  const code=url.searchParams.get('code');if(!code||code.length>4096)throw new CrmFailure('Google no entregó la autorización.');
  if((await prospectMailConfig())?.version!==context.revision||JSON.stringify(await calendarClientCredentials())!==JSON.stringify(context.credentials))throw new CrmFailure('La configuración cambió.');
  reason='google-token';const token=await calendarGooglePost({client_id:context.credentials.clientId,client_secret:context.credentials.clientSecret,code,code_verifier:context.verifier,grant_type:'authorization_code',redirect_uri:GMAIL_CALLBACK});
  const scopes=typeof token.scope==='string'?token.scope.split(/\s+/):[];
  if(typeof token.access_token!=='string'||typeof token.refresh_token!=='string'||!scopes.includes(PROSPECT_SEND_SCOPE)||!scopes.includes(PROSPECT_METADATA_SCOPE))throw new CrmFailure('Google no concedió los permisos de envío y seguimiento.');
  reason='google-account';const response=await calendarGoogleFetch('https://openidconnect.googleapis.com/v1/userinfo',{headers:{Authorization:'Bearer '+token.access_token}}),account=await response.json() as {email?:string;email_verified?:boolean};
  if(!response.ok||account.email_verified!==true||account.email?.toLowerCase()!==GMAIL_SENDER)throw new CrmFailure('Autoriza la cuenta compartida de Gmail de JAC.');
  reason='storage';if(JSON.stringify(await calendarClientCredentials())!==JSON.stringify(context.credentials))throw new CrmFailure('La configuración cambió.');
  await storeProspectMailCredentials({...context.credentials,refreshToken:token.refresh_token,scopes},context.revision,actor);result='connected';
 }catch{console.error('CRM prospect mail authorization failed',{reason});}
 return {url:'https://jhonalexcastano.com/crm?seccion=prospectos&tracking='+result,cookie:cookie('',0)};
}
