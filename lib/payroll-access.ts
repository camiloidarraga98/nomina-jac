import {getChatGPTUser} from '@/app/chatgpt-auth';
import {headers} from 'next/headers';
import {ownAuthReady,authenticatedSession,OWNER_EMAIL} from './payroll-auth-store';
import {sessionToken} from './payroll-auth-crypto';
import {permissionKeys,defaultPermissionKeys,type AccessUser} from './payroll-permissions';
const allowed=[OWNER_EMAIL,'info@jacmusic.co','contabilidad@jacmusic.co'];
export async function payrollUser():Promise<AccessUser|null>{
 const h=await headers(),local=/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(h.get('host')||'');
 const session=await authenticatedSession(sessionToken(h.get('cookie')||'',!local));if(session)return session;
 if(await ownAuthReady())return null;
 const user=await getChatGPTUser();if(user&&allowed.includes(user.email.trim().toLowerCase()))return {...user,email:user.email.trim().toLowerCase(),id:'legacy:'+user.email,username:user.email,isOwner:user.email.trim().toLowerCase()===OWNER_EMAIL,permissions:defaultPermissionKeys,legacy:true};
 if(process.env.NODE_ENV==='development'&&local)return {email:OWNER_EMAIL,id:'preview',username:'camilo',displayName:'Vista previa · Camilo',fullName:null,isOwner:true,permissions:permissionKeys,legacy:true};
 return null;
}
export const payrollHeaders={'Cache-Control':'private, no-store, max-age=0','X-Robots-Tag':'noindex, nofollow','Vary':'Cookie','X-Content-Type-Options':'nosniff','Referrer-Policy':'same-origin'};
