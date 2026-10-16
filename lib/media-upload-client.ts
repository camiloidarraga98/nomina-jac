// Only the upload-session capability crosses to the client. It permits bytes
// for one reserved file, never Drive listing, reading or owner OAuth access.
export function directMediaUploadURL(value:string){
 let url:URL;try{url=new URL(value);}catch{throw new Error('La autorización de subida no es válida.');}
 if(url.username||url.password||url.hash||url.port||url.protocol!=='https:')throw new Error('La autorización de subida no es válida.');
 if(/^[a-f0-9]{32}\.r2\.cloudflarestorage\.com$/.test(url.hostname)){
  const q=url.searchParams,allowed=['uploadId','partNumber','X-Amz-Algorithm','X-Amz-Credential','X-Amz-Date','X-Amz-Expires','X-Amz-SignedHeaders','X-Amz-Signature'];
  if(!/^\/jac-fotografia\/originals\/[a-f0-9-]{36}$/.test(url.pathname)||[...q.keys()].some(k=>!allowed.includes(k))||allowed.some(k=>q.getAll(k).length!==1)||!q.get('uploadId')||!/^\d{1,4}$/.test(q.get('partNumber')||'')||q.get('X-Amz-Algorithm')!=='AWS4-HMAC-SHA256'||!/^\w{32}\/\d{8}\/auto\/s3\/aws4_request$/.test(q.get('X-Amz-Credential')||'')||!/^\d{8}T\d{6}Z$/.test(q.get('X-Amz-Date')||'')||q.get('X-Amz-Expires')!=='300'||q.get('X-Amz-SignedHeaders')!=='content-length;content-type;host'||!/^[a-f0-9]{64}$/.test(q.get('X-Amz-Signature')||''))throw new Error('La autorización de subida no es válida.');
 }else if(url.origin!=='https://www.googleapis.com'||!/^\/upload\/drive\/v3\/files(?:\/[A-Za-z0-9_-]+)?$/.test(url.pathname)||url.searchParams.getAll('upload_id').length!==1||!url.searchParams.get('upload_id'))throw new Error('La autorización de subida no es válida.');
 return url;
}
export async function sendMediaDirectChunk(value:string,mime:string,chunk:Blob,offset:number,total:number,signal:AbortSignal){
 const url=directMediaUploadURL(value);
 if(!Number.isSafeInteger(offset)||offset<0||!chunk.size||chunk.size>8*1024*1024||!Number.isSafeInteger(total)||offset+chunk.size>total)throw new Error('El tramo de subida no es válido.');
 const r2=url.hostname.endsWith('.r2.cloudflarestorage.com');if(r2&&(Number(url.searchParams.get('partNumber'))!==Math.floor(offset/(8*1024*1024))+1||offset%(8*1024*1024)||chunk.size!==Math.min(8*1024*1024,total-offset)))throw new Error('La parte no coincide con la autorización de subida.');
 const response=await fetch(url,{method:'PUT',credentials:'omit',referrerPolicy:'no-referrer',redirect:'error',cache:'no-store',headers:{'Content-Type':mime,...(!r2?{'Content-Range':`bytes ${offset}-${offset+chunk.size-1}/${total}`}:{})},body:chunk,signal});
 await response.body?.cancel();
 if(!response.ok&&(r2||response.status!==308))throw new Error('El almacenamiento no confirmó el tramo enviado. Reintenta para consultar el progreso.');
}
