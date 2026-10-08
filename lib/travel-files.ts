import {env} from 'cloudflare:workers';
import {database} from '@/db/raw';
import {decodeNoticeFiles} from './notice-files';
export async function contentHash(value:unknown){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(value)))),b=>b.toString(16).padStart(2,'0')).join('');}
export async function stageTravelFiles(files:ReturnType<typeof decodeNoticeFiles>){
 const uploads=files.map(f=>({...f,id:crypto.randomUUID(),key:'notice-attachments/'+crypto.randomUUID()}));
 try{for(const f of uploads){await database().prepare('INSERT INTO jac_notice_attachments(id,file_key,filename,mime_type,size,expires_at) VALUES (?,?,?,?,?,?)').bind(f.id,f.key,f.filename,f.mimeType,f.size,new Date(Date.now()+3600000).toISOString()).run();await env.BUCKET.put(f.key,f.bytes,{httpMetadata:{contentType:f.mimeType}});}return uploads;}catch(e){await discardTravelFiles(uploads);throw e;}
}
export async function discardTravelFiles(files:{id:string}[]){for(const f of files)await database().prepare("UPDATE jac_notice_attachments SET state='deleted',cleaned=0,cleanup_version=cleanup_version+1 WHERE id=? AND state<>'ready'").bind(f.id).run();}
export const uploadedGate=(files:{id:string}[])=>files.length?` AND (SELECT count(*) FROM jac_notice_attachments WHERE state='staged' AND expires_at>? AND id IN (${files.map(()=>'?').join(',')}))=${files.length}`:'';
export const uploadedBindings=(files:{id:string}[])=>files.length?[new Date().toISOString(),...files.map(f=>f.id)]:[];
