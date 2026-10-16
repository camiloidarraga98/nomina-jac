import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard,mediaFile,mediaMetadata} from '@/lib/media-drive';
import {usesMediaR2,r2Metadata,r2File} from '@/lib/media-r2-gallery';
import {MediaFailure} from '@/lib/media-core';
export const dynamic='force-dynamic';
export async function GET(req:Request){const user=await payrollUser();if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de JAC.'},{status:401,headers:payrollHeaders});try{const q=new URL(req.url).searchParams;if(q.get('metadata')==='1')return Response.json(await (await usesMediaR2()?r2Metadata:mediaMetadata)(mediaGuard(req,user),q.get('id')||''),{headers:payrollHeaders});const response=await (await usesMediaR2()?r2File:mediaFile)(mediaGuard(req,user),q.get('id')||'',q.get('thumbnail')==='1',req.headers.get('range'),q.get('revision')||undefined);for(const [key,value] of Object.entries(payrollHeaders))response.headers.set(key,value);return response;}catch(e){return Response.json({error:e instanceof MediaFailure?e.message:'No pudimos abrir el archivo.'},{status:e instanceof MediaFailure?e.status:503,headers:payrollHeaders});}}
