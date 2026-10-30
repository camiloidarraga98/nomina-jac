import {payrollUser} from '@/lib/payroll-access';
import {can} from '@/lib/payroll-permissions';
import {payrollReadAuthorized} from '@/lib/payroll-section-guard';
import {readPayroll} from '@/lib/payroll-store';
import SlipDocument from './slip-document';
import PrintControls from './controls';
import './document.css';
export const dynamic='force-dynamic';
export default async function PrintPage({searchParams}:{searchParams:Promise<{period?:string;employee?:string}>}){
 const params=await searchParams;return <Slip period={params.period} employee={params.employee}/>;
}
async function Slip({period,employee}:{period?:string;employee?:string}){
 const user=await payrollUser();if(!user){const path='/payroll/print?'+new URLSearchParams({period:period||'',employee:employee||''});return <main className="login"><div className="login-box"><h1>Inicia sesión para imprimir</h1><a className="primary btn" target="_top" href={'/acceso?'+new URLSearchParams({returnTo:path})}>Iniciar sesión</a></div></main>;}
 if(!can(user,'export'))return <main className="login"><div className="login-box"><h1>Sin permiso para imprimir</h1><p>Solicita al administrador el permiso de documentos.</p><a href="/">Volver a nómina</a></div></main>;
 const {data}=await readPayroll(),p=data.periods.find(p=>p.id===period),s=p?.snapshot,rows=s?.rows.filter(r=>r.employeeId===employee)||[];
 if(!await payrollReadAuthorized(user))return <main className="login"><div className="login-box"><h1>Tu sesión o permiso cambió</h1><p>Inicia sesión de nuevo para consultar tus documentos.</p></div></main>;
 if(!p||p.status!=='cerrada'||!s||!rows.length)return <main className="print-slip"><h1>Desprendible no disponible</h1><p>Selecciona una persona con pago en una quincena cerrada.</p><a href="/">Volver a nómina</a></main>;
 return <main className="print-slip"><PrintControls/><SlipDocument period={p} employee={employee!}/></main>;
}
