import {createHash,createHmac} from 'node:crypto';
import {database} from '@/db/raw';
import {mailKey} from './payroll-mail';
import {encryptMail,decryptMail} from './payroll-mail-core';
import {mediaGuardActive,type MediaGuard} from './media-drive';
import {MediaFailure} from './media-core';

export type MediaR2Secret={accountId:string;bucket:string;accessKeyId:string;secretAccessKey:string};
type Connection={credentials:string;version:number;enabled:number};
const digest=(value:string)=>createHash('sha256').update(value).digest('hex');
const hmac=(key:string|Uint8Array,value:string)=>createHmac('sha256',key).update(value).digest();
const encode=(value:string)=>encodeURIComponent(value).replace(/[!'()*]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());
export function mediaR2Input(body:Record<string,unknown>):MediaR2Secret {
 const {accountId,bucket,accessKeyId,secretAccessKey}=body;
 if(typeof accountId!=='string'||!/^[a-f0-9]{32}$/.test(accountId)||typeof bucket!=='string'||!/^jac-fotografia$/.test(bucket)||typeof accessKeyId!=='string'||!/^[a-f0-9]{32}$/i.test(accessKeyId)||typeof secretAccessKey!=='string'||!/^[a-f0-9]{64}$/i.test(secretAccessKey))throw new MediaFailure('Revisa la cuenta y las claves S3 del bucket jac-fotografia.');
 return {accountId,bucket,accessKeyId,secretAccessKey};
}
// Endpoint, bucket and method are chosen by the server, never by the browser.
// No redirects may carry the signed Authorization header to another origin.
export function mediaR2BucketRequest(secret:MediaR2Secret,now=new Date()):Request {
 const valid=mediaR2Input(secret),host=valid.accountId+'.r2.cloudflarestorage.com',url='https://'+host+'/'+encode(valid.bucket);
 const date=now.toISOString().replace(/[:-]|\.\d{3}/g,''),day=date.slice(0,8),scope=day+'/auto/s3/aws4_request';
 const payload=digest(''),canonicalHeaders='host:'+host+'\nx-amz-content-sha256:'+payload+'\nx-amz-date:'+date+'\n',names='host;x-amz-content-sha256;x-amz-date';
 const canonical=['HEAD','/'+encode(valid.bucket),'',canonicalHeaders,names,payload].join('\n');
 const key=hmac(hmac(hmac(hmac('AWS4'+valid.secretAccessKey,day),'auto'),'s3'),'aws4_request');
 const signature=hmac(key,['AWS4-HMAC-SHA256',date,scope,digest(canonical)].join('\n')).toString('hex');
 return new Request(url,{method:'HEAD',redirect:'manual',headers:{'x-amz-date':date,'x-amz-content-sha256':payload,Authorization:'AWS4-HMAC-SHA256 Credential='+valid.accessKeyId+'/'+scope+', SignedHeaders='+names+', Signature='+signature}});
}
async function active(g:MediaGuard){if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión o tus permisos cambiaron.',403);}
async function connection(){return database().prepare("SELECT credentials,version,enabled FROM jac_media_r2_connection WHERE id='jac'").first<Connection>();}
export async function mediaR2Connection(g:MediaGuard){
 await active(g);const c=await connection();
 const secret=c?.credentials?await decryptMail<MediaR2Secret>(c.credentials,mailKey()):undefined;
 await active(g);
 return {configured:!!secret,active:c?.enabled===1,version:c?.version||0,...(secret?{accountId:secret.accountId,bucket:secret.bucket}:{})};
}
export async function activateMediaR2(g:MediaGuard,input:Record<string,unknown>){
 const version=input.version;if(typeof version!=='number'||!Number.isSafeInteger(version)||version<1)throw new MediaFailure('Actualiza la configuración antes de activar.',409);
 await active(g);const before=await connection();if(!before?.credentials||before.version!==version)throw new MediaFailure('La conexión cambió. Actualiza antes de activar.',409);
 if(before.enabled===1)return mediaR2Connection(g);
 // An independent catalogue, never an import or reset of Drive/payroll data.
 const count=await database().prepare('SELECT COUNT(*) AS n FROM jac_media_r2_entries').first<{n:number}>();if(count?.n)throw new MediaFailure('El archivo nuevo ya contiene datos. No se puede reinicializar.',409);
 const now=new Date().toISOString();
 // D1 batch is atomic. Discard only Photography's stored Drive grant locally;
 // never call Google's grant revocation (Calendar/Gmail/Sheets may share it).
 const saved=await database().batch([
  database().prepare(`UPDATE jac_media_r2_connection SET enabled=1,version=version+1,updated_at=? WHERE id='jac' AND version=? AND enabled=0 AND ${g.sql}`).bind(now,version,...g.bindings),
  database().prepare(`UPDATE jac_media_connection SET credentials='',email='',version=version+1,updated_at=? WHERE id='jac' AND EXISTS(SELECT 1 FROM jac_media_r2_connection WHERE id='jac' AND enabled=1 AND version=?) AND ${g.sql}`).bind(now,version+1,...g.bindings),
  database().prepare(`DELETE FROM payroll_oauth WHERE id LIKE 'jac-media:%' AND EXISTS(SELECT 1 FROM jac_media_r2_connection WHERE id='jac' AND enabled=1 AND version=?) AND ${g.sql}`).bind(version+1,...g.bindings)
 ]);
 if(saved[0].meta.changes!==1)throw new MediaFailure('La sesión o la conexión cambió. Actualiza antes de activar.',409);return mediaR2Connection(g);
}
export async function saveMediaR2Connection(g:MediaGuard,input:Record<string,unknown>){
 const secret=mediaR2Input(input),version=input.version;
 if(typeof version!=='number'||!Number.isSafeInteger(version)||version<0)throw new MediaFailure('Actualiza la configuración antes de guardar.',409);
 await active(g);const before=await connection();if((before?.version||0)!==version)throw new MediaFailure('La conexión cambió. Actualiza antes de guardar.',409);
 if(before?.enabled)throw new MediaFailure('La galería ya usa R2. Conserva esta conexión hasta completar la rotación segura.',409);
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);let response:Response;
 try{const request=mediaR2BucketRequest(secret);response=await fetch(request,{signal:controller.signal,redirect:'manual'});}catch{throw new MediaFailure('No pudimos comprobar R2. Conserva las claves y vuelve a intentar.',502);}finally{clearTimeout(timer);}
 await response.body?.cancel().catch(()=>{});await active(g);
 if(!response.ok)throw new MediaFailure([401,403,404].includes(response.status)?'R2 no confirmó acceso a jac-fotografia. Revisa la cuenta, el bucket y el alcance de la credencial.':'R2 no confirmó la conexión. Vuelve a intentar.',response.status>=300&&response.status<400?502:response.status>=500||response.status===429?503:422);
 const credentials=await encryptMail(secret,mailKey());await active(g);
 const saved=await database().prepare(`INSERT INTO jac_media_r2_connection(id,credentials,version,updated_at)
 SELECT 'jac',?,1,? WHERE (?=0 OR EXISTS(SELECT 1 FROM jac_media_r2_connection WHERE id='jac' AND version=?)) AND ${g.sql}
 ON CONFLICT(id) DO UPDATE SET credentials=excluded.credentials,version=jac_media_r2_connection.version+1,updated_at=excluded.updated_at
 WHERE jac_media_r2_connection.version=? AND jac_media_r2_connection.enabled=0 AND ${g.sql}`)
 .bind(credentials,new Date().toISOString(),version,version,...g.bindings,version,...g.bindings).run();
 if(saved.meta.changes!==1)throw new MediaFailure('La sesión o la conexión cambió. Actualiza antes de guardar.',409);
 return mediaR2Connection(g);
}
