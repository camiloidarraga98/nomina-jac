import {env} from 'cloudflare:workers';
import {sourceTransfer,type TransferEnv} from '@/lib/hosting-transfer';
import {authenticatedSession,OWNER_EMAIL} from '@/lib/payroll-auth-store';
import {sessionToken} from '@/lib/payroll-auth-crypto';

export const dynamic='force-dynamic';
export async function POST(req:Request){
 const token=sessionToken(req.headers.get('Cookie')||'');
 const founder=async()=>{const user=await authenticatedSession(token);return !!user&&!user.legacy&&user.email===OWNER_EMAIL&&!!await env.DB.prepare('SELECT id FROM payroll_users WHERE id=? AND owner=1 AND active=1').bind(user.id).first();};
 try{return await sourceTransfer(req,env as TransferEnv,founder);}catch{return new Response(null,{status:404,headers:{'Cache-Control':'no-store'}});}
}
