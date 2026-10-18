// Only photos explicitly selected by the user are persisted. IndexedDB holds
// ciphertext and a non-extractable, session-scoped CryptoKey; never cookies,
// login tokens, Google/R2 credentials or private HTML/API responses.
const DB='jac-media-offline-v1',ACTIVE='jac.media.offline.scope.v1',MAX=64*1024*1024,TOTAL=512*1024*1024;
let epoch=0,dbPromise;
const encoder=new TextEncoder(),decoder=new TextDecoder();
function database(){return dbPromise??=new Promise((resolve,reject)=>{const request=indexedDB.open(DB,1);request.onupgradeneeded=()=>{request.result.createObjectStore('vault');request.result.createObjectStore('photos',{keyPath:'id'});request.result.createObjectStore('bytes',{keyPath:'id'});};request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});}
async function transaction(stores,mode,run){const db=await database();return new Promise((resolve,reject)=>{const tx=db.transaction(stores,mode);let value;tx.oncomplete=()=>resolve(value);tx.onerror=tx.onabort=()=>reject(tx.error||new Error('No se pudo guardar la copia sin conexión.'));run(tx,v=>{value=v;});});}
async function snapshot(){return transaction(['vault','photos'],'readonly',(tx,set)=>{let vault,photos;const finish=()=>{if(photos!==undefined&&vault!==undefined)set({vault:vault||null,photos});};const v=tx.objectStore('vault').get('active');v.onsuccess=()=>{vault=v.result||null;finish();};const p=tx.objectStore('photos').getAll();p.onsuccess=()=>{photos=p.result;finish();};});}
function current(vault,version){return epoch===version&&!!vault&&localStorage.getItem(ACTIVE)===vault.scope;}
const aad=(scope,id,kind)=>encoder.encode(JSON.stringify([DB,scope,id,kind]));
async function seal(key,scope,id,kind,bytes){const iv=crypto.getRandomValues(new Uint8Array(12));return {iv,cipher:await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:aad(scope,id,kind)},key,bytes)};}
async function unseal(vault,id,kind,box){return crypto.subtle.decrypt({name:'AES-GCM',iv:box.iv,additionalData:aad(vault.scope,id,kind)},vault.key,box.cipher);}
function notify(){if(typeof window!=='undefined')window.dispatchEvent(new Event('jac-media-offline-changed'));}
export async function clearMediaOffline(){epoch++;try{localStorage.removeItem(ACTIVE);}catch{}notify();await transaction(['vault','photos','bytes'],'readwrite',tx=>{tx.objectStore('vault').clear();tx.objectStore('photos').clear();tx.objectStore('bytes').clear();});}
export async function connectMediaOffline(collection){
 const version=epoch,response=await fetch('/api/media/offline',{credentials:'same-origin',cache:'no-store'});
 if([401,403].includes(response.status)){await clearMediaOffline();throw new Error('Tu sesión cambió o ya no tienes acceso a Fotografía.');}
 if(!response.ok)throw new Error('No se pudo validar la copia sin conexión.');
 const context=await response.json();if(!/^[A-Za-z0-9_-]{43}$/.test(context.scope)||!/^[A-Za-z0-9_-]{43}$/.test(context.key))throw new Error('No se pudo validar la copia sin conexión.');
 const before=await snapshot();if(epoch!==version)throw new DOMException('Cancelled','AbortError');
 if(before.vault?.scope===context.scope&&(!collection||before.vault.collection===collection)&&localStorage.getItem(ACTIVE)===context.scope)return;
 const key=await crypto.subtle.importKey('raw',Uint8Array.from(atob(context.key.replace(/-/g,'+').replace(/_/g,'/')+'='),c=>c.charCodeAt(0)),'AES-GCM',false,['encrypt','decrypt']);
 if(epoch!==version)throw new DOMException('Cancelled','AbortError');
 localStorage.setItem(ACTIVE,context.scope);
 await transaction(['vault','photos','bytes'],'readwrite',tx=>{if(epoch!==version){tx.abort();return;}tx.objectStore('photos').clear();tx.objectStore('bytes').clear();tx.objectStore('vault').put({scope:context.scope,key,collection:collection||before.vault?.collection||'',deleted:[]},'active');});notify();
}
export async function fetchMediaPhoto(item,signal){
 const response=await fetch('/api/media/file?'+new URLSearchParams({id:item.id,revision:item.modifiedAt}),{credentials:'same-origin',cache:'no-store',signal});
 if([401,403].includes(response.status)){await clearMediaOffline();throw Object.assign(new Error('Tu cuenta ya no tiene acceso a esta foto.'),{status:response.status});}
 if([404,410].includes(response.status)){await removeMediaOffline([item.id]);throw Object.assign(new Error('Esta foto se eliminó de Fotografía.'),{status:response.status});}
 if(!response.ok||response.headers.get('content-type')?.split(';')[0]!==item.mimeType){await response.body?.cancel();throw new Error('La foto cambió o no está disponible. Actualiza la carpeta.');}
 const reader=response.body?.getReader();if(!reader)throw new Error('La foto no tiene contenido.');const parts=[];let size=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>item.size||size>MAX){await reader.cancel();throw new Error('Esta foto supera el límite de 64 MB de la copia del navegador. Puedes descargar el original.');}parts.push(value);}}finally{reader.releaseLock();}
 if(size!==item.size)throw new Error('La foto llegó incompleta. Intenta de nuevo.');return new Blob(parts,{type:item.mimeType});
}
export async function saveMediaPhoto(item,blob,breadcrumbs,collection){
 if(item.kind!=='image'||item.size!==blob.size||blob.size>MAX||blob.type!==item.mimeType)throw new Error('La foto no es válida para guardar sin conexión.');
 const version=epoch,{vault}=await snapshot();if(!current(vault,version)||vault.collection!==collection||(vault.deleted||[]).includes(item.id))throw new Error('La galería cambió. Actualiza Fotografía.');
 const data=await seal(vault.key,vault.scope,item.id,'photo',await blob.arrayBuffer()),meta=await seal(vault.key,vault.scope,item.id,'metadata',encoder.encode(JSON.stringify({item,breadcrumbs})));
 if(!current(vault,version))throw new DOMException('Cancelled','AbortError');
 await transaction(['vault','photos','bytes'],'readwrite',(tx)=>{const request=tx.objectStore('vault').get('active');request.onsuccess=()=>{const latest=request.result;if(!current(latest,version)||latest.scope!==vault.scope||latest.collection!==collection||(latest.deleted||[]).includes(item.id)){tx.abort();return;}const all=tx.objectStore('photos').getAll();all.onsuccess=()=>{if(all.result.filter(p=>p.id!==item.id).reduce((n,p)=>n+p.size,0)+blob.size>TOTAL){tx.abort();return;}tx.objectStore('photos').put({id:item.id,scope:vault.scope,size:blob.size,meta});tx.objectStore('bytes').put({id:item.id,data});};};});notify();
}
export async function listMediaOffline(){
 const version=epoch,{vault,photos}=await snapshot();if(!current(vault,version))return [];
 const result=[];for(const record of photos){if(record.scope!==vault.scope||(vault.deleted||[]).includes(record.id))continue;try{const meta=JSON.parse(decoder.decode(await unseal(vault,record.id,'metadata',record.meta)));if(meta.item.id===record.id&&meta.item.kind==='image')result.push(meta);}catch{/* Corrupt ciphertext never yields a photo. */}}
 return current(vault,version)?result:[];
}
export async function readMediaPhoto(id){
 const version=epoch,{vault,photos}=await snapshot(),record=photos.find(p=>p.id===id);if(!current(vault,version)||!record||record.scope!==vault.scope||(vault.deleted||[]).includes(id))return null;
 const stored=await transaction(['bytes'],'readonly',(tx,set)=>{const request=tx.objectStore('bytes').get(id);request.onsuccess=()=>set(request.result);});if(!stored)return null;
 const {item}=JSON.parse(decoder.decode(await unseal(vault,id,'metadata',record.meta))),data=await unseal(vault,id,'photo',stored.data);
 if(!current(vault,version)||data.byteLength!==item.size)return null;return {item,blob:new Blob([data],{type:item.mimeType})};
}
export async function removeMediaOffline(ids){
 if(!ids.length)return;epoch++;
 await transaction(['vault','photos','bytes'],'readwrite',tx=>{const request=tx.objectStore('vault').get('active');request.onsuccess=()=>{const vault=request.result;if(vault){vault.deleted=[...new Set([...(vault.deleted||[]),...ids])];tx.objectStore('vault').put(vault,'active');}for(const id of ids){tx.objectStore('photos').delete(id);tx.objectStore('bytes').delete(id);}};});notify();
}
export async function reconcileMediaOffline(feed){
 const photos=await listMediaOffline(),removed=new Set(feed.deletedFiles||[]),folders=new Set(feed.deletedFolders||[]);
 for(const saved of photos)if(saved.breadcrumbs.some(f=>folders.has(f.id)))removed.add(saved.item.id);
 await removeMediaOffline([...removed]);
}
if(typeof window!=='undefined')window.addEventListener('storage',event=>{if(event.key===ACTIVE||event.key===null){epoch++;notify();}});

