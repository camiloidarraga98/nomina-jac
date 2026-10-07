import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {startNativeMailOauth,authorizeNativeMail} from '@/lib/payroll-mobile-oauth';
import {isOwnerEmail} from '@/lib/payroll-policy';
export const dynamic='force-dynamic';
const headers={...payrollHeaders,'Referrer-Policy':'no-referrer'};
export async function POST(req:Request){
 const user=await payrollUser();
 if(!user||user.legacy)return Response.json({error:'Inicia sesión con tu cuenta de nómina.'},{status:401,headers});
 if(!user.isOwner||!isOwnerEmail(user.email))return Response.json({error:'Solo Camilo puede conectar Gmail.'},{status:403,headers});
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Origen no autorizado.'},{status:403,headers});
 try{return Response.json(await startNativeMailOauth(user,req.headers.get('cookie')||''),{headers});}
 catch(e){return Response.json({error:(e as Error).message},{status:400,headers});}
}
export async function GET(req:Request){
 try{const result=await authorizeNativeMail(new URL(req.url).searchParams.get('ticket'));return new Response(null,{status:303,headers:{...headers,Location:result.url,'Set-Cookie':result.cookie}});}
 catch{return new Response('La autorización venció o la sesión cambió. Cierra esta ventana y vuelve a conectar Gmail desde la app.',{status:400,headers:{...headers,'Content-Type':'text/plain; charset=utf-8'}});}
}
