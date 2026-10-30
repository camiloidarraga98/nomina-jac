import {payrollUser,payrollHeaders} from '@/lib/payroll-access';
import {readPayroll} from '@/lib/payroll-store';
import {payrollPdf,payrollXlsx,payrollSlipZip,payrollReview,type PayrollReview} from '@/lib/payroll-export';
import {can,hasSection} from '@/lib/payroll-permissions';
import {payrollReadAuthorized} from '@/lib/payroll-section-guard';
export const dynamic='force-dynamic';
export async function GET(req:Request){
 const user=await payrollUser();if(!user)return Response.json({error:'Acceso no autorizado.'},{status:401,headers:payrollHeaders});
 if(!hasSection(user,'payroll')||!can(user,'export'))return Response.json({error:'No tienes permiso para descargar documentos de nómina.'},{status:403,headers:payrollHeaders});
 try{const url=new URL(req.url),id=url.searchParams.get('period'),format=url.searchParams.get('format')||'pdf',employee=url.searchParams.get('employee')||undefined;
 const mode=url.searchParams.get('mode')||'final',isReview=mode==='preliquidation';
 if(!['final','preliquidation'].includes(mode)||isReview&&(!['pdf','xlsx'].includes(format)||url.searchParams.has('employee')))return Response.json({error:'La preliquidación solo permite el reporte general en PDF o Excel.'},{status:400,headers:payrollHeaders});
 const {data,version}=await readPayroll();let p=data.periods.find(p=>p.id===id),review:PayrollReview|undefined;
 if(!p)return Response.json({error:'La quincena no existe. Actualiza el listado.'},{status:404,headers:payrollHeaders});
 if(isReview){
  const expected=url.searchParams.get('version');
  if(expected===null||!/^\d+$/.test(expected)||!Number.isSafeInteger(Number(expected)))return Response.json({error:'Actualiza la quincena antes de preliquidar.'},{status:400,headers:payrollHeaders});
  if(Number(expected)!==version)return Response.json({error:'La nómina cambió. Actualiza la quincena y vuelve a generar la preliquidación.'},{status:409,headers:payrollHeaders});
  if(p.status!=='abierta')return Response.json({error:'La quincena ya está cerrada. Descarga su liquidación definitiva.'},{status:400,headers:payrollHeaders});
  const prepared=payrollReview(data,p,version);p=prepared.period;review=prepared.review;
 }else if(p.status!=='cerrada'||!p.snapshot)return Response.json({error:'Cierra la quincena para generar sus documentos definitivos.'},{status:400,headers:payrollHeaders});
 if(employee&&!p.snapshot!.rows.some(r=>r.employeeId===employee))return Response.json({error:'La persona no tiene pagos en este cierre.'},{status:404,headers:payrollHeaders});
 let bytes:Uint8Array,type:string,ext:string,label:string;
 if(format==='xlsx'){bytes=payrollXlsx(p,review);type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';ext='xlsx';label='nomina';}
 else if(format==='zip'){bytes=await payrollSlipZip(p);type='application/zip';ext='zip';label='desprendibles';}
 else if(format==='pdf'||format==='slips'){bytes=await payrollPdf(p,employee,format==='slips',review);type='application/pdf';ext='pdf';label=employee?'desprendible-'+employee:format==='slips'?'desprendibles':'resumen-nomina';}
 else return Response.json({error:'Formato no válido.'},{status:400,headers:payrollHeaders});
 if(isReview&&(await readPayroll()).version!==version)return Response.json({error:'La nómina cambió mientras se generaba el reporte. Actualiza y vuelve a preliquidar.'},{status:409,headers:payrollHeaders});
 if(!await payrollReadAuthorized(user))return Response.json({error:'Tu sesión o permiso cambió. Inicia sesión de nuevo.'},{status:403,headers:payrollHeaders});
 if(review)label='preliquidacion-v'+review.version;
 return new Response(bytes as BodyInit,{headers:{...payrollHeaders,'Content-Type':type,'Content-Disposition':`attachment; filename="${label}-${p.start}.${ext}"`,'X-Content-Type-Options':'nosniff'}});
 }catch(e){console.error('Payroll export failed',e);return Response.json({error:'No se pudo generar el documento. Intenta de nuevo.'},{status:500,headers:payrollHeaders});}
}
