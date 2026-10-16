import {payrollUser} from '@/lib/payroll-access';
import {can} from '@/lib/payroll-permissions';
import {payrollReadAuthorized} from '@/lib/payroll-section-guard';
import {readPayroll} from '@/lib/payroll-store';
import {categoryNames,closedDate,periodLabel} from '@/lib/payroll';
import PrintControls from './controls';
export const dynamic='force-dynamic';
const amount=(v:number)=>'$ '+v.toLocaleString('es-CO',{minimumFractionDigits:2,maximumFractionDigits:2});
export default async function PrintPage({searchParams}:{searchParams:Promise<{period?:string;employee?:string}>}){
 const params=await searchParams;return <Slip period={params.period} employee={params.employee}/>;
}
async function Slip({period,employee}:{period?:string;employee?:string}){
 const user=await payrollUser();if(!user){const path='/payroll/print?'+new URLSearchParams({period:period||'',employee:employee||''});return <main className="login"><div className="login-box"><h1>Inicia sesión para imprimir</h1><a className="primary btn" target="_top" href={'/acceso?'+new URLSearchParams({returnTo:path})}>Iniciar sesión</a></div></main>;}
 if(!can(user,'export'))return <main className="login"><div className="login-box"><h1>Sin permiso para imprimir</h1><p>Solicita al administrador el permiso de documentos.</p><a href="/">Volver a nómina</a></div></main>;
 const {data}=await readPayroll(),p=data.periods.find(p=>p.id===period),s=p?.snapshot,rows=s?.rows.filter(r=>r.employeeId===employee)||[];
 if(!await payrollReadAuthorized(user))return <main className="login"><div className="login-box"><h1>Tu sesión o permiso cambió</h1><p>Inicia sesión de nuevo para consultar tus documentos.</p></div></main>;
 if(!p||p.status!=='cerrada'||!s||!rows.length)return <main className="print-slip"><h1>Desprendible no disponible</h1><p>Selecciona una persona con pago en una quincena cerrada.</p><a href="/">Volver a nómina</a></main>;
 const person=rows[0];return <main className="print-slip"><PrintControls/><header><strong className="print-brand">JAC MUSIC</strong><div>{s.company}<br/>NIT {s.nit}</div></header><h1>Desprendible de pago</h1><p>{periodLabel(p)}</p><section className="print-person"><h2>{person.name}</h2><p>Documento: {person.document||'Sin registrar'}<br/>{person.role}</p></section>{rows.map(r=><section key={r.category}><h3>{categoryNames[r.category]}</h3><table><thead><tr><th>Concepto</th><th>Cantidad</th><th>Valor</th></tr></thead><tbody>{r.items.map((i,index)=><tr key={index}><td>{i.concept}{i.reference&&<small>{i.reference}</small>}</td><td>{i.quantity}</td><td>{i.kind==='deduccion'?'− ':''}{amount(i.amount)}</td></tr>)}</tbody></table><p className="print-subtotal">Neto {categoryNames[r.category]} <strong>{amount(r.net)}</strong></p></section>)}<div className="print-total"><span>Total a pagar</span><strong>{amount(rows.reduce((v,r)=>v+r.net,0))}</strong></div><footer>Cierre: {closedDate(s.closedAt)}<br/>Responsable: {s.closedBy}{p.revisions?.length?<><br/>Versión del cierre: {p.revisions.length+1}</>:null}</footer></main>;
}
