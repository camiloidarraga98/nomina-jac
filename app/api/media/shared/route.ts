import {waitUntil} from 'cloudflare:workers';
import {playbackInfo} from '@/lib/media-stream';
import {sharedPlaybackGuard} from '@/lib/media-folder-shares';
import {sharedFolderFeed,sharedFolderFile} from '@/lib/media-folder-shares';
import {MediaFailure,MediaPreviewFailure} from '@/lib/media-core';
export const dynamic='force-dynamic';
const headers={'Cache-Control':'private, no-store','Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex, nofollow, noarchive','X-Content-Type-Options':'nosniff'};
export async function GET(req:Request){try{const q=new URL(req.url).searchParams;let response:Response;
 if(q.get('playback')==='1'){const token=q.get('token')||'',id=q.get('id')||'';response=Response.json(await playbackInfo(await sharedPlaybackGuard(token,id),id,new URL(req.url).origin,{share:token}));}
 else if(q.has('id')){response=await sharedFolderFile(q.get('token'),q.get('id')||'',q.get('thumbnail')==='1',req.headers.get('range'),q.get('revision')||undefined,q.get('preview')==='1'&&q.get('download')!=='1',waitUntil);if(q.get('download')==='1'){const disposition=response.headers.get('content-disposition');if(disposition)response.headers.set('content-disposition',disposition.replace(/^inline/,'attachment'));}}
 else response=Response.json(await sharedFolderFeed(q.get('token'),q.get('folder')||undefined,q.get('pageToken')||undefined));
 for(const [key,value]of Object.entries(headers))response.headers.set(key,value);return response;
 }catch(e){return Response.json({error:e instanceof MediaFailure?e.message:'No pudimos abrir esta carpeta.',...(e instanceof MediaPreviewFailure?{code:e.reason}:{})},{status:e instanceof MediaFailure?e.status:503,headers:{...headers,...(e instanceof MediaPreviewFailure?{'Retry-After':String(e.retryAfter)}:{})}});}}
