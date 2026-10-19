// Bounded presentation variant. Original bytes are never recompressed/replaced.
// Browser codec support varies; native uploads also supply a compatible JPEG.
export async function mediaBrowserThumbnail(file:File,mime:string):Promise<Blob|null>{
 const url=URL.createObjectURL(file);let media:HTMLImageElement|HTMLVideoElement|null=null,timer:ReturnType<typeof setTimeout>|undefined;
 try{
  const video=mime.startsWith('video/');media=video?document.createElement('video'):document.createElement('img');
  await new Promise<void>((resolve,reject)=>{
   timer=setTimeout(()=>reject(new Error('Vista previa pendiente.')),10000);
   if(media instanceof HTMLVideoElement){media.preload='auto';media.muted=true;media.playsInline=true;media.onloadeddata=()=>resolve();}
   else (media as HTMLImageElement).onload=()=>resolve();
   media!.onerror=()=>reject(new Error('El navegador no decodifica este archivo.'));media!.src=url;
  });
  const width=media instanceof HTMLVideoElement?media.videoWidth:media.naturalWidth,height=media instanceof HTMLVideoElement?media.videoHeight:media.naturalHeight;
  if(!width||!height)return null;const scale=Math.min(1,360/Math.max(width,height)),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(width*scale));canvas.height=Math.max(1,Math.round(height*scale));const context=canvas.getContext('2d');if(!context)return null;context.drawImage(media,0,0,canvas.width,canvas.height);
  const blob=await new Promise<Blob|null>(resolve=>canvas.toBlob(resolve,'image/jpeg',0.60));return blob&&blob.size<=512*1024?blob:null;
 }catch{return null;}finally{if(timer)clearTimeout(timer);if(media){media.onload=null;media.onerror=null;if(media instanceof HTMLVideoElement){media.onloadeddata=null;media.pause();media.removeAttribute('src');media.load();}else media.removeAttribute('src');}URL.revokeObjectURL(url);}
}
