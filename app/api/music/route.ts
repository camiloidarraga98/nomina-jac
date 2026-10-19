import {payrollUser} from '@/lib/payroll-access';
import {musicGuard,musicLibrary,musicLease,deleteMusic} from '@/lib/music-store';
import {MusicFailure} from '@/lib/music-core';
import {musicReply,musicError,musicJson,musicOrigin} from '@/lib/music-http';
export const dynamic='force-dynamic';
export async function GET(req:Request){try{const u=await payrollUser();if(!u||u.legacy)throw new MusicFailure('Inicia sesión con tu cuenta de JAC.',401);const g=musicGuard(req,u),q=new URL(req.url).searchParams;return musicReply(q.get('play')==='1'?await musicLease(g,q.get('id'),q.get('revision')):await musicLibrary(g,u));}catch(e){return musicError(e);}}
export async function POST(req:Request){try{musicOrigin(req);const u=await payrollUser();if(!u||u.legacy)throw new MusicFailure('Inicia sesión con tu cuenta de JAC.',401);const b=await musicJson(req);if(b.action!=='delete')throw new MusicFailure('Acción inválida.');return musicReply(await deleteMusic(musicGuard(req,u,'delete'),b.id,b.revision));}catch(e){return musicError(e);}}
