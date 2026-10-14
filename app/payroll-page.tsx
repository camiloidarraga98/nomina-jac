import {agendaCacheContext} from '@/lib/agenda-cache-context';
import {payrollUser} from '@/lib/payroll-access';
import {readPayroll} from '@/lib/payroll-store';
import PayrollApp from './payroll-app';
import {payrollHref,type PayrollRoute} from '@/lib/payroll-navigation';
import {itineraryWorkspace,itineraryViews} from '@/lib/itineraries-access';
import {redirect,notFound} from 'next/navigation';
export const dynamic='force-dynamic';
export default async function PayrollPage({route={view:'quincena',tab:'shows'},periodId}:{route?:PayrollRoute;periodId?:string}){const href=payrollHref(route.view,route.tab,periodId);let user;try{user=await payrollUser();}catch{console.error('Payroll page unavailable');return unavailable(href);}if(user?.itinerariesOnly&&!itineraryViews.includes(route.view))redirect('/itinerarios');if(user&&['usuarios','conexiones','crm'].includes(route.view)&&!user.isOwner)notFound();try{if(!user)return <main className="login"><div className="login-box"><div className="wordmark">JAC<span>MUSIC</span></div><p className="eyebrow">NÓMINA Y EQUIPO</p><h1>Cada pago,<br/>en su lugar.</h1><p>Administra los shows, las novedades y la nómina de tu equipo.</p><a className="primary btn" href={href==='/'?'/acceso':'/acceso?returnTo='+encodeURIComponent(href)}>Iniciar sesión</a><p className="muted">Acceso exclusivo para las cuentas autorizadas por el administrador.</p></div><div className="login-art" aria-hidden="true"><span>JAC</span><div className="bars">{[30,60,90,45,100,75,35,85,55].map((n,i)=><i key={i} style={{height:n+'%'}}/>)}</div></div></main>;
 return <PayrollApp agendaCache={await agendaCacheContext(user)} initialRoute={route} initialPeriodId={periodId} initial={user.itinerariesOnly?{data:itineraryWorkspace(),version:0}:await readPayroll()} user={user.displayName} isOwner={user.isOwner} access={user}/>;
 }catch{console.error('Payroll page unavailable');return unavailable(href);}}
function unavailable(href:string){return <main className="login"><div className="login-box"><h1>No pudimos cargar la nómina.</h1><p>Intenta de nuevo en unos momentos. Tus datos se conservan.</p><a className="btn primary" href={href}>Volver a intentar</a></div></main>;}
