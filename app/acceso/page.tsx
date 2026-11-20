import Link from 'next/link';
import {payrollUser} from '@/lib/payroll-access';
import {ownAuthReady} from '@/lib/payroll-auth-store';
import {chatGPTSignInPath} from '@/app/chatgpt-auth';
import AccessScreen from './access-screen';

export const dynamic = 'force-dynamic';

export default async function AccessPage({searchParams}: {searchParams: Promise<{configurar?: string; returnTo?: string}>}) {
  const params = await searchParams;
  let ready: boolean, bootstrap: boolean;
  try {
    ready = await ownAuthReady();
    const user = await payrollUser();
    bootstrap = !ready && !!user?.isOwner;
  } catch {
    return (
      <main className="login"><div className="login-box">
        <h1>No pudimos abrir el acceso.</h1>
        <p>Intenta de nuevo en unos momentos.</p>
        <Link className="btn primary" href="/acceso">Volver a intentar</Link>
      </div></main>
    );
  }
  return <AccessScreen ready={ready} bootstrap={bootstrap} returnTo={params.returnTo} setupURL={chatGPTSignInPath('/acceso?configurar=1')}/>;
}
