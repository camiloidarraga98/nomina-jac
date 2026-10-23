import {z} from 'zod';
import {database} from '@/db/raw';
import {type AccessUser,hasSection,sectionSql} from './payroll-permissions';
import {encryptMail} from './payroll-mail-core';
import {mailKey} from './payroll-mail';
import {allowedNotice,noticeAttachment,noticeConfig,noticeOwner,pushCredentials} from './notifications';
import {MAX_PDF_BYTES,NoticeFailure,type PushCredentials} from './notifications-core';
import {boardingFilenameDetails,validBoardingDate} from './boarding-passes';
import {fileMime} from './notice-files';
import {parseWalletBarcodeDetails} from './boarding-wallet-details';
import {normalizeWalletCredentials,validateWalletBarcode,buildBoardingWalletPass,type WalletCredentials} from './boarding-wallet-core';

export const MAX_WALLET_BYTES=1024*1024;
export type WalletGuard={sessionId:string;current:()=>Promise<AccessUser|null>};
export type WalletSettings={configured:boolean;version:number;passTypeId?:string;expiresAt?:string};
type StoredCredentials=PushCredentials&{wallet?:WalletCredentials};
type WalletRole='view'|'configure'|'create';
const uuid=z.string().uuid();
const configureSchema=z.object({action:z.literal('configure'),version:z.number().int().nonnegative(),teamId:z.string().regex(/^[A-Z0-9]{10}$/),passTypeId:z.string().min(6).max(200),p12:z.string().min(1).max(180000),password:z.string().max(200),wwdr:z.string().min(1).max(24000)}).strict();
const readable=(max:number)=>z.string().max(max).refine(value=>!/[\p{C}]/u.test(value)).transform(value=>value.trim());
const time=readable(5).refine(value=>value===''||/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value));
const seat=readable(6).refine(value=>value===''||/^(?=.*[1-9A-Z])[A-Z0-9]{1,6}$/.test(value));
const detailsSchema=z.object({passenger:readable(120).optional(),origin:readable(100).optional(),destination:readable(100).optional(),departureTime:time.optional(),boardingTime:time.optional(),seat:seat.optional()}).strict();
const createSchema=z.object({action:z.literal('create'),id:uuid,file:uuid,revision:z.number().int().positive(),sourceSha256:z.string().regex(/^[a-f0-9]{64}$/),barcode:z.object({format:z.string().max(40),message:z.string().max(4096)}).strict(),details:detailsSchema.optional(),legIndex:z.number().int().min(0).max(3).optional()}).strict();

