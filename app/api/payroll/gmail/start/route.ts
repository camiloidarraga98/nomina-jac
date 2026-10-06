import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {isOwnerEmail} from '@/lib/payroll-policy';
import {startMailOauth} from '@/lib/payroll-mail';
export const dynamic='force-dynamic';
export async function POST(req:Request){const user=await payrollUser();if(!user||!isOwnerEmail(user.email))return Response.json({error:'Solo Camilo puede conectar Gmail.'},{status:403,headers:payrollHeaders});if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Origen no autorizado.'},{status:403,headers:payrollHeaders});try{const {url,state}=await startMailOauth(user.email);return Response.json({url},{headers:{...payrollHeaders,'Set-Cookie':`jac_gmail_state=${state}; Path=/api/payroll/gmail; HttpOnly; Secure; SameSite=Lax; Max-Age=600`}});}catch(e){return Response.json({error:(e as Error).message},{status:400,headers:payrollHeaders});}}
