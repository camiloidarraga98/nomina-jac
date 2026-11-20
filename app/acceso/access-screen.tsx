import AuthForm from '@/app/auth-form';

type AccessScreenProps = {
  ready: boolean;
  bootstrap: boolean;
  returnTo?: string;
  setupURL?: string;
};

export default function AccessScreen({ready, bootstrap, returnTo, setupURL}: AccessScreenProps) {
  return (
    <main className="login">
      <div className="login-box">
        <div className="wordmark">JAC<span>MUSIC</span></div>
        <p className="eyebrow">NÓMINA Y EQUIPO</p>
        <h1>{bootstrap ? 'Tu acceso propio.' : 'Bienvenido al equipo.'}</h1>
        <p>{bootstrap
          ? 'Elige tu usuario y contraseña. Desde ese momento el equipo entrará con sus propias cuentas.'
          : 'Ingresa con el usuario y la contraseña de tu cuenta.'}</p>
        <AuthForm mode={bootstrap ? 'bootstrap' : 'login'} returnTo={returnTo || '/'}/>
        {!ready && !bootstrap && (
          <p className="muted">
            Camilo debe activar primero el acceso propio. <a href={setupURL} target="_top">Verificar administrador</a>
          </p>
        )}
        {ready && <p className="muted">Si necesitas activar o recuperar tu cuenta, solicita un enlace al administrador.</p>}
      </div>
      <div className="login-art" aria-hidden="true">
        <span>JAC</span>
        <div className="bars">
          {[30, 60, 90, 45, 100, 75, 35, 85, 55].map((n, i) => <i key={i} style={{height: n + '%'}}/>)}
        </div>
      </div>
    </main>
  );
}
