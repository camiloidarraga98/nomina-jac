import {payrollHeaders} from '@/lib/payroll-access';
import {authorizeCalendarTicket} from '@/lib/calendar-oauth';
export const dynamic='force-dynamic';
export async function GET(req:Request){
 const headers={...payrollHeaders,'Referrer-Policy':'no-referrer'};
 try{const result=await authorizeCalendarTicket(new URL(req.url).searchParams.get('ticket'));return new Response(null,{status:303,headers:{...headers,Location:result.url,'Set-Cookie':result.cookie}});}
 catch{return new Response('La autorización venció o la sesión cambió. Cierra esta ventana y vuelve a conectar Agenda.',{status:400,headers:{...headers,'Content-Type':'text/plain; charset=utf-8'}});}
}
