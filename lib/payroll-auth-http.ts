import {z} from 'zod';
import {createHmac} from 'node:crypto';
import type {AccessUser} from './payroll-permissions';
import {ownAuthReady,passwordLogin,rateLimit,authKey,attendancePilotOrigin,attendanceIdentity,bootstrapOwner,activateUser,changePassword,makeSession,revokeSession,sessionIsPersistent} from '@/lib/payroll-auth-store';
import {sessionCookie,sessionToken,passwordIssue,SESSION_SECONDS} from '@/lib/payroll-auth-crypto';
export const payrollHeaders={'Cache-Control':'private, no-store, max-age=0','X-Robots-Tag':'noindex, nofollow','Vary':'Cookie','X-Content-Type-Options':'nosniff','Referrer-Policy':'same-origin'};
const reply=(body:unknown,status=200,cookie?:string)=>Response.json(body,{status,headers:{...payrollHeaders,...(cookie?{'Set-Cookie':cookie}:{})}});
const passwordSchema=z.string().min(1);
const usernameSchema=z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9._-]{2,39}$/);
export async function handlePayrollAuth(req:Request, payrollUser:()=>Promise<AccessUser|null>){
 if(req.headers.get('origin')!==new URL(req.url).origin)return reply({error:'Origen no autorizado.'},403);
 const secure=!/^(localhost|127\.0\.0\.1)$/.test(new URL(req.url).hostname);
 const pilotBrowser=attendancePilotOrigin(new URL(req.url))&&!req.headers.get('user-agent')?.startsWith('JACNomina-');
 function withOfflineScope(response:Response,id?:string,persistent=false){
  if(pilotBrowser){
   const value=id?id+'.'+createHmac('sha256',authKey()).update('attendance-offline-v1:'+id).digest('base64url'):'';
   const expiry=!id?'; Max-Age=0':persistent?'':'; Max-Age='+SESSION_SECONDS;
   response.headers.append('Set-Cookie',`jac_attendance_scope=${value}; Path=/asistencia/; SameSite=Strict${secure?'; Secure':''}${expiry}`);
  }
  return response;
 }
 try{const text=await req.text();if(text.length>4000)return reply({error:'Solicitud demasiado grande.'},413);const body=JSON.parse(text);
 if(body.action==='logout'){await revokeSession(sessionToken(req.headers.get('cookie')||'',secure),body.notificationDeviceId);return withOfflineScope(reply({ok:true},200,sessionCookie('',secure,0)));}
 if(body.action==='login'){const input=z.object({username:z.string().trim().toLowerCase().min(1).max(254),password:passwordSchema,keepSignedIn:z.boolean().optional().default(false)}).safeParse(body);if(!input.success)return reply({error:'Usuario o contraseña incorrectos.'},401);await rateLimit(req,input.data.username);const row=await passwordLogin(input.data.username,input.data.password);const kiosk=row&&attendanceIdentity(row);
 if(!row||(row.attendance_role&&(!kiosk||!attendancePilotOrigin(new URL(req.url)))))return reply({error:'Usuario o contraseña incorrectos.'},401);
 const session=await makeSession(row.id,input.data.keepSignedIn);
 return withOfflineScope(reply({ok:true,...(kiosk?{attendance:kiosk}:{})},200,sessionCookie(session,secure,input.data.keepSignedIn?null:undefined)),kiosk?.id,input.data.keepSignedIn);}
 if(body.action==='activate'){const input=z.object({token:z.string().regex(/^[A-Za-z0-9_-]{43}$/),password:passwordSchema}).safeParse(body);if(!input.success)return reply({error:'Revisa el enlace e ingresa una contraseña.'},400);await rateLimit(req,'activation:'+input.data.token);const id=await activateUser(input.data.token,input.data.password);return withOfflineScope(reply({ok:true},200,sessionCookie(await makeSession(id),secure)));}
 const user=await payrollUser();if(!user)return reply({error:'Inicia sesión para continuar.'},401);
 if(body.action==='bootstrap'){if(!user.isOwner||!user.legacy||await ownAuthReady())return reply({error:'Solo Camilo puede activar el administrador, una sola vez.'},403);const input=z.object({username:usernameSchema,password:passwordSchema}).safeParse(body);if(!input.success)return reply({error:'Usa un usuario de 3 a 40 caracteres (letras, números, punto, guion). Ingresa una contraseña.'},400);const id=await bootstrapOwner(input.data.username,input.data.password);return withOfflineScope(reply({ok:true},200,sessionCookie(await makeSession(id),secure)));}
 if(body.action==='password'){if(user.legacy)return reply({error:'Primero activa tu cuenta propia.'},400);const input=z.object({currentPassword:passwordSchema,password:passwordSchema}).safeParse(body);if(!input.success)return reply({error:passwordIssue(body.password||'')||'Ingresa la contraseña actual.'},400);await rateLimit(req,'password:'+user.id);const persistent=await sessionIsPersistent(sessionToken(req.headers.get('cookie')||'',secure));const id=await changePassword(user,input.data.currentPassword,input.data.password);return reply({ok:true},200,sessionCookie(await makeSession(id,persistent),secure,persistent?null:undefined));}
 return reply({error:'Acción inválida.'},400);
 }catch(e){if(e instanceof Error&&e.message==='RATE_LIMIT')return reply({error:'Demasiados intentos. Espera 15 minutos antes de volver a intentarlo.'},429);console.error('Authentication operation failed');return reply({error:'No se pudo completar la operación. Revisa los datos e intenta de nuevo.'},400);}
}
