import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {readPayroll} from '@/lib/payroll-store';
import {mobileOverview,mobilePeriod} from '@/lib/payroll-mobile';

export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:payrollHeaders});

export async function GET(req:Request){
 const user=await payrollUser();
 // The native app requires a real account session. Never expose the development/legacy bootstrap.
 if(!user||user.legacy)return reply({error:'Inicia sesión con tu cuenta de nómina.'},401);
 const id=new URL(req.url).searchParams.get('period');
 if(id!==null&&(!id||id.length>80))return reply({error:'Selecciona una quincena válida.'},400);
 try{
  const {data,version}=await readPayroll();
  if(id!==null){
   const p=data.periods.find(p=>p.id===id);
   if(!p)return reply({error:'La quincena no existe. Actualiza el listado.'},404);
   return reply(mobilePeriod(data,p,version));
  }
  return reply({...mobileOverview(data,version),user});
 }catch{
  console.error('Mobile payroll load failed');
  return reply({error:'No se pudo consultar la nómina. Intenta de nuevo.'},503);
 }
}
