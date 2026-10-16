import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard,mediaFile} from '@/lib/media-drive';
import {MediaFailure} from '@/lib/media-core';
export const dynamic='force-dynamic';
export async function GET(req:Request){const user=await payrollUser();if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers:payrollHeaders});try{const q=new URL(req.url).searchParams,response=await mediaFile(mediaGuard(req,user),q.get('id')||'',q.get('thumbnail')==='1',req.headers.get('range'));for(const [key,value] of Object.entries(payrollHeaders))response.headers.set(key,value);return response;}catch(e){return Response.json({error:e instanceof MediaFailure?e.message:'No pudimos abrir el archivo.'},{status:e instanceof MediaFailure?e.status:503,headers:payrollHeaders});}}