function permitted(user:AccessUser,role:WalletRole){
 return !user.legacy&&(role==='configure'?noticeOwner(user):role==='create'?hasSection(user,'boarding'):hasSection(user,'boarding')||noticeOwner(user));
}
function sessionSql(role:WalletRole){
 const section=role==='configure'?sectionSql('wallet_user','crm'):role==='create'?sectionSql('wallet_user','boarding'):`(${sectionSql('wallet_user','boarding')} OR ${sectionSql('wallet_user','crm')})`;
 return `EXISTS(SELECT 1 FROM payroll_sessions wallet_session JOIN payroll_users wallet_user ON wallet_user.id=wallet_session.user_id AND wallet_user.version=wallet_session.user_version WHERE wallet_session.id=? AND wallet_user.id=? AND (wallet_session.persistent=1 OR wallet_session.expires_at>strftime('%Y-%m-%dT%H:%M:%fZ','now')) AND wallet_user.active=1 AND wallet_user.password_hash<>'' AND ${section})`;
}
async function authorize(user:AccessUser,guard:WalletGuard,role:WalletRole){
 const current=await guard.current();
 if(!current||JSON.stringify(current)!==JSON.stringify(user)||!permitted(current,role)||!guard.sessionId)throw new NoticeFailure('Tu sesión o permiso cambió. Inicia sesión de nuevo.',403);
 const live=await database().prepare('SELECT 1 AS active WHERE '+sessionSql(role)).bind(guard.sessionId,user.id).first();
 if(!live)throw new NoticeFailure('Tu sesión o permiso cambió. Inicia sesión de nuevo.',403);
}
function usableWallet(value:unknown):value is WalletCredentials{
 if(!value||typeof value!=='object'||Array.isArray(value))return false;
 const c=value as Record<string,unknown>;
 return ['teamId','passTypeId','certificate','privateKey','wwdr','expiresAt'].every(key=>typeof c[key]==='string'&&Boolean(c[key]))&&Number.isFinite(Date.parse(String(c.expiresAt)))&&Date.parse(String(c.expiresAt))>Date.now();
}
function metadata(version:number,wallet:unknown):WalletSettings{
 if(!usableWallet(wallet))return {configured:false,version};
 return {configured:true,version,passTypeId:wallet.passTypeId,expiresAt:wallet.expiresAt};
}
export async function boardingWalletSettings(user:AccessUser,guard:WalletGuard):Promise<WalletSettings>{
 await authorize(user,guard,'view');
 const config=await noticeConfig(),keys=await pushCredentials(config) as StoredCredentials;
 await authorize(user,guard,'view');
 return metadata(config.version,keys.wallet);
}
export async function configureBoardingWallet(user:AccessUser,input:unknown,guard:WalletGuard):Promise<WalletSettings>{
 await authorize(user,guard,'configure');
 const parsed=configureSchema.safeParse(input);if(!parsed.success)throw new NoticeFailure('Revisa el Team ID, identificador y los archivos de Wallet.');
 const p=parsed.data,config=await noticeConfig();
 if(config.version!==p.version)throw new NoticeFailure('La configuración cambió. Actualiza antes de guardar.',409);
 const keys=await pushCredentials(config) as StoredCredentials;
 const wallet=await normalizeWalletCredentials({teamId:p.teamId,passTypeId:p.passTypeId,p12:p.p12,password:p.password,wwdr:p.wwdr});
 await authorize(user,guard,'configure');
 // Store only the normalized signer, encrypted together with the previous
 // APNs/Slack/Web credentials. Never persist the uploaded PKCS#12/password.
 const encrypted=await encryptMail({...keys,wallet},mailKey());
 await authorize(user,guard,'configure');
 const db=database(),bindings=[guard.sessionId,user.id];
 await db.prepare('INSERT OR IGNORE INTO jac_notice_settings (id) SELECT ? WHERE '+sessionSql('configure')).bind('jac',...bindings).run();
 const result=await db.prepare('UPDATE jac_notice_settings SET credentials=?,version=version+1 WHERE id=? AND version=? AND '+sessionSql('configure')).bind(encrypted,'jac',config.version,...bindings).run();
 if(result.meta.changes!==1){await authorize(user,guard,'configure');throw new NoticeFailure('La configuración cambió. Actualiza antes de guardar.',409);}
 await authorize(user,guard,'configure');
 return metadata(config.version+1,wallet);
}

