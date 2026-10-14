'use client';
import {useState,useEffect} from 'react';
import {Button} from '@/components/ui/button';
import {clearBrowserAgendaCache} from '@/lib/agenda-cache';
import {Input} from '@/components/ui/input';
export default function AuthForm({mode='login',returnTo='/'}:{mode?:'login'|'bootstrap'|'password';returnTo?:string}){
 const [token,setToken]=useState(''),[username,setUsername]=useState(mode==='bootstrap'?'camilo':''),[password,setPassword]=useState(''),[confirmation,setConfirmation]=useState(''),[currentPassword,setCurrentPassword]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{if(mode==='login'){clearBrowserAgendaCache();const t=new URLSearchParams(location.hash.slice(1)).get('activacion');if(t){setToken(t);history.replaceState(null,'',location.pathname);}}},[mode]);
 const action=token?'activate':mode==='bootstrap'?'bootstrap':mode==='password'?'password':'login',newPassword=action!=='login';
 return <form className="editor auth-form" onSubmit={async e=>{e.preventDefault();if(newPassword&&password!==confirmation){setError('Las contraseñas no coinciden.');return;}setBusy(true);setError('');clearBrowserAgendaCache();try{const r=await fetch('/api/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,username,password,currentPassword,token})});const result=await r.json() as {error?:string};if(!r.ok)throw new Error(result.error||'No pudimos iniciar sesión.');setPassword('');setConfirmation('');setCurrentPassword('');location.assign(returnTo.startsWith('/')&&!returnTo.startsWith('//')?returnTo:'/');}catch(e){setError((e as Error).message);setBusy(false);}}}>
 {token&&<><h2>Activar tu cuenta</h2><p className="muted">Establece tu contraseña para entrar a la nómina. El enlace se utiliza una sola vez.</p></>}
 {!token&&mode!=='password'&&<label>Usuario<Input aria-label="Usuario" value={username} onChange={e=>setUsername(e.target.value)} required autoComplete="username" maxLength={action==='login'?254:40}/></label>}
 {mode==='password'&&<label>Contraseña actual<Input aria-label="Contraseña actual" type="password" value={currentPassword} onChange={e=>setCurrentPassword(e.target.value)} required autoComplete="current-password"/></label>}
 <label>{newPassword?'Nueva contraseña':'Contraseña'}<Input aria-label={newPassword?'Nueva contraseña':'Contraseña'} type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete={newPassword?'new-password':'current-password'}/></label>
 {newPassword&&<><label>Confirmar contraseña<Input aria-label="Confirmar contraseña" type="password" value={confirmation} onChange={e=>setConfirmation(e.target.value)} required autoComplete="new-password"/></label></>}
 {error&&<p className="message error" role="alert">{error}</p>}
 <Button className="primary" type="submit" disabled={busy}>{busy?'Validando…':action==='bootstrap'?'Activar acceso propio':action==='activate'?'Activar mi cuenta':action==='password'?'Guardar contraseña':'Iniciar sesión'}</Button>
 {mode==='password'&&<p className="muted">Al guardar, se cerrarán tus otras sesiones.</p>}
 </form>;
}
