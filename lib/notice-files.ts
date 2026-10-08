import {z} from 'zod';
import {NoticeFailure,MAX_PDF_BYTES} from './notifications-core';
export const manualNoticeSchema=z.object({id:z.string().uuid(),kind:z.enum(['alert','itinerary','boarding_pass']),travelDate:z.string().optional(),title:z.string().trim().min(1).max(120),body:z.string().trim().max(2000),recipients:z.array(z.string().uuid()).max(100),files:z.array(z.object({filename:z.string().min(1).max(160),data:z.string().max(14*1024*1024)}).strict()).max(5)}).strict();
export function fileMime(bytes:Uint8Array){
 if(new TextDecoder().decode(bytes.slice(0,5))==='%PDF-')return 'application/pdf';
 if(bytes.length>8&&[137,80,78,71,13,10,26,10].every((n,i)=>bytes[i]===n))return 'image/png';
 if(bytes.length>3&&bytes[0]===255&&bytes[1]===216&&bytes[2]===255)return 'image/jpeg';
 throw new NoticeFailure('Solo se admiten archivos PDF, JPG o PNG válidos.');
}
export function decodeNoticeFiles(files:{filename:string;data:string}[]){
 let total=0;return files.map(file=>{
  if((file.data.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(file.data)))throw new NoticeFailure('No se pudo leer un adjunto. Selecciónalo de nuevo.');
  const raw=atob(file.data);total+=raw.length;if(!raw.length||total>MAX_PDF_BYTES)throw new NoticeFailure('Los adjuntos deben sumar como máximo 10 MB.');
  const bytes=Uint8Array.from(raw,c=>c.charCodeAt(0)),mimeType=fileMime(bytes),extension=mimeType==='application/pdf'?'.pdf':mimeType==='image/png'?'.png':'.jpg';
  const base=Array.from(file.filename.replace(/[\x00-\x1f\x7f/\\]/g,'_').replace(/\.[^.]*$/,'')).slice(0,70).map(c=>c.length===1&&/[\uD800-\uDFFF]/.test(c)?'_':c).join('')||'Adjunto';
  return {filename:base+extension,mimeType,bytes,size:bytes.length};
 });
}
export async function boundedNoticeJSON(req:Request){
 const limit=14*1024*1024;if(Number(req.headers.get('content-length')??0)>limit)throw new NoticeFailure('Solicitud demasiado grande.',413);
 if(!req.body)throw new NoticeFailure('Solicitud no válida.');const reader=req.body.getReader(),parts:Uint8Array[]=[];let size=0;
 for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>limit){await reader.cancel();throw new NoticeFailure('Solicitud demasiado grande.',413);}parts.push(next.value);}
 const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
 try{return JSON.parse(new TextDecoder().decode(bytes)) as unknown;}catch{throw new NoticeFailure('Solicitud no válida.');}
}
