import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard,mediaFeed,createMediaFolder} from '@/lib/media-drive';
import {startMediaOauth} from '@/lib/media-oauth';
import {MediaFailure,MEDIA_ROOT_ID,readMediaJson} from '@/lib/media-core';
export const dynamic='force-dynamic';
const reply=(body:unknown,status=200,extra:Record<string,string>={})=>Response.json(body,{status,headers:{...payrollHeaders,...extra}});
export async function GET(req:Request){const user=await payrollUser();if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);try{const q=new URL(req.url).searchParams;return reply(await mediaFeed(mediaGuard(req,user),user,q.get('folder')??MEDIA_ROOT_ID,q.get('pageToken')||undefined));}catch(e){return failure(e);}}
export async function POST(req:Request){const user=await payrollUser();if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de JAC.'},401);if(req.headers.get('origin')!==new URL(req.url).origin)return reply({error:'Origen no autorizado.'},403);try{const body=await readMediaJson(req);if(body.action==='connect'){const connection=await startMediaOauth(req,user);return reply({url:connection.url},200,{'Set-Cookie':connection.cookie});}if(body.action==='createFolder')return reply(await createMediaFolder(mediaGuard(req,user,'upload'),body));return reply({error:'Acción inválida.'},400);}catch(e){return failure(e);}}
function failure(e:unknown){if(e instanceof MediaFailure)return reply({error:e.message},e.status);if(e instanceof SyntaxError)return reply({error:'Revisa los datos enviados.'},400);console.error('Media operation failed');return reply({error:'No pudimos consultar Fotografía. Intenta de nuevo.'},503);}
