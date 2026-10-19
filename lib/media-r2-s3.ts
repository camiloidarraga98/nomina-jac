import {createHash,createHmac} from 'node:crypto';
import {MediaFailure} from './media-core';
import {mediaR2Input,type MediaR2Secret} from './media-r2';

const sha=(v:string|Uint8Array)=>createHash('sha256').update(v).digest('hex');
const mac=(k:string|Uint8Array,v:string)=>createHmac('sha256',k).update(v).digest();
const enc=(v:string)=>encodeURIComponent(v).replace(/[!'()*]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());
const queryString=(q:Record<string,string>)=>Object.entries(q).map(([k,v])=>[enc(k),enc(v)]).sort((a,b)=>a[0]<b[0]?-1:a[0]>b[0]?1:0).map(p=>p.join('=')).join('&');
function base(secret:MediaR2Secret,key:string,now:Date){
 const valid=mediaR2Input(secret);
 if(key&&!/^(originals|thumbnails|previews)\/[a-f0-9-]{36}(?:\.jpg)?$/.test(key))throw new MediaFailure('El objeto de Fotografía no es válido.');
 const host=valid.accountId+'.r2.cloudflarestorage.com',path='/'+enc(valid.bucket)+(key?'/'+key.split('/').map(enc).join('/'):'');
 const date=now.toISOString().replace(/[:-]|\.\d{3}/g,''),day=date.slice(0,8),scope=day+'/auto/s3/aws4_request';
 const signing=mac(mac(mac(mac('AWS4'+valid.secretAccessKey,day),'auto'),'s3'),'aws4_request');
 return {host,path,date,scope,signing};
}
// The endpoint and object namespace are server-owned. Signed requests never
// follow a redirect, and caller cookies/OAuth headers cannot enter this API.
export function r2Request(secret:MediaR2Secret,method:'GET'|'HEAD'|'POST'|'PUT'|'DELETE',key='',query:Record<string,string>={},headers:Record<string,string>={},body?:string|Uint8Array,now=new Date()){
 const b=base(secret,key,now),payload=sha(body??''),h=new Headers(headers);
 h.set('host',b.host);h.set('x-amz-date',b.date);h.set('x-amz-content-sha256',payload);
 const entries=[...h].sort(([a],[b])=>a<b?-1:a>b?1:0),names=entries.map(([k])=>k).join(';'),canonicalHeaders=entries.map(([k,v])=>k+':'+v.trim().replace(/\s+/g,' ')+'\n').join(''),q=queryString(query);
 const canonical=[method,b.path,q,canonicalHeaders,names,payload].join('\n');
 const signature=mac(b.signing,['AWS4-HMAC-SHA256',b.date,b.scope,sha(canonical)].join('\n')).toString('hex');
 h.set('authorization','AWS4-HMAC-SHA256 Credential='+secret.accessKeyId+'/'+b.scope+', SignedHeaders='+names+', Signature='+signature);
 return new Request('https://'+b.host+b.path+(q?'?'+q:''),{method,headers:h,redirect:'manual',...(body!==undefined?{body:body as BodyInit}:{})});
}
export function r2PartURL(secret:MediaR2Secret,key:string,uploadId:string,part:number,length:number,mime:string,now=new Date()){
 const b=base(secret,key,now),names='content-length;content-type;host';
 const query={uploadId,partNumber:String(part),'X-Amz-Algorithm':'AWS4-HMAC-SHA256','X-Amz-Credential':secret.accessKeyId+'/'+b.scope,'X-Amz-Date':b.date,'X-Amz-Expires':'300','X-Amz-SignedHeaders':names};
 const q=queryString(query),canonical=['PUT',b.path,q,'content-length:'+length+'\ncontent-type:'+mime+'\nhost:'+b.host+'\n',names,'UNSIGNED-PAYLOAD'].join('\n');
 const signature=mac(b.signing,['AWS4-HMAC-SHA256',b.date,b.scope,sha(canonical)].join('\n')).toString('hex');
 return 'https://'+b.host+b.path+'?'+q+'&X-Amz-Signature='+signature;
}
// This short-lived read capability is sent only to Cloudflare Stream ingestion.
// It never appears in a gallery response, manifest or application log.
export function r2SourceURL(secret:MediaR2Secret,key:string,now=new Date()){
 const b=base(secret,key,now),query={'X-Amz-Algorithm':'AWS4-HMAC-SHA256','X-Amz-Credential':secret.accessKeyId+'/'+b.scope,'X-Amz-Date':b.date,'X-Amz-Expires':'3600','X-Amz-SignedHeaders':'host'};
 const q=queryString(query),canonical=['GET',b.path,q,'host:'+b.host+'\n','host','UNSIGNED-PAYLOAD'].join('\n');
 const signature=mac(b.signing,['AWS4-HMAC-SHA256',b.date,b.scope,sha(canonical)].join('\n')).toString('hex');
 return 'https://'+b.host+b.path+'?'+q+'&X-Amz-Signature='+signature;
}
export async function r2Bytes(response:Response,limit:number){
 if(Number(response.headers.get('content-length')||0)>limit){await response.body?.cancel();throw new MediaFailure('La respuesta de almacenamiento excede el límite.',502);}
 const reader=response.body?.getReader();if(!reader)return new Uint8Array();const chunks:Uint8Array[]=[];let size=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>limit){await reader.cancel();throw new MediaFailure('La respuesta de almacenamiento excede el límite.',502);}chunks.push(value);}}finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return bytes;
}
export async function r2XML(response:Response){const text=new TextDecoder('utf-8',{fatal:true}).decode(await r2Bytes(response,1024*1024));if(/<!DOCTYPE|<!ENTITY/i.test(text))throw new MediaFailure('Respuesta de almacenamiento inválida.',502);return text;}
export function xmlValue(xml:string,tag:string){const values=[...xml.matchAll(new RegExp('<'+tag+'>([\\s\\S]*?)</'+tag+'>','g'))];if(values.length!==1)return '';const value=values[0][1];if(/</.test(value))return '';return value.replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');}
export const xmlEscape=(value:string)=>value.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
