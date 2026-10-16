import {mediaImageLimit,type MediaImageLimit} from "./media-image-policy";
const STORAGE_KEY="jac.media.image-quality.v1";
export function savedMediaImageLimit():MediaImageLimit {try{return mediaImageLimit(localStorage.getItem(STORAGE_KEY)??2_000_000);}catch{return 2_000_000;}}
export function saveMediaImageLimit(limit:MediaImageLimit){try{localStorage.setItem(STORAGE_KEY,String(limit));}catch{throw new Error("El navegador no permite guardar esta preferencia.");}}

// Runs once before reserving the upload ID/payload on the server. A retry keeps
// this exact prepared File; it must not reserve a second, differently sized copy.
export async function prepareMediaImage(file:File,mime:string,limit:MediaImageLimit=2_000_000):Promise<File>{
 if(!mime.startsWith('image/')||!limit||file.size<=limit)return file;
 const header=new Uint8Array(await file.slice(0,65536).arrayBuffer()),text=new TextDecoder('latin1').decode(header);
 if(mime==='image/gif'||mime==='image/webp'&&text.includes('ANIM')||mime==='image/png'&&text.includes('acTL'))throw new Error('Para conservar esta imagen animada, elige Sin compresión.');
 const bitmap=await createImageBitmap(file,{imageOrientation:'from-image'}).catch(()=>{throw new Error('No pudimos optimizar esta imagen. Tu navegador debe poder abrir su formato. También puedes elegir Sin compresión.');});
 try{
  let edge=Math.min(8192,Math.max(bitmap.width,bitmap.height));
  for(let pass=0;pass<6;pass++,edge=Math.floor(edge*0.75)){
   const scale=Math.min(1,edge/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
   const context=canvas.getContext('2d');if(!context)throw new Error('No pudimos preparar la foto en este navegador.');context.fillStyle="#fff";context.fillRect(0,0,canvas.width,canvas.height);context.drawImage(bitmap,0,0,canvas.width,canvas.height);
   const encode=(quality:number)=>new Promise<Blob>((resolve,reject)=>canvas.toBlob(blob=>blob?.size?resolve(blob):reject(new Error('No pudimos optimizar la imagen.')),'image/jpeg',quality));
   const best=await encode(0.92);if(best.size<=limit)return new File([best],mime==='image/jpeg'?file.name:file.name.replace(/\.[^.]+$/,'')+'.jpg',{type:'image/jpeg',lastModified:file.lastModified});
   let low=0.48,high=0.92,accepted:Blob|null=null;
   for(let attempt=0;attempt<6;attempt++){const quality=attempt===0?low:(low+high)/2,blob=await encode(quality);if(blob.size<=limit){accepted=blob;low=quality;}else {high=quality;if(attempt===0)break;}}
   if(accepted)return new File([accepted],mime==='image/jpeg'?file.name:file.name.replace(/\.[^.]+$/,'')+'.jpg',{type:'image/jpeg',lastModified:file.lastModified});
  }
  throw new Error('No pudimos reducir esta imagen al tamaño elegido. Usa otro nivel o Sin compresión.');
 }finally{bitmap.close();}
}
