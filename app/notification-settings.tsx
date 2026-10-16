'use client';
import {useEffect,useRef,useState} from 'react';
import {Bell} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {Dialog,DialogContent,DialogTitle,DialogDescription} from '@/components/ui/dialog';
import {browserPushClient,browserPushSupported,type WebPushClient} from '@/lib/web-push-client';
import {BoardingChannelSettings,NoticeSettings,type Feed} from './notices-panel';

export default function NotificationSettings({userID,owner,view,enabled=true}:{userID:string;owner:boolean;view:string;enabled?:boolean}){
 const [feed,setFeed]=useState<Feed>(),[error,setError]=useState(''),[message,setMessage]=useState(''),[busy,setBusy]=useState(false),[consent,setConsent]=useState(false),[supported,setSupported]=useState(false),[active,setActive]=useState(false),[denied,setDenied]=useState(false);
 const client=useRef<WebPushClient|null>(null),mounted=useRef(false),generation=useRef(0),revoked=useRef(false),pending=useRef(new Set<AbortController>());
 const current=(revision:number)=>mounted.current&&generation.current===revision&&!revoked.current;
 const aborted=(e:unknown)=>e instanceof Error&&e.name==='AbortError';
 function cancelPending(){for(const controller of pending.current)controller.abort();pending.current.clear();}
 function revoke(){generation.current++;revoked.current=true;client.current?.stop();client.current=null;cancelPending();if(mounted.current){setFeed(undefined);setConsent(false);setActive(false);setBusy(false);setMessage('');setDenied(true);setError('Tu sesión o tus permisos cambiaron. Inicia sesión de nuevo para continuar.');}}
 async function refresh(){
  const revision=generation.current;if(!current(revision))throw new DOMException('Consulta cancelada.','AbortError');
  const controller=new AbortController();pending.current.add(controller);
  try{
   const r=await fetch('/api/notices',{cache:'no-store',signal:controller.signal});
   if(!current(revision))throw new DOMException('Consulta cancelada.','AbortError');
   if(r.status===401||r.status===403){revoke();throw new DOMException('Acceso retirado.','AbortError');}
   const data=await r.json() as Feed&{error?:string};if(!r.ok)throw new Error(data.error||'No se pudo consultar la configuración.');
   if(!current(revision))throw new DOMException('Consulta cancelada.','AbortError');setFeed(data);return data;
  }finally{pending.current.delete(controller);}
 }
 // The push client intentionally exposes no server status. If a registration
 // fails, recheck our own access before keeping a previously opened consent UI.
 async function report(e:unknown,revision:number,fallback:string,checkAccess=false){if(!current(revision)||aborted(e))return;if(checkAccess){try{await refresh();}catch{/* A temporary failure keeps the last settings; revocation clears them. */}}if(current(revision))setError(e instanceof Error?e.message:fallback);}
 useEffect(()=>{mounted.current=true;generation.current++;revoked.current=false;setDenied(false);setFeed(undefined);setConsent(false);setActive(false);setBusy(false);setError('');setMessage('');if(!enabled)return()=>{mounted.current=false;generation.current++;cancelPending();};
  const supported=browserPushSupported();setSupported(supported);let binding=false,cancelled=false;
  const instance=supported?browserPushClient(userID):null;client.current=instance;
  async function prepare(){if(binding||revoked.current||document.visibilityState==='hidden')return;const revision=generation.current;binding=true;let bindingDevice=false;try{const data=await refresh();if(cancelled||!current(revision)||!instance||!data.settings.webPublicKey)return;
   if(!instance.disabled&&Notification.permission==='granted'){bindingDevice=true;const registered=await instance.bind(data.settings.webPublicKey);if(!cancelled&&current(revision))setActive(registered);}
   else if(!instance.disabled&&Notification.permission==='default'&&!sessionStorage.getItem('jac.push.dismissed.'+userID))setConsent(true);
  }catch(e){await report(e,revision,'No se pudo preparar los avisos.',bindingDevice);}finally{binding=false;}}
  void prepare();document.addEventListener('visibilitychange',prepare);window.addEventListener('online',prepare);
  return()=>{cancelled=true;mounted.current=false;generation.current++;cancelPending();instance?.stop();if(client.current===instance)client.current=null;document.removeEventListener('visibilitychange',prepare);window.removeEventListener('online',prepare);};
 },[userID,enabled]);
 function dismiss(){sessionStorage.setItem('jac.push.dismissed.'+userID,'1');setConsent(false);}
 async function enable(){if(!client.current||!feed?.settings.webPublicKey||busy||revoked.current)return;const revision=generation.current,instance=client.current;setBusy(true);setError('');try{
  const success=await instance.enable(feed.settings.webPublicKey);if(!current(revision))return;setActive(success);dismiss();setMessage(success?'Notificaciones activadas en este navegador.':'Puedes permitir las notificaciones de JAC desde los ajustes del navegador.');
 }catch(e){await report(e,revision,'No se pudieron activar los avisos.',true);}finally{if(current(revision))setBusy(false);}}
 async function disable(){if(!client.current||busy||revoked.current)return;const revision=generation.current,instance=client.current;setBusy(true);setError('');setActive(false);dismiss();try{await instance.disable();if(current(revision))setMessage('Notificaciones desactivadas en este navegador.');}catch(e){await report(e,revision,'No se pudieron desactivar los avisos.',true);}finally{if(current(revision))setBusy(false);}}
 return <>
 {view==='notificaciones'&&<section className="panel notices-panel"><div className="panel-title"><h2><Bell size={20}/> Notificaciones</h2></div>
  <p>Recibe los itinerarios nuevos y las alertas dirigidas a ti. Las alertas muestran su título y mensaje.</p>
  {error&&<p className="message error" role="alert">{error}</p>}{message&&<p className="message success" role="status">{message}</p>}
  {!enabled?<p>Activa primero tu acceso propio para recibir notificaciones.</p>:denied?null:!supported?<p>Este navegador no admite estos avisos. En iPhone puedes utilizar la app JAC o añadir el webapp a la pantalla de inicio.</p>:<>
   <p className="muted">{active?'Activadas en este navegador.':client.current?.disabled?'Desactivadas en este navegador.':Notification.permission==='denied'?'Permiso bloqueado en el navegador. Cámbialo en los ajustes del sitio.':'Pendientes de autorización o registro.'}</p>
   {!feed?.settings.webPublicKey&&<p className="muted">Los avisos del navegador están pendientes de preparación por Camilo.</p>}
   <div className="notice-actions"><Button className="primary" disabled={busy||!feed?.settings.webPublicKey||active} onClick={()=>void enable()}>Permitir notificaciones</Button><Button variant="outline" disabled={busy} onClick={()=>void disable()}>Desactivar en este navegador</Button></div>
  </>}
 </section>}
 {view==='conexiones'&&owner&&<section className="panel notices-panel"><div className="panel-title"><h2>Servicios conectados</h2></div><p className="muted">Configuración exclusiva de Camilo. Las claves se guardan cifradas.</p>{error&&<p className="message error" role="alert">{error}</p>}{!enabled?<p>Activa tu acceso propio para configurar estos servicios.</p>:denied?null:feed?<><NoticeSettings settings={feed.settings} failures={feed.failures} onBusy={setBusy} onSaved={async()=>{await refresh();}}/><BoardingChannelSettings feed={feed} onSaved={async()=>{await refresh();}}/></>:<p>Consultando…</p>}</section>}
 <Dialog open={consent} onOpenChange={open=>{if(!open&&!busy)dismiss();}}><DialogContent className="payroll-dialog" showCloseButton={!busy} onInteractOutside={e=>{if(busy)e.preventDefault();}}><DialogTitle>Recibe tus avisos de JAC</DialogTitle><DialogDescription>Te avisaremos cuando llegue un itinerario o una alerta para ti. Confirma el permiso que mostrará tu navegador. Puedes desactivar los avisos en Configuración general → Notificaciones.</DialogDescription>{error&&<p className="message error" role="alert">{error}</p>}<div className="notice-actions"><Button className="primary" disabled={busy} onClick={()=>void enable()}>Permitir notificaciones</Button><Button variant="outline" disabled={busy} onClick={dismiss}>Ahora no</Button></div></DialogContent></Dialog>
 </>;
}
