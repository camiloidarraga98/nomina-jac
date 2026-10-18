import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard} from '@/lib/media-drive';
import {MediaFailure,readMediaJson} from '@/lib/media-core';
import {mediaR2Connection,saveMediaR2Connection,activateMediaR2} from '@/lib/media-r2';
export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});
async function actor(req:Request){const user=await payrollUser();if(!user||user.legacy)throw new MediaFailure('Inicia sesión con tu cuenta de JAC.',401);return mediaGuard(req,user,'connect');}
export async function GET(req:Request){try{return reply(await mediaR2Connection(await actor(req)));}catch(e){return failure(e);}}
export async function POST(req:Request){try{if(req.headers.get('origin')!==new URL(req.url).origin)throw new MediaFailure('Origen no autorizado.',403);const g=await actor(req),body=await readMediaJson(req);return reply(body.action==='activateNewCollection'?await activateMediaR2(g,body):await saveMediaR2Connection(g,body));}catch(e){return failure(e);}}
function failure(e:unknown){return reply({error:e instanceof MediaFailure?e.message:'No pudimos guardar la conexión de almacenamiento.'},e instanceof MediaFailure?e.status:503);}
