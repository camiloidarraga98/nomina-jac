import {env} from 'cloudflare:workers';
import {authenticatedSession,OWNER_EMAIL} from '@/lib/payroll-auth-store';
import {sessionToken} from '@/lib/payroll-auth-crypto';
export const dynamic='force-dynamic';
export async function POST(req:Request){
 const headers={'Cache-Control':'private, no-store','X-Robots-Tag':'noindex, nofollow'};
 const missing=()=>new Response(null,{status:404,headers});
 try{
  const e=env as typeof env&{JAC_TRANSFER_PUBLIC_KEY?:string;JAC_TRANSFER_EXPIRES?:string},expiry=Date.parse(e.JAC_TRANSFER_EXPIRES||'');
  if(req.headers.get('Origin')!==new URL(req.url).origin||!e.JAC_TRANSFER_PUBLIC_KEY||!Number.isFinite(expiry)||expiry<=Date.now()||expiry-Date.now()>2*60*60*1000)return missing();
  const token=sessionToken(req.headers.get('Cookie')||'');
  const founder=async()=>{const user=await authenticatedSession(token);return !!user&&!user.legacy&&user.email===OWNER_EMAIL&&!!await env.DB.prepare('SELECT id FROM payroll_users WHERE id=? AND owner=1 AND active=1').bind(user.id).first();};
  if(!await founder())return missing();
  const objects:{key:string;size:number;etag:string}[]=[];let cursor:string|undefined;
  do{const page=await env.BUCKET.list({limit:100,cursor});objects.push(...page.objects.map(o=>({key:o.key,size:o.size,etag:o.etag})));if(objects.length>2000)return missing();cursor=page.truncated?page.cursor:undefined;if(!await founder())return missing();}while(cursor);
  return Response.json({objects},{headers});
 }catch{return missing();}
}
