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
export async function sendMediaDirectChunk(value:string,mime:string,chunk:Blob,offset:number,total:number,signal:AbortSignal,onProgress?:(sent:number)=>void){
 const url=directMediaUploadURL(value);
 if(!Number.isSafeInteger(offset)||offset<0||!chunk.size||chunk.size>8*1024*1024||!Number.isSafeInteger(total)||offset+chunk.size>total)throw new Error('El tramo de subida no es válido.');
 const r2=url.hostname.endsWith('.r2.cloudflarestorage.com');if(r2&&(Number(url.searchParams.get('partNumber'))!==Math.floor(offset/(8*1024*1024))+1||offset%(8*1024*1024)||chunk.size!==Math.min(8*1024*1024,total-offset)))throw new Error('La parte no coincide con la autorización de subida.');
 // XHR exposes actual transmitted bytes. It lives in a separate document whose
 // CSP allows only this exact R2 account, blocking off-host redirects before
 // sending bytes. Legacy transports keep fetch's redirect:error behavior.
 if(r2&&onProgress&&typeof document!=='undefined')return isolatedMediaUpload(url,mime,chunk,signal,onProgress);
 const response=await fetch(url,{method:'PUT',credentials:'omit',referrerPolicy:'no-referrer',redirect:'error',cache:'no-store',headers:{'Content-Type':mime,...(!r2?{'Content-Range':`bytes ${offset}-${offset+chunk.size-1}/${total}`}:{})},body:chunk,signal});
 await response.body?.cancel();
 if(!response.ok&&(r2||response.status!==308))throw new Error('El almacenamiento no confirmó el tramo enviado. Reintenta para consultar el progreso.');
 onProgress?.(chunk.size);
}

// No upload URL is placed in a DOM attribute, disk, log or query string. The
// frame receives one short-lived capability by structured clone after loading.
export function mediaUploadDocument(origin:string,nonce:string){
 if(!/^https:\/\/[a-f0-9]{32}\.r2\.cloudflarestorage\.com$/.test(origin)||!/^[-a-f0-9]{36}$/.test(nonce))throw new Error('Destino de subida inválido.');
 return `<!doctype html><meta name="referrer" content="no-referrer"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-${nonce}'; connect-src ${origin}; base-uri 'none'; form-action 'none'"><script nonce="${nonce}">(${mediaFrameTransport.toString()})()</script>`;
}
function mediaFrameTransport(){
 let used=false;const parentOrigin=parent.location.origin;
 addEventListener('message',event=>{
  if(used||event.source!==parent||event.origin!==parentOrigin)return;used=true;
  const {url,mime,chunk}=event.data,xhr=new XMLHttpRequest();
  const send=(data:unknown)=>parent.postMessage(data,parentOrigin);
  xhr.upload.onprogress=event=>send({type:'progress',loaded:event.loaded});
  xhr.onload=()=>send({type:'done',ok:xhr.status>=200&&xhr.status<300&&xhr.responseURL===url});
  xhr.onerror=xhr.ontimeout=()=>send({type:'failed'});
  xhr.open('PUT',url);xhr.withCredentials=false;xhr.timeout=120000;xhr.setRequestHeader('Content-Type',mime);xhr.send(chunk);
 });
}
function isolatedMediaUpload(url:URL,mime:string,chunk:Blob,signal:AbortSignal,progress:(sent:number)=>void):Promise<void>{
 return new Promise((resolve,reject)=>{
  const frame=document.createElement('iframe');frame.hidden=true;frame.title='Transferencia privada';frame.referrerPolicy='no-referrer';frame.setAttribute('sandbox','allow-scripts allow-same-origin');
  const cleanup=()=>{clearTimeout(timer);signal.removeEventListener('abort',abort);window.removeEventListener('message',receive);frame.remove();};
  const fail=()=>{cleanup();reject(new Error('El almacenamiento no confirmó el tramo enviado. Reintenta para consultar el progreso.'));};
  const abort=()=>{cleanup();reject(new DOMException('Subida detenida.','AbortError'));};
  const receive=(event:MessageEvent)=>{if(event.source!==frame.contentWindow||event.origin!==location.origin)return;const data=event.data;if(data?.type==='progress'&&Number.isSafeInteger(data.loaded)&&data.loaded>=0&&data.loaded<=chunk.size)progress(data.loaded);else if(data?.type==='done'&&data.ok===true){progress(chunk.size);cleanup();resolve();}else if(data?.type==='done'||data?.type==='failed')fail();};
  const timer=setTimeout(fail,125000);signal.addEventListener('abort',abort,{once:true});if(signal.aborted){abort();return;}
  window.addEventListener('message',receive);frame.onload=()=>frame.contentWindow?.postMessage({url:url.href,mime,chunk},location.origin);frame.srcdoc=mediaUploadDocument(url.origin,crypto.randomUUID());document.documentElement.appendChild(frame);
 });
}
