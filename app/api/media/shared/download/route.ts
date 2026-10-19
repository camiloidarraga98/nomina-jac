import {MediaFailure} from '@/lib/media-core';
import {sharedFolderDownloadPlan,type SharedDownloadMode} from '@/lib/media-folder-shares';
import {mediaZipStream,mediaZipLength} from '@/lib/media-download-zip';
export const dynamic='force-dynamic';
const headers={'Cache-Control':'private, no-store','Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex, nofollow, noarchive','X-Content-Type-Options':'nosniff'};
export async function POST(req:Request){
 try{
  if(!req.headers.get('content-type')?.startsWith('application/x-www-form-urlencoded'))throw new MediaFailure('Revisa la solicitud de descarga.');
  const reader=req.body?.getReader();if(!reader)throw new MediaFailure('Selecciona una descarga.');
  let size=0;const parts:Uint8Array[]=[];
  try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>1024*1024){await reader.cancel();throw new MediaFailure('La selección es demasiado grande para una sola solicitud.',413);}parts.push(value);}}finally{reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
  const input=new URLSearchParams(new TextDecoder('utf-8',{fatal:true}).decode(bytes));let selected;
  try{selected=JSON.parse(input.get('selection')||'[]');if(!Array.isArray(selected)||selected.some(item=>!item||typeof item.id!=='string'||typeof item.revision!=='string'))throw new Error();}catch{throw new MediaFailure('La selección no es válida.');}
  const plan=await sharedFolderDownloadPlan(input.get('token'),input.get('folder')||'',input.get('mode') as SharedDownloadMode,selected);
  const length=mediaZipLength(plan.files);let body=mediaZipStream(plan.files,req.signal);
  // Workerd only retains Content-Length for a stream with a known length.
  // This also makes a revoked/truncated ZIP fail as an incomplete download.
  const FixedLength=(globalThis as unknown as {FixedLengthStream?:new(length:bigint)=>{readable:ReadableStream<Uint8Array>;writable:WritableStream<Uint8Array>}}).FixedLengthStream;
  if(FixedLength){const fixed=new FixedLength(BigInt(length));void body.pipeTo(fixed.writable).catch(()=>{});body=fixed.readable;}
  return new Response(body,{headers:{...headers,'Content-Type':'application/zip','Content-Length':length,'Content-Disposition':"attachment; filename*=UTF-8''"+encodeURIComponent(plan.name)}});
 }catch(e){
  const message=e instanceof MediaFailure?e.message:'No pudimos preparar esta descarga. Vuelve a la carpeta y reintenta.';
  const safe=message.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
  return new Response('<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Descarga de JAC</title></head><body><main><h1>No se pudo descargar</h1><p>'+safe+'</p><p>Vuelve a la pestaña de la carpeta para reintentar.</p></main></body></html>',{status:e instanceof MediaFailure?e.status:503,headers:{...headers,'Content-Type':'text/html; charset=utf-8','Content-Security-Policy':"default-src 'none'; frame-ancestors 'none'; base-uri 'none'"}});
 }
}
