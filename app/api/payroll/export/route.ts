import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {readPayroll} from '@/lib/payroll-store';
import {payrollPdf,payrollXlsx,payrollSlipZip} from '@/lib/payroll-export';
import {can} from '@/lib/payroll-permissions';
export const dynamic='force-dynamic';
export async function GET(req:Request){
 const user=await payrollUser();if(!user)return Response.json({error:'Acceso no autorizado.'},{status:401,headers:payrollHeaders});
 if(!can(user,'export'))return Response.json({error:'No tienes permiso para descargar documentos.'},{status:403,headers:payrollHeaders});
 try{const url=new URL(req.url),id=url.searchParams.get('period'),format=url.searchParams.get('format')||'pdf',employee=url.searchParams.get('employee')||undefined;
 const {data}=await readPayroll();const p=data.periods.find(p=>p.id===id);if(!p||p.status!=='cerrada'||!p.snapshot)return Response.json({error:'Cierra la quincena para generar sus documentos.'},{status:400,headers:payrollHeaders});
 if(employee&&!p.snapshot.rows.some(r=>r.employeeId===employee))return Response.json({error:'La persona no tiene pagos en este cierre.'},{status:404,headers:payrollHeaders});
 let bytes:Uint8Array,type:string,ext:string,label:string;
 if(format==='xlsx'){bytes=payrollXlsx(p);type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';ext='xlsx';label='nomina';}
 else if(format==='zip'){bytes=await payrollSlipZip(p);type='application/zip';ext='zip';label='desprendibles';}
 else if(format==='pdf'||format==='slips'){bytes=await payrollPdf(p,employee,format==='slips');type='application/pdf';ext='pdf';label=employee?'desprendible-'+employee:format==='slips'?'desprendibles':'resumen-nomina';}
 else return Response.json({error:'Formato no válido.'},{status:400,headers:payrollHeaders});
 return new Response(bytes as BodyInit,{headers:{...payrollHeaders,'Content-Type':type,'Content-Disposition':`attachment; filename="${label}-${p.start}.${ext}"`,'X-Content-Type-Options':'nosniff'}});
 }catch(e){console.error('Payroll export failed',e);return Response.json({error:'No se pudo generar el documento. Intenta de nuevo.'},{status:500,headers:payrollHeaders});}
}
