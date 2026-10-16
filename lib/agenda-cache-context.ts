import {createHmac} from 'node:crypto';
import {headers} from 'next/headers';
import {authKey} from './payroll-auth-store';
import {sessionToken} from './payroll-auth-crypto';
import type {AccessUser} from './payroll-permissions';
// A separate, read-only encryption capability. Never expose the login token,
// authentication key, or Google credentials to browser storage.
export function deriveAgendaCacheContext(userID:string,token:string,secret:string){
 if(!/^[A-Za-z0-9_-]{43}$/.test(token))return null;
 const derive=(purpose:string)=>createHmac('sha256',secret).update(JSON.stringify(['jac-agenda-cache-v1',purpose,userID,token])).digest('base64url');
 return {scope:derive('scope'),key:derive('encryption')};
}
export async function agendaCacheContext(user:AccessUser){
 if(user.legacy||user.mediaOnly)return null;
 const h=await headers(),local=/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(h.get('host')||'');
 return deriveAgendaCacheContext(user.id,sessionToken(h.get('cookie')||'',!local),authKey());
}