type Source={key:string;filename:string;mimeType:string;size:number;revision:number;travelDate:string;legacy:boolean};
async function sourceMetadata(user:AccessUser,id:string,file:string,revision:number):Promise<Source>{
 const item=await allowedNotice(user,id);
 if(item.kind!=='boarding_pass')throw new NoticeFailure('Elige un pase de abordar de tu cuenta.',404);
 if(item.revision!==revision)throw new NoticeFailure('El pase cambió. Abre su versión actual.',409);
 let data:{file_key:string;filename:string;mime_type:string;size:number}|null;
 const legacy=Boolean(file===id&&item.file_key);
 if(legacy)data={file_key:item.file_key,filename:item.filename,mime_type:'application/pdf',size:item.size};
 else data=await database().prepare("SELECT file_key,filename,mime_type,size FROM jac_notice_attachments WHERE id=? AND notice_id=? AND state='ready'").bind(file,id).first<{file_key:string;filename:string;mime_type:string;size:number}>();
 if(!data)throw new NoticeFailure('El archivo ya no está disponible.',404);
 if(!['application/pdf','image/jpeg','image/png'].includes(data.mime_type)||!Number.isSafeInteger(data.size)||data.size<=0||data.size>MAX_PDF_BYTES)throw new NoticeFailure('Este archivo no es un pase compatible de hasta 10 MB.');
 return {key:data.file_key,filename:data.filename,mimeType:data.mime_type,size:data.size,revision:item.revision,travelDate:item.travel_date,legacy};
}
async function readSource(body:ReadableStream<Uint8Array>){
 const reader=body.getReader(),chunks:Uint8Array[]=[];let length=0;
 try{for(;;){const next=await reader.read();if(next.done)break;length+=next.value.length;if(length>MAX_PDF_BYTES)throw new NoticeFailure('El pase supera los 10 MB.',413);chunks.push(next.value);}}catch(error){await reader.cancel().catch(()=>{});throw error;}finally{reader.releaseLock();}
 const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return bytes;
}
async function sha256(bytes:Uint8Array){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes)))).map(value=>value.toString(16).padStart(2,'0')).join('');}
type DisplayDetails={passenger?:string;origin?:string;destination?:string;departureTime?:string;boardingTime?:string;seat?:string};
function displayDetails(barcode:string,filename:string,confirmed:DisplayDetails|undefined,legIndex:number|undefined):DisplayDetails{
 const count=Number(barcode[1]),parsed=parseWalletBarcodeDetails(barcode);
 if(legIndex!==undefined&&legIndex>=count)throw new NoticeFailure('Elige un tramo válido del pase de abordar.');
 if(confirmed&&count>1&&legIndex===undefined)throw new NoticeFailure('Elige el tramo del pase antes de preparar Wallet.');
 // Legacy clients did not select a leg. Keep the common passenger, but never
 // combine a filename route or seat with an arbitrary multi-leg selection.
 const leg=parsed?.legs[legIndex??(count===1?0:-1)];
 const filenameDetails=count===1?boardingFilenameDetails(filename):null;
 const fallback:DisplayDetails={passenger:parsed?.passenger??filenameDetails?.passenger,origin:leg?.origin??filenameDetails?.origin,destination:leg?.destination??filenameDetails?.destination,seat:leg?.seat};
 const result:DisplayDetails={};
 for(const key of ['passenger','origin','destination','departureTime','boardingTime','seat'] as const){
  // An explicit blank is the user's choice to omit a suggestion. Missing keys
  // from older clients can still use conservative original-document metadata.
  const value=confirmed&&Object.hasOwn(confirmed,key)?confirmed[key]:fallback[key];
  if(value)result[key]=value;
 }
 return result;
}
async function finalSourceGate(user:AccessUser,guard:WalletGuard,p:{id:string;file:string;revision:number},source:Source,config:{credentials:string;version:number}){
 const legacy=source.legacy;
 const attachment=legacy?"wallet_notice.file_key=? AND wallet_notice.filename=? AND wallet_notice.size=?":`EXISTS(SELECT 1 FROM jac_notice_attachments wallet_attachment WHERE wallet_attachment.notice_id=wallet_notice.id AND wallet_attachment.id=? AND wallet_attachment.state='ready' AND wallet_attachment.file_key=? AND wallet_attachment.filename=? AND wallet_attachment.mime_type=? AND wallet_attachment.size=?)`;
 const bindings=legacy?[source.key,source.filename,source.size]:[p.file,source.key,source.filename,source.mimeType,source.size];
 const row=await database().prepare(`SELECT 1 AS permitted FROM jac_notices wallet_notice WHERE wallet_notice.id=? AND wallet_notice.kind='boarding_pass' AND wallet_notice.revision=? AND wallet_notice.travel_date=? AND EXISTS(SELECT 1 FROM jac_notice_recipients wallet_recipient WHERE wallet_recipient.notice_id=wallet_notice.id AND wallet_recipient.user_id=?) AND ${attachment} AND EXISTS(SELECT 1 FROM jac_notice_settings wallet_settings WHERE wallet_settings.id='jac' AND wallet_settings.version=? AND wallet_settings.credentials=?) AND ${sessionSql('create')}`).bind(p.id,p.revision,source.travelDate,user.id,...bindings,config.version,config.credentials,guard.sessionId,user.id).first();
 if(!row)throw new NoticeFailure('El pase o tu acceso cambió. Abre de nuevo el documento original.',403);
}
export async function createBoardingWallet(user:AccessUser,input:unknown,guard:WalletGuard){
 await authorize(user,guard,'create');
 const parsed=createSchema.safeParse(input);if(!parsed.success)throw new NoticeFailure('Revisa los datos del pase, la silla y las horas en formato HH:mm.');
 const p=parsed.data,barcode=validateWalletBarcode(p.barcode),config=await noticeConfig(),keys=await pushCredentials(config) as StoredCredentials;
 if(!usableWallet(keys.wallet))throw new NoticeFailure('Wallet todavía no está configurado o su certificado venció.',409);
 const snapshot=await sourceMetadata(user,p.id,p.file,p.revision);
 const attachment=await noticeAttachment(user,p.id,p.file);
 await authorize(user,guard,'create');
 const bytes=await readSource(attachment.object.body);
 await authorize(user,guard,'create');
 if(bytes.length!==snapshot.size||fileMime(bytes)!==snapshot.mimeType||attachment.filename!==snapshot.filename||attachment.mimeType!==snapshot.mimeType)throw new NoticeFailure('El archivo cambió. Abre de nuevo el pase original.',409);
 const hash=await sha256(bytes);
 await authorize(user,guard,'create');
 if(hash!==p.sourceSha256)throw new NoticeFailure('La copia del pase cambió. Vuelve a abrir el original.',409);
 const revalidateSource=async()=>{const source=await sourceMetadata(user,p.id,p.file,p.revision);if(JSON.stringify(source)!==JSON.stringify(snapshot))throw new NoticeFailure('El pase cambió. Abre su versión actual.',409);};
 await revalidateSource();
 const details=displayDetails(barcode.message,snapshot.filename,p.details,p.legIndex);
 const serialParts:unknown[]=['boarding-wallet-v1',user.id,p.id,p.file,hash,barcode.format,barcode.message];
 // Preserve the old stable serial for a single/first leg. Other selected legs
 // must not overwrite each other's copies when the same barcode covers both.
 if(p.legIndex!==undefined&&p.legIndex>0)serialParts.push(p.legIndex);
 const serialNumber='JAC-'+await sha256(new TextEncoder().encode(JSON.stringify(serialParts)));
 await authorize(user,guard,'create');
 // The native reader supplies an exact supported IATA payload from the
 // authorized original. Hash binding detects stale source copies; it does not
 // claim independent server-side barcode decoding or airline issuance.
 const output=await buildBoardingWalletPass(keys.wallet,{serialNumber,description:'Pase de abordar · JAC',...details,...(validBoardingDate(snapshot.travelDate)?{travelDate:snapshot.travelDate}:{}),barcode});
 await authorize(user,guard,'create');
 if(output.length===0||output.length>MAX_WALLET_BYTES)throw new NoticeFailure('No se pudo preparar un pase de Wallet dentro del límite permitido.',413);
 await revalidateSource();
 const current=await noticeConfig();if(current.version!==config.version||current.credentials!==config.credentials)throw new NoticeFailure('La configuración de Wallet cambió. Inténtalo de nuevo.',409);
 if(!usableWallet(keys.wallet))throw new NoticeFailure('El certificado de Wallet venció. Actualiza la conexión.',409);
 await authorize(user,guard,'create');
 // One final SQL snapshot covers access and source/config revision together.
 // No asynchronous work follows before the private bytes reach the route.
 await finalSourceGate(user,guard,p,snapshot,config);
 return {bytes:output,filename:'JAC-pase-'+p.id+'.pkpass'};
}