// The public offline shell contains no identity or private server-rendered data.
if(typeof document!=='undefined'&&document.documentElement.hasAttribute('data-jac-media-offline')){
 const gallery=document.getElementById('photos'),status=document.getElementById('status'),urls=new Set();let generation=0;
 function clear(){generation++;for(const url of urls)URL.revokeObjectURL(url);urls.clear();gallery.replaceChildren();}
 async function render(){clear();const version=generation;const photos=await listMediaOffline();if(version!==generation)return;
  for(const {item} of photos){const saved=await readMediaPhoto(item.id);if(!saved||version!==generation)return;const url=URL.createObjectURL(saved.blob);urls.add(url);const card=document.createElement('article'),image=document.createElement('img'),name=document.createElement('p'),link=document.createElement('a');image.src=url;image.alt=item.name;image.loading='lazy';name.textContent=item.name;link.href=url;link.download=item.name;link.textContent='Descargar foto';card.append(image,name,link);gallery.append(card);}
  if(!photos.length)status.textContent='No hay fotos guardadas sin conexión en este navegador.';
 }
 async function refresh(){clear();status.textContent='Comprobando acceso…';try{
   await connectMediaOffline();
   for(const {item} of await listMediaOffline()){
    const r=await fetch('/api/media/file?'+new URLSearchParams({id:item.id,metadata:'1'}),{credentials:'same-origin',cache:'no-store'});
    if([401,403].includes(r.status)){await clearMediaOffline();throw new Error('Inicia sesión de nuevo para consultar Fotografía.');}
    if([404,410].includes(r.status)){await removeMediaOffline([item.id]);continue;}
    if(!r.ok)throw new Error('No se pudo comprobar esta foto. Intenta de nuevo.');const fresh=(await r.json()).item;if(fresh.id!==item.id||fresh.modifiedAt!==item.modifiedAt||fresh.size!==item.size||fresh.mimeType!==item.mimeType)await removeMediaOffline([item.id]);
   }
   status.textContent='Fotos guardadas en este navegador.';await render();
  }catch(error){if(error instanceof TypeError){status.textContent='Sin conexión · Últimas fotos guardadas en este navegador.';await render();}else status.textContent=error.message;}
 }
 window.addEventListener('online',refresh);window.addEventListener('pageshow',refresh);window.addEventListener('storage',clear);document.getElementById('refresh').onclick=refresh;
 document.getElementById('clear').onclick=async()=>{if(confirm('¿Quitar las fotos sin conexión de este navegador? Los originales se conservan.')){await clearMediaOffline();await render();}};
}
