import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {hasSection,type AccessUser} from '@/lib/payroll-permissions';
import {sessionToken,tokenHash} from '@/lib/payroll-auth-crypto';
import {noticeOwner} from '@/lib/notifications';
import {NoticeFailure} from '@/lib/notifications-core';
import {boardingWalletSettings,configureBoardingWallet,createBoardingWallet,type WalletGuard} from '@/lib/boarding-wallet-store';

export const dynamic='force-dynamic';
const MAX_REQUEST_BYTES=200*1024;
const json=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});
const failure=(error:unknown)=>json({error:error instanceof NoticeFailure?error.message:'No se pudo completar la operación de Wallet.'},error instanceof NoticeFailure?error.status:502);
function guardFor(req:Request):WalletGuard{
 const local=/^(localhost|127\.0\.0\.1)$/.test(new URL(req.url).hostname),token=sessionToken(req.headers.get('cookie')??'',!local);
 return {sessionId:token?tokenHash(token):'',current:payrollUser};
}
const permitted=(user:AccessUser)=>!user.legacy&&(hasSection(user,'boarding')||noticeOwner(user));
async function requestJSON(req:Request){
 const declared=req.headers.get('content-length');if(declared&&(!/^\d+$/.test(declared)||Number(declared)>MAX_REQUEST_BYTES))throw new NoticeFailure('Los archivos de configuración superan el límite permitido.',413);
 if(!req.body)throw new NoticeFailure('La solicitud de Wallet está vacía.');
 const reader=req.body.getReader(),chunks:Uint8Array[]=[];let length=0;
 try{for(;;){const part=await reader.read();if(part.done)break;length+=part.value.length;if(length>MAX_REQUEST_BYTES)throw new NoticeFailure('Los archivos de configuración superan el límite permitido.',413);chunks.push(part.value);}}catch(error){await reader.cancel().catch(()=>{});throw error;}finally{reader.releaseLock();}
 const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 let body:unknown;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{throw new NoticeFailure('La solicitud de Wallet no es válida.');}
 if(!body||typeof body!=='object'||Array.isArray(body))throw new NoticeFailure('La solicitud de Wallet no es válida.');return body as Record<string,unknown>;
}
export async function GET(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return json({error:'Inicia sesión con tu cuenta de JAC.'},401);if(!permitted(user))return json({error:'Tu cuenta no tiene acceso a pases o a su configuración.'},403);
 try{return json(await boardingWalletSettings(user,guardFor(req)));}catch(error){return failure(error);}
}
export async function POST(req:Request){
 const user=await payrollUser();if(!user||user.legacy)return json({error:'Inicia sesión con tu cuenta de JAC.'},401);if(!permitted(user))return json({error:'Tu cuenta no tiene acceso a pases o a su configuración.'},403);
 if(req.headers.get('origin')!==new URL(req.url).origin)return json({error:'Origen no autorizado.'},403);
 try{
  const body=await requestJSON(req),guard=guardFor(req);
  if(body.action==='configure'){if(!noticeOwner(user))return json({error:'Solo un administrador puede configurar Wallet.'},403);return json(await configureBoardingWallet(user,body,guard));}
  if(body.action==='create'){
   if(!hasSection(user,'boarding'))return json({error:'Tu cuenta no tiene acceso a pases de abordar.'},403);
   const result=await createBoardingWallet(user,body,guard);
   return new Response(new Uint8Array(result.bytes).buffer,{headers:{...payrollHeaders,'Content-Type':'application/vnd.apple.pkpass','Content-Disposition':'attachment; filename="'+result.filename+'"'}});
  }
  throw new NoticeFailure('La operación de Wallet no es válida.');
 }catch(error){return failure(error);}
}
