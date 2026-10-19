import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {mediaGuard} from '@/lib/media-drive';
import {listFolderShares,createFolderShare,revokeFolderShare} from '@/lib/media-folder-shares';
import {MediaFailure,readMediaJson} from '@/lib/media-core';
export const dynamic='force-dynamic';
const headers={...payrollHeaders,'Referrer-Policy':'no-referrer'};
const failure=(e:unknown)=>Response.json({error:e instanceof MediaFailure?e.message:'No pudimos preparar el enlace.'},{status:e instanceof MediaFailure?e.status:503,headers});
export async function GET(req:Request){try{const user=await payrollUser();if(!user||user.legacy)throw new MediaFailure('Inicia sesión en JAC.',401);return Response.json(await listFolderShares(mediaGuard(req,user,'upload'),new URL(req.url).searchParams.get('folder')),{headers});}catch(e){return failure(e);}}
export async function POST(req:Request){try{const user=await payrollUser();if(!user||user.legacy)throw new MediaFailure('Inicia sesión en JAC.',401);if(req.headers.get('origin')!==new URL(req.url).origin)throw new MediaFailure('Origen no autorizado.',403);const body=await readMediaJson(req),g=mediaGuard(req,user,'upload');if(body.action==='create')return Response.json(await createFolderShare(g,body),{headers});if(body.action==='revoke')return Response.json(await revokeFolderShare(g,body),{headers});throw new MediaFailure('Acción inválida.');}catch(e){return failure(e);}}
