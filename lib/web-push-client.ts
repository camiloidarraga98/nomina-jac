// Device-local choices only. Server authorization and recipient checks remain authoritative.
export type PushEnvironment = {
 permission:()=>NotificationPermission;
 requestPermission:()=>Promise<NotificationPermission>;
 subscribe:(key:string)=>Promise<PushSubscriptionJSON>;
 unsubscribe:()=>Promise<void>;
 post:(body:unknown)=>Promise<unknown>;
 storage:Pick<Storage,'getItem'|'setItem'>;
 deviceID:()=>string;
};
export class WebPushClient {
 private queue:Promise<unknown>=Promise.resolve();
 private revision=0;
 private stopped=false;
 readonly preferenceKey:string;
 constructor(readonly userID:string,private env:PushEnvironment){this.preferenceKey='jac.push.preference.'+userID;}
 get disabled(){return this.env.storage.getItem(this.preferenceKey)==='disabled';}
 private ordered<T>(work:()=>Promise<T>):Promise<T>{const next=this.queue.catch(()=>{}).then(work);this.queue=next;return next;}
 stop(){this.stopped=true;this.revision++;}
 bind(key:string){const revision=this.revision;return this.ordered(async()=>{
  if(this.stopped||this.disabled||this.env.permission()!=='granted'||!key)return false;
  const subscription=await this.env.subscribe(key);
  if(this.stopped||revision!==this.revision||this.disabled)return false;
  await this.env.post({action:'register',id:this.env.deviceID(),platform:'web',subscription});return true;
 });}
 enable(key:string){
  // Call synchronously from the consent button, before any fetch/await loses Safari's gesture.
  const permission=this.env.permission()==='granted'?Promise.resolve('granted' as const):this.env.requestPermission();
  const revision=++this.revision;
  return permission.then(value=>{if(value!=='granted')return false;if(this.stopped||revision!==this.revision)return false;this.env.storage.setItem(this.preferenceKey,'enabled');return this.bind(key);});
 }
 disable(){this.revision++;this.env.storage.setItem(this.preferenceKey,'disabled');return this.ordered(async()=>{
  await this.env.post({action:'unregister',id:this.env.deviceID()});await this.env.unsubscribe();
 });}
}
export function browserPushSupported(){return typeof window!=='undefined'&&window.isSecureContext&&'Notification' in window&&'serviceWorker' in navigator&&'PushManager' in window;}
export function browserPushClient(userID:string){return new WebPushClient(userID,{
 permission:()=>Notification.permission,requestPermission:()=>Notification.requestPermission(),storage:localStorage,
 deviceID:()=>{let id=localStorage.getItem('jac.push.device');if(!id){id=crypto.randomUUID();localStorage.setItem('jac.push.device',id);}return id;},
 post:async body=>{const r=await fetch('/api/notices',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json() as {error?:string};if(!r.ok)throw new Error(data.error||'No se pudieron guardar las notificaciones.');},
 subscribe:async publicKey=>{const registration=await navigator.serviceWorker.register('/jac-push-sw.js',{updateViaCache:'none'});try{await registration.update();}catch{/* Existing worker remains usable offline. */}const key=Uint8Array.from(atob(publicKey.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));const subscription=await registration.pushManager.getSubscription()??await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:key});return subscription.toJSON();},
 unsubscribe:async()=>{const registration=await navigator.serviceWorker.getRegistration('/jac-push-sw.js');await (await registration?.pushManager.getSubscription())?.unsubscribe();}
});}
