import {payrollUser} from '@/lib/payroll-access';
import {ownAuthReady} from '@/lib/payroll-auth-store';
import {chatGPTSignInPath} from '@/app/chatgpt-auth';
import AuthForm from '@/app/auth-form';
export const dynamic='force-dynamic';
export default async function AccessPage({searchParams}:{searchParams:Promise<{configurar?:string;returnTo?:string}>}){const params=await searchParams;return <Access params={params}/>;}
async function Access({params}:{params:{configurar?:string;returnTo?:string}}){try{const ready=await ownAuthReady(),user=await payrollUser(),bootstrap=!ready&&user?.isOwner;
 return <main className="login"><div className="login-box"><div className="wordmark">JAC<span>MUSIC</span></div><p className="eyebrow">NÓMINA Y EQUIPO</p><h1>{bootstrap?'Tu acceso propio.':'Bienvenido al equipo.'}</h1><p>{bootstrap?'Elige tu usuario y contraseña. Desde ese momento el equipo entrará con sus propias cuentas.':'Ingresa con el usuario y la contraseña de tu cuenta.'}</p><AuthForm mode={bootstrap?'bootstrap':'login'} returnTo={params.returnTo||'/'}/>{!ready&&!bootstrap&&<p className="muted">Camilo debe activar primero el acceso propio. <a href={chatGPTSignInPath('/acceso?configurar=1')} target="_top">Verificar administrador</a></p>}{ready&&<p className="muted">Si necesitas activar o recuperar tu cuenta, solicita un enlace al administrador.</p>}</div><div className="login-art" aria-hidden="true"><span>JAC</span><div className="bars">{[30,60,90,45,100,75,35,85,55].map((n,i)=><i key={i} style={{height:n+'%'}}/>)}</div></div></main>;
 }catch{ return <main className="login"><div className="login-box"><h1>No pudimos abrir el acceso.</h1><p>Intenta de nuevo en unos momentos.</p><a className="btn primary" href="/acceso">Volver a intentar</a></div></main>;}}
