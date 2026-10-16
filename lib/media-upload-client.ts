// Only the upload-session capability crosses to the client. It permits bytes
// for one reserved file, never Drive listing, reading or owner OAuth access.
export function directMediaUploadURL(value:string){
 let url:URL;try{url=new URL(value);}catch{throw new Error('La autorización de subida no es válida.');}
 if(url.origin!=='https://www.googleapis.com'||url.username||url.password||url.hash||!/^\/upload\/drive\/v3\/files(?:\/[A-Za-z0-9_-]+)?$/.test(url.pathname)||url.searchParams.getAll('upload_id').length!==1||!url.searchParams.get('upload_id'))throw new Error('La autorización de subida no es válida.');
 return url;
}
export async function sendMediaDirectChunk(value:string,mime:string,chunk:Blob,offset:number,total:number,signal:AbortSignal){
 const url=directMediaUploadURL(value);
 if(!Number.isSafeInteger(offset)||offset<0||!chunk.size||chunk.size>8*1024*1024||!Number.isSafeInteger(total)||offset+chunk.size>total)throw new Error('El tramo de subida no es válido.');
 const response=await fetch(url,{method:'PUT',credentials:'omit',referrerPolicy:'no-referrer',redirect:'error',cache:'no-store',headers:{'Content-Type':mime,'Content-Range':`bytes ${offset}-${offset+chunk.size-1}/${total}`},body:chunk,signal});
 await response.body?.cancel();
 if(!response.ok&&response.status!==308)throw new Error('Drive no confirmó el tramo enviado. Reintenta para consultar el progreso.');
}
