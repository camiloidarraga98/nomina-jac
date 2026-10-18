import {createHmac} from 'node:crypto';
import {headers} from 'next/headers';
import {authKey} from './payroll-auth-store';
import {sessionToken} from './payroll-auth-crypto';
import {canReadMedia} from './media-core';
import type {AccessUser} from './payroll-permissions';

// A purpose-separated encryption capability; never expose the session token.
export async function mediaCacheContext(user:AccessUser){
 if(!canReadMedia(user))return null;
 const h=await headers(),local=/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(h.get('host')||'');
 const token=sessionToken(h.get('cookie')||'',!local);if(!/^[A-Za-z0-9_-]{43}$/.test(token))return null;
 const derive=(purpose:string)=>createHmac('sha256',authKey()).update(JSON.stringify(['jac-media-offline-v1',purpose,user.id,token])).digest('base64url');
 return {scope:derive('scope'),key:derive('encryption')};
}
