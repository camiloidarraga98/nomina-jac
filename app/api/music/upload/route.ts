import {payrollUser} from '@/lib/payroll-access';
import {musicGuard,startMusic,appendMusic,completeMusic,cancelMusic} from '@/lib/music-store';
import {MUSIC_CHUNK,MusicFailure} from '@/lib/music-core';
import {musicReply,musicError,musicJson,musicOrigin,musicBytes} from '@/lib/music-http';
export const dynamic='force-dynamic';
export async function POST(req:Request){try{musicOrigin(req);const u=await payrollUser();if(!u||u.legacy)throw new MusicFailure('Inicia sesión con tu cuenta de JAC.',401);const g=musicGuard(req,u,'upload'),b=await musicJson(req);if(b.action==='start')return musicReply(await startMusic(g,b));if(b.action==='complete')return musicReply(await completeMusic(g,b.id));if(b.action==='cancel')return musicReply(await cancelMusic(g,b.id));throw new MusicFailure('Acción inválida.');}catch(e){return musicError(e);}}
export async function PUT(req:Request){try{musicOrigin(req);const u=await payrollUser();if(!u||u.legacy)throw new MusicFailure('Inicia sesión con tu cuenta de JAC.',401);const g=musicGuard(req,u,'upload'),q=new URL(req.url).searchParams;if(!/^\d+$/.test(q.get('offset')||''))throw new MusicFailure('Bloque inválido.');return musicReply(await appendMusic(g,q.get('id'),Number(q.get('offset')),await musicBytes(req,MUSIC_CHUNK)));}catch(e){return musicError(e);}}
