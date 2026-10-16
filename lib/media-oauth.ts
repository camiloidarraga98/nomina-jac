import {database} from '@/db/raw';
import {calendarClientCredentials,calendarGoogleFetch,calendarGooglePost} from './calendar';
import {mailKey} from './payroll-mail';
import {encryptMail,decryptMail,base64Url,GMAIL_CALLBACK} from './payroll-mail-core';
import {tokenHash,sessionToken} from './payroll-auth-crypto';
import {MEDIA_ROOT_ID,MEDIA_SCOPE,MEDIA_FOLDER_MIME,MediaFailure,canConnectMedia} from './media-core';
import {mediaGuard,mediaStoredGuard,mediaGuardActive,ensureMediaConfig,mediaConfig,storeMediaConnection} from './media-drive';
import type {AccessUser} from './payroll-permissions';
type Context={kind:'jac-media';state:string;actorID:string;sessionID:string;guardHash:string;verifier:string;credentials:{clientId:string;clientSecret:string};revision:number};
const random=()=>base64Url(crypto.getRandomValues(new Uint8Array(32))),valid=(s:unknown):s is string=>typeof s==='string'&&/^[A-Za-z0-9_-]{43}$/.test(s),cookieName='__Host-jac_media_oauth';
const cookie=(value:string,age=600)=>`${cookieName}=${value}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${age}`;
export async function startMediaOauth(req:Request,user:AccessUser){if(!canConnectMedia(user))throw new MediaFailure('Solo Camilo puede conectar la carpeta compartida de fotografías.',403);const guard=mediaGuard(req,user,'connect'),credentials=await calendarClientCredentials(),config=await ensureMediaConfig(),state=random(),verifier=random(),browserGuard=random(),sessionID=guard.bindings[0] as string;if(!await mediaGuardActive(guard))throw new MediaFailure('Tu sesión cambió.',403);const challenge=base64Url(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier)))),url=new URL('https://accounts.google.com/o/oauth2/v2/auth');url.search=new URLSearchParams({client_id:credentials.clientId,redirect_uri:GMAIL_CALLBACK,response_type:'code',scope:'openid email '+MEDIA_SCOPE,access_type:'offline',prompt:'consent',include_granted_scopes:'true',login_hint:'jacmusicestudios@gmail.com',state,code_challenge:challenge,code_challenge_method:'S256'}).toString();const context:Context={kind:'jac-media',state,actorID:user.id,sessionID,guardHash:tokenHash(browserGuard),verifier,credentials,revision:config.version};await database().prepare('INSERT INTO payroll_oauth(id,payload,expires_at) VALUES (?,?,?)').bind('jac-media:'+state,await encryptMail(context,mailKey()),new Date(Date.now()+600000).toISOString()).run();return {url:url.toString(),cookie:cookie(browserGuard)};}
export type MediaOAuthReason='browser_guard_missing'|'browser_guard_mismatch'|'web_session_missing'|'web_session_changed'|'authorization_used'|'expired'|'session_revoked'|'google_denied'|'missing_code'|'configuration_changed'|'google_token'|'google_account'|'folder_access'|'connection_storage';
export async function finishMediaOauth(req:Request){
 const url=new URL(req.url),state=url.searchParams.get('state');if(!valid(state))return null;
 const db=database(),id='jac-media:'+state,row=await db.prepare('SELECT payload,expires_at FROM payroll_oauth WHERE id=?').bind(id).first<{payload:string;expires_at:string}>();if(!row)return null;
 const context=await decryptMail<Context>(row.payload,mailKey());if(context.kind!=='jac-media'||context.state!==state)return null;
 let result='error',reason:MediaOAuthReason='browser_guard_missing';
 try{
  const browserGuard=req.headers.get('cookie')?.split(';').map(v=>v.trim()).find(v=>v.startsWith(cookieName+'='))?.slice(cookieName.length+1);
  if(!valid(browserGuard))throw new MediaFailure('La protección de este navegador no está disponible.');
  reason='browser_guard_mismatch';if(tokenHash(browserGuard)!==context.guardHash)throw new MediaFailure('El navegador cambió durante la autorización.');
  const session=sessionToken(req.headers.get('cookie')||'',true);
  reason='web_session_missing';if(!valid(session))throw new MediaFailure('Inicia sesión de nuevo en JAC.');
  reason='web_session_changed';if(tokenHash(session)!==context.sessionID)throw new MediaFailure('La sesión cambió durante la autorización.');
  reason='authorization_used';const claimed=await db.prepare('DELETE FROM payroll_oauth WHERE id=? AND payload=? RETURNING id').bind(id,row.payload).first();if(!claimed)throw new MediaFailure('Esta autorización ya fue utilizada.');
  reason='expired';if(row.expires_at<new Date().toISOString())throw new MediaFailure('La autorización venció.');
  const guard=mediaStoredGuard(context.sessionID,context.actorID,'connect');
  reason='session_revoked';if(!await mediaGuardActive(guard))throw new MediaFailure('La sesión o el permiso cambió.');
  reason='google_denied';if(url.searchParams.has('error'))throw new MediaFailure('Google no autorizó la conexión.');
  const code=url.searchParams.get('code');reason='missing_code';if(!code||code.length>4096)throw new MediaFailure('Google no entregó la autorización.');
  reason='configuration_changed';if((await mediaConfig())?.version!==context.revision||JSON.stringify(await calendarClientCredentials())!==JSON.stringify(context.credentials))throw new MediaFailure('La configuración cambió.');
  reason='google_token';const token=await calendarGooglePost({client_id:context.credentials.clientId,client_secret:context.credentials.clientSecret,code,code_verifier:context.verifier,grant_type:'authorization_code',redirect_uri:GMAIL_CALLBACK});
  if(typeof token.access_token!=='string'||typeof token.refresh_token!=='string'||typeof token.scope!=='string'||!token.scope.split(/\s+/).includes(MEDIA_SCOPE))throw new MediaFailure('Falta el permiso para Drive.');
  reason='google_account';const response=await calendarGoogleFetch('https://openidconnect.googleapis.com/v1/userinfo',{headers:{Authorization:'Bearer '+token.access_token}}),account=await response.json() as {email?:string;email_verified?:boolean};
  if(!response.ok||!account.email_verified||account.email?.toLowerCase()!=='jacmusicestudios@gmail.com')throw new MediaFailure('Usa jacmusicestudios@gmail.com.');
  reason='folder_access';const folderResponse=await calendarGoogleFetch('https://www.googleapis.com/drive/v3/files/'+MEDIA_ROOT_ID+'?'+new URLSearchParams({fields:'id,mimeType,trashed,capabilities(canAddChildren)',supportsAllDrives:'true'}),{headers:{Authorization:'Bearer '+token.access_token}}),folder=await folderResponse.json() as {id?:string;mimeType?:string;trashed?:boolean;capabilities?:{canAddChildren?:boolean}};
  if(!folderResponse.ok||folder.id!==MEDIA_ROOT_ID||folder.mimeType!==MEDIA_FOLDER_MIME||folder.trashed||folder.capabilities?.canAddChildren!==true)throw new MediaFailure('La cuenta de JAC necesita acceso de edición a la carpeta de fotografías.');
  reason='configuration_changed';if(JSON.stringify(await calendarClientCredentials())!==JSON.stringify(context.credentials))throw new MediaFailure('La configuración cambió.');
  reason='connection_storage';await storeMediaConnection({...context.credentials,refreshToken:token.refresh_token,scopes:token.scope.split(/\s+/)},context.revision,guard);result='connected';
 }catch{console.error('Media Drive authorization failed',{reason});}
 return {url:'https://jhonalexcastano.com/fotografia?drive='+result+(result==='error'?'&reason='+reason:''),cookie:cookie('',0)};
}
