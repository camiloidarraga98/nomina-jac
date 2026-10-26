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
export type MediaUploadAcknowledgement={etag?:string};
type UploadProgress=(sent:number,continuous?:boolean)=>void;
function acknowledgement(etag:string|null):MediaUploadAcknowledgement{return etag&&/^"[a-f0-9]{32}"$/i.test(etag)?{etag}:{};}
export async function sendMediaDirectChunk(value:string,mime:string,chunk:Blob,offset:number,total:number,signal:AbortSignal,onProgress?:UploadProgress,fetchOnly=false):Promise<MediaUploadAcknowledgement>{
 const url=directMediaUploadURL(value);
 if(!Number.isSafeInteger(offset)||offset<0||!chunk.size||chunk.size>8*1024*1024||!Number.isSafeInteger(total)||offset+chunk.size>total)throw new Error('El tramo de subida no es válido.');
 const r2=url.hostname.endsWith('.r2.cloudflarestorage.com');if(r2&&(Number(url.searchParams.get('partNumber'))!==Math.floor(offset/(8*1024*1024))+1||offset%(8*1024*1024)||chunk.size!==Math.min(8*1024*1024,total-offset)))throw new Error('La parte no coincide con la autorización de subida.');
 // XHR exposes actual transmitted bytes. It lives in a separate document whose
 // CSP allows only this exact R2 account, blocking off-host redirects before
 // sending bytes. Legacy transports keep fetch's redirect:error behavior.
 // WebKit sends the Blob in the main document: avoid depending on a hidden
 // srcdoc document to start its cross-origin request. Fetch rejects redirects.
 const webkit=typeof navigator!=='undefined'&&/AppleWebKit/i.test(navigator.userAgent)&&!/(?:Chrome|Chromium|Edg|OPR)\//i.test(navigator.userAgent);
 if(r2&&onProgress&&typeof document!=='undefined'&&!webkit&&!fetchOnly){
  try{return await isolatedMediaUpload(url,mime,chunk,signal,onProgress);}catch(error){if(!(error instanceof FrameUnavailable))throw error;}
 }
 let response:Response;
 try{response=await fetch(url,{method:'PUT',credentials:'omit',referrerPolicy:'no-referrer',redirect:'error',cache:'no-store',headers:{'Content-Type':mime,...(!r2?{'Content-Range':`bytes ${offset}-${offset+chunk.size-1}/${total}`}:{})},body:chunk,signal});}
 catch(error){if(signal.aborted)throw error;throw new Error('El navegador no pudo enviar este tramo al almacenamiento. Reintenta para consultar su estado.');}
 const result=acknowledgement(response.headers.get('ETag'));
 await response.body?.cancel();
 if(!response.ok&&(r2||response.status!==308))throw new Error(`El almacenamiento rechazó el tramo enviado (HTTP ${response.status}). Reintenta para consultar su estado.`);
 // Fetch has no upload progress events. Completion must not invent live speed.
 onProgress?.(chunk.size,false);
 return result;
}

// No upload URL is placed in a DOM attribute, disk, log or query string. The
// frame receives one short-lived capability by structured clone after loading.
export function mediaUploadDocument(origin:string,nonce:string){
 if(!/^https:\/\/[a-f0-9]{32}\.r2\.cloudflarestorage\.com$/.test(origin)||!/^[-a-f0-9]{36}$/.test(nonce))throw new Error('Destino de subida inválido.');
 return `<!doctype html><meta name="referrer" content="no-referrer"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-${nonce}'; connect-src ${origin}; base-uri 'none'; form-action 'none'"><script nonce="${nonce}">(${mediaFrameTransport.toString()})()</script>`;
}
function mediaFrameTransport(){
 let used=false;const parentOrigin=parent.location.origin;
 const send=(data:unknown)=>parent.postMessage(data,parentOrigin);
 addEventListener('message',event=>{
  if(used||event.source!==parent||event.origin!==parentOrigin)return;used=true;
  const {url,mime,chunk}=event.data,xhr=new XMLHttpRequest();
  xhr.upload.onprogress=event=>send({type:'progress',loaded:event.loaded});
  xhr.onload=()=>send({type:'done',ok:xhr.status>=200&&xhr.status<300&&xhr.responseURL===url,etag:xhr.getResponseHeader('ETag')});
  xhr.onerror=()=>send({type:'failed'});xhr.ontimeout=()=>send({type:'timeout'});
  xhr.open('PUT',url);xhr.withCredentials=false;xhr.timeout=120000;xhr.setRequestHeader('Content-Type',mime);xhr.send(chunk);
 });
 send({type:'ready'});
}
class FrameUnavailable extends Error{}
function isolatedMediaUpload(url:URL,mime:string,chunk:Blob,signal:AbortSignal,progress:UploadProgress):Promise<MediaUploadAcknowledgement>{
 return new Promise((resolve,reject)=>{
  const frame=document.createElement('iframe');frame.hidden=true;frame.title='Transferencia privada';frame.referrerPolicy='no-referrer';frame.setAttribute('sandbox','allow-scripts allow-same-origin');
  let started=false;
  const cleanup=()=>{clearTimeout(startup);clearTimeout(timer);signal.removeEventListener('abort',abort);window.removeEventListener('message',receive);frame.remove();};
  const fail=(timeout=false)=>{cleanup();reject(new Error(timeout?'El envío tardó demasiado. Reintenta para consultar lo recibido.':'El navegador no pudo confirmar el envío al almacenamiento. Reintenta para consultar su estado.'));};
  const abort=()=>{cleanup();reject(signal.reason instanceof Error&&signal.reason.name==='TimeoutError'?signal.reason:new DOMException('Subida detenida.','AbortError'));};
  const receive=(event:MessageEvent)=>{
   if(event.source!==frame.contentWindow||event.origin!==location.origin)return;const data=event.data;
   if(data?.type==='ready'&&!started){started=true;clearTimeout(startup);frame.contentWindow?.postMessage({url:url.href,mime,chunk},location.origin);return;}
   if(!started)return;
   if(data?.type==='progress'&&Number.isSafeInteger(data.loaded)&&data.loaded>=0&&data.loaded<=chunk.size)progress(data.loaded);
   else if(data?.type==='done'&&data.ok===true){progress(chunk.size);cleanup();resolve(acknowledgement(typeof data.etag==='string'?data.etag:null));}
   else if(data?.type==='done'||data?.type==='failed'||data?.type==='timeout')fail(data.type==='timeout');
  };
  // Fall back only before giving the frame any bytes or capability, so a
  // blocked frame cannot cause two concurrent PUTs for the same part.
  const startup=setTimeout(()=>{cleanup();reject(new FrameUnavailable());},5000),timer=setTimeout(()=>fail(true),125000);
  signal.addEventListener('abort',abort,{once:true});if(signal.aborted){abort();return;}
  window.addEventListener('message',receive);frame.srcdoc=mediaUploadDocument(url.origin,crypto.randomUUID());document.documentElement.appendChild(frame);
 });
}
