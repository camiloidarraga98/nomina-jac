import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {isOwnerEmail} from '@/lib/payroll-policy';
import {finishMailOauth} from '@/lib/payroll-mail';
import {finishNativeMailOauth} from '@/lib/payroll-mobile-oauth';
import {finishCalendarCallback} from '@/lib/calendar-oauth';
export const dynamic='force-dynamic';
export async function GET(req:Request){
 try{const calendar=await finishCalendarCallback(req);if(calendar)return new Response(null,{status:303,headers:{...payrollHeaders,'Referrer-Policy':'no-referrer',Location:calendar.url,'Set-Cookie':calendar.cookie}});}catch{console.error('Calendar callback failed');}
 try{const native=await finishNativeMailOauth(req);if(native)return new Response(null,{status:303,headers:{...payrollHeaders,'Referrer-Policy':'no-referrer',Location:native.url,'Set-Cookie':native.cookie}});}catch{console.error('Native Gmail callback failed');}
 const url=new URL(req.url),state=url.searchParams.get('state'),code=url.searchParams.get('code'),cookie=req.headers.get('cookie')?.split(';').map(x=>x.trim()).find(x=>x.startsWith('jac_gmail_state='))?.slice('jac_gmail_state='.length);const user=await payrollUser();let result='error';try{if(!user||!isOwnerEmail(user.email)||!state||state!==cookie||!code||url.searchParams.has('error'))throw new Error('Autorización inválida');await finishMailOauth(state,code,user.email);result='connected';}catch{result='error';}return new Response(null,{status:303,headers:{...payrollHeaders,Location:'/?mail='+result,'Set-Cookie':'jac_gmail_state=; Path=/api/payroll/gmail; HttpOnly; Secure; SameSite=Lax; Max-Age=0'}});
}
