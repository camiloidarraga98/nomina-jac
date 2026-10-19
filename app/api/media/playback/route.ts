import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard} from '@/lib/media-drive';
import {MediaFailure} from '@/lib/media-core';
import {playbackInfo,playbackAsset} from '@/lib/media-stream';
export const dynamic='force-dynamic';
export async function GET(req:Request){try{
 const url=new URL(req.url),q=url.searchParams;
 if(q.has('lease'))return await playbackAsset(q.get('lease')||'',q.get('asset')||'',req.headers.get('range'));
 const user=await payrollUser();if(!user||user.legacy)throw new MediaFailure('Inicia sesión con tu cuenta de JAC.',401);
 const g=mediaGuard(req,user);return Response.json(await playbackInfo(g,q.get('id')||'',url.origin,{actorID:user.id,sessionID:String(g.bindings[0])},true),{headers:payrollHeaders});
 }catch(error){return Response.json({error:error instanceof MediaFailure?error.message:'No se pudo abrir la reproducción.'},{status:error instanceof MediaFailure?error.status:503,headers:payrollHeaders});}}
