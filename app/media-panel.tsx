'use client';

import {useCallback,useEffect,useRef,useState,type DragEvent} from 'react';
import {Camera,Check,ChevronRight,Cloud,Download,Folder,FolderPlus,Image as ImageIcon,LoaderCircle,RefreshCw,Upload,Video,X} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {Input} from '@/components/ui/input';
import {Dialog,DialogContent,DialogDescription,DialogTitle} from '@/components/ui/dialog';
import './media.css';

type MediaItem={id:string;name:string;mimeType:string;kind:'folder'|'image'|'video';size:number;modifiedAt:string;thumbnailAvailable:boolean};
type MediaFolder={id:string;name:string};
type MediaFeed={connected:boolean;canRead:boolean;canUpload:boolean;canConnect:boolean;root:MediaFolder;folder:MediaFolder;breadcrumbs:MediaFolder[];items:MediaItem[];nextPageToken?:string};
type UploadState={id:string;offset:number;chunkSize:number;complete:boolean};
type PendingUpload={id:string;parentId:string;folderName:string;file:File;mimeType:string;state:'waiting'|'uploading'|'done'|'error';offset:number;error:string};
class MediaFailure extends Error {constructor(message:string,readonly status=0){super(message);}}
const CHUNK=1024*1024,MAX_FILE=20*1024*1024*1024;
const FILE_TYPES:Record<string,string>={jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',gif:'image/gif',webp:'image/webp',heic:'image/heic',heif:'image/heif',tif:'image/tiff',tiff:'image/tiff',mp4:'video/mp4',mov:'video/quicktime',webm:'video/webm',m4v:'video/x-m4v'};
const ACCEPT=Object.keys(FILE_TYPES).map(x=>'.'+x).join(',');
const fileURL=(id:string,thumbnail=false)=>'/api/media/file?id='+encodeURIComponent(id)+(thumbnail?'&thumbnail=1':'');
const message=(e:unknown)=>e instanceof Error?e.message:'No pudimos completar la operación. Reintenta cuando tengas conexión.';
const bytes=(value:number)=>{if(value<1024)return value+' B';if(value<1024*1024)return (value/1024).toFixed(0)+' KB';if(value<1024**3)return (value/1024**2).toFixed(1)+' MB';return (value/1024**3).toFixed(2)+' GB';};
const fileDate=(value:string)=>{const date=new Date(value);return Number.isNaN(date.getTime())?'':new Intl.DateTimeFormat('es-CO',{dateStyle:'medium',timeZone:'America/Bogota'}).format(date);};
const today=()=>new Intl.DateTimeFormat('en-CA',{year:'numeric',month:'2-digit',day:'2-digit',timeZone:'America/Bogota'}).format(new Date());

export default function MediaPanel(){
 const [feed,setFeed]=useState<MediaFeed|null>(null),[folder,setFolder]=useState(''),[loading,setLoading]=useState(true),[error,setError]=useState(''),[notice,setNotice]=useState(''),[search,setSearch]=useState(''),[dragging,setDragging]=useState(false),[preview,setPreview]=useState<MediaItem|null>(null),[previewThumbnail,setPreviewThumbnail]=useState(false),[previewError,setPreviewError]=useState(''),[creating,setCreating]=useState(false),[folderName,setFolderName]=useState(''),[folderDate,setFolderDate]=useState(today),[folderError,setFolderError]=useState(''),[saving,setSaving]=useState(false),[connecting,setConnecting]=useState(false),[uploads,setUploads]=useState<PendingUpload[]>([]);
 const mounted=useRef(false),authorized=useRef(false),uploadAllowed=useRef(false),currentFolder=useRef(''),loadedPages=useRef(1),readGeneration=useRef(0),readController=useRef<AbortController|null>(null),uploadController=useRef<AbortController|null>(null),queue=useRef<PendingUpload[]>([]),working=useRef(false),fileInput=useRef<HTMLInputElement>(null),createAttempt=useRef<{id:string;parentId:string;name:string;date:string}|null>(null),dragDepth=useRef(0);
 currentFolder.current=folder;
 const revoke=useCallback(()=>{authorized.current=false;uploadAllowed.current=false;readGeneration.current++;uploadController.current?.abort();queue.current=[];if(mounted.current){setFeed(null);setPreview(null);setCreating(false);setUploads([]);setLoading(false);setError('Tu cuenta ya no tiene acceso a la galería.');}},[]);
 const request=useCallback(async<T,>(path:string,init:RequestInit={},signal?:AbortSignal):Promise<T>=>{
  const response=await fetch(path,{...init,cache:'no-store',credentials:'same-origin',signal});
  if(response.status===401||response.status===403){revoke();if(response.status===401)location.assign('/acceso?returnTo=%2Ffotografia');throw new MediaFailure('Tu sesión cambió o ya no tienes acceso a la galería.',response.status);}
  let data:T&{error?:string};try{data=await response.json();}catch{throw new MediaFailure('La galería no pudo responder. Conservamos los archivos pendientes para reintentar.',response.status);}
  if(!response.ok)throw new MediaFailure(data.error||'No pudimos completar la operación. Reintenta.',response.status);
  return data;
 },[revoke]);
 const post=useCallback(<T,>(path:string,body:unknown,signal?:AbortSignal)=>request<T>(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)},signal),[request]);
 const refresh=useCallback(async(target=currentFolder.current,pages=loadedPages.current,quiet=false)=>{
  readController.current?.abort();const controller=new AbortController();readController.current=controller;const generation=++readGeneration.current;
  if(!quiet&&mounted.current)setLoading(true);
  try{
   let result:MediaFeed|null=null,items:MediaItem[]=[],token='';
   for(let page=0;page<pages;page++){
    const query=new URLSearchParams();if(target)query.set('folder',target);if(token)query.set('pageToken',token);
    result=await request<MediaFeed>('/api/media'+(query.size?'?'+query.toString():''),{},controller.signal);
    if(!result.canRead){revoke();return;}
    items.push(...result.items);token=result.nextPageToken||'';if(!token)break;
   }
   if(!mounted.current||generation!==readGeneration.current||target!==currentFolder.current||!result)return;
   authorized.current=result.canRead;uploadAllowed.current=result.canUpload&&result.connected;
   if(!result.connected){setPreview(null);uploadAllowed.current=false;}
   setFeed({...result,items:items.filter((item,index,all)=>all.findIndex(x=>x.id===item.id)===index)});setError('');
  }catch(e){if(controller.signal.aborted)return;if(mounted.current&&generation===readGeneration.current)setError(message(e));}
  finally{if(mounted.current&&generation===readGeneration.current)setLoading(false);}
 },[request,revoke]);
 useEffect(()=>{
  mounted.current=true;void refresh(folder,1);
  const foreground=()=>{if(document.visibilityState==='visible')void refresh();},timer=setInterval(foreground,30000);
  window.addEventListener('focus',foreground);window.addEventListener('online',foreground);document.addEventListener('visibilitychange',foreground);
  return()=>{mounted.current=false;readController.current?.abort();readGeneration.current++;clearInterval(timer);window.removeEventListener('focus',foreground);window.removeEventListener('online',foreground);document.removeEventListener('visibilitychange',foreground);};
 },[folder,refresh]);
 useEffect(()=>()=>{authorized.current=false;uploadAllowed.current=false;uploadController.current?.abort();queue.current=[];},[]);
 function navigate(next:string){if(next===folder)return;currentFolder.current=next;loadedPages.current=1;setFolder(next);setFeed(null);setSearch('');setPreview(null);setError('');setLoading(true);}
 function updateUpload(id:string,update:Partial<PendingUpload>){queue.current=queue.current.map(item=>item.id===id?{...item,...update}:item);if(mounted.current)setUploads([...queue.current]);}
 async function uploadRequest<T>(path:string,init:RequestInit):Promise<T>{const controller=new AbortController();uploadController.current=controller;const timer=setTimeout(()=>controller.abort(),90000);try{return await request<T>(path,init,controller.signal);}finally{clearTimeout(timer);if(uploadController.current===controller)uploadController.current=null;}}
 const uploadPost=<T,>(body:unknown)=>uploadRequest<T>('/api/media/upload',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 function validateProgress(state:UploadState,item:PendingUpload){if(state.id!==item.id||!Number.isSafeInteger(state.offset)||state.offset<0||state.offset>item.file.size||state.chunkSize!==CHUNK||(state.complete&&state.offset!==item.file.size))throw new Error('No se pudo confirmar el avance del archivo. Reintenta para consultar su estado.');return state;}
 async function reconcile(item:PendingUpload,error:unknown):Promise<UploadState>{if(!mounted.current||!uploadAllowed.current||error instanceof MediaFailure&&[400,401,403,404,410,413,415,422].includes(error.status))throw error;return validateProgress(await uploadPost<UploadState>({action:'status',id:item.id}),item);}
 async function processQueue(){
  if(working.current)return;working.current=true;
  try{while(mounted.current&&uploadAllowed.current){const item=queue.current.find(x=>x.state==='waiting');if(!item)break;updateUpload(item.id,{state:'uploading',error:''});
   try{
    let state:UploadState;try{state=validateProgress(await uploadPost<UploadState>({action:'start',id:item.id,parentId:item.parentId,filename:item.file.name,mimeType:item.mimeType,size:item.file.size}),item);}catch(e){state=await reconcile(item,e);}
    updateUpload(item.id,{offset:state.offset});
    while(!state.complete){if(!mounted.current||!uploadAllowed.current)throw new Error('La subida se ha detenido.');const offset=state.offset,chunk=item.file.slice(offset,Math.min(offset+CHUNK,item.file.size));
     try{state=validateProgress(await uploadRequest<UploadState>('/api/media/upload?id='+encodeURIComponent(item.id)+'&offset='+offset,{method:'PUT',headers:{'Content-Type':'application/octet-stream'},body:chunk}),item);}catch(e){state=await reconcile(item,e);}
     if(state.offset<=offset&&!state.complete)throw new Error('La conexión se interrumpió. Pulsa Reintentar para continuar desde el último tramo confirmado.');
     updateUpload(item.id,{offset:state.offset});
    }
    updateUpload(item.id,{state:'done',offset:item.file.size});if(mounted.current)void refresh(currentFolder.current,loadedPages.current,true);
   }catch(e){if(mounted.current&&authorized.current)updateUpload(item.id,{state:'error',error:message(e)});}
  }}finally{working.current=false;}
 }
 function addFiles(files:File[]){
  if(!feed?.connected||!uploadAllowed.current)return;setError('');const added:PendingUpload[]=[],rejected:string[]=[];
  for(const file of files){const ext=file.name.split('.').pop()?.toLowerCase()||'',mimeType=FILE_TYPES[ext];if(!mimeType){rejected.push(file.name+': formato no compatible.');continue;}if(!file.size||file.size>MAX_FILE){rejected.push(file.name+': el tamaño debe ser mayor que cero y hasta 20 GB.');continue;}added.push({id:crypto.randomUUID(),parentId:feed.folder.id,folderName:feed.folder.name,file,mimeType,state:'waiting',offset:0,error:''});}
  queue.current=[...queue.current,...added];setUploads([...queue.current]);if(rejected.length)setError(rejected.join(' '));if(added.length)void processQueue();
 }
 function dropped(event:DragEvent){event.preventDefault();dragDepth.current=0;setDragging(false);if(uploadAllowed.current)addFiles(Array.from(event.dataTransfer.files));}
 async function createFolder(){if(saving||!feed?.canUpload||!uploadAllowed.current)return;const name=folderName.trim();if(!name||!folderDate)return;setSaving(true);setFolderError('');
  if(!createAttempt.current)createAttempt.current={id:crypto.randomUUID(),parentId:feed.folder.id,name,date:folderDate};
  try{const result=await post<{folder:MediaFolder}>('/api/media',{action:'createFolder',...createAttempt.current});if(mounted.current){setCreating(false);createAttempt.current=null;navigate(result.folder.id);setNotice('Carpeta creada. Ya puedes guardar aquí las fotos y videos.');}}catch(e){if(e instanceof MediaFailure&&e.status===400)createAttempt.current=null;if(mounted.current&&authorized.current)setFolderError(message(e));}finally{if(mounted.current)setSaving(false);}
 }
 async function connect(){setConnecting(true);setError('');try{const result=await post<{url:string}>('/api/media',{action:'connect'}),url=new URL(result.url);if(url.protocol!=='https:'||url.hostname!=='accounts.google.com')throw new Error('No se pudo verificar la autorización de Google.');location.assign(url.href);}catch(e){setError(message(e));setConnecting(false);}}
 const items=(feed?.items||[]).filter(item=>item.name.toLocaleLowerCase('es').includes(search.toLocaleLowerCase('es'))),folders=items.filter(x=>x.kind==='folder'),files=items.filter(x=>x.kind!=='folder'),activeUploads=uploads.filter(x=>x.state!=='done').length;
 return <section className="media-gallery" aria-label="Galería de fotografía">
  <header className="media-hero"><span className="media-hero-icon"><Camera size={29}/></span><div><p>MEMORIAS JAC MUSIC</p><h2>Fotografía y video</h2><span>Cada show, cada día y cada historia, en un solo lugar.</span></div><span className="media-cloud"><Cloud size={16}/>{feed?.connected?'Conectado a Drive':'Archivo del equipo'}</span></header>
  {error&&<p className="message error media-feedback" role="alert">{error}</p>}{notice&&<p className="message success media-feedback" role="status">{notice}<button aria-label="Cerrar mensaje" onClick={()=>setNotice('')}><X size={16}/></button></p>}
  {!feed&&loading?<div className="media-empty" role="status"><LoaderCircle className="media-spin"/><h3>Abriendo la galería…</h3></div>:!feed?<div className="media-empty"><Camera/><h3>No pudimos abrir la galería</h3><p>Comprueba tu conexión o los permisos de tu cuenta.</p><Button variant="outline" onClick={()=>void refresh()}>Reintentar</Button></div>:!feed.connected?<div className="media-empty media-connect"><Cloud/><h3>Preparando el archivo de JAC</h3><p>{feed.canConnect?'Conecta la cuenta de Google que tiene acceso a la carpeta compartida para ver las fotos y los videos aquí mismo.':'Camilo debe conectar la carpeta compartida de Google Drive. En cuanto esté lista, podrás consultar aquí las fotos y los videos.'}</p>{feed.canConnect&&<Button className="primary" disabled={connecting} onClick={()=>void connect()}>{connecting?<LoaderCircle className="media-spin"/>:<Cloud/>}{connecting?'Abriendo Google…':'Conectar Google Drive'}</Button>}</div>:<>
   <div className="media-toolbar"><nav className="media-breadcrumb" aria-label="Carpetas de fotografía">{(feed.breadcrumbs.length?feed.breadcrumbs:[feed.root]).map((part,index,all)=><span key={part.id}>{index>0&&<ChevronRight size={15}/>}<button aria-current={index===all.length-1?'page':undefined} onClick={()=>navigate(part.id===feed.root.id?'':part.id)}>{index===0&&<Folder size={16}/>}<span>{index===0?'Archivo JAC':part.name}</span></button></span>)}</nav><div className="media-toolbar-actions"><Button variant="outline" size="icon" aria-label="Actualizar galería" title="Actualizar galería" disabled={loading} onClick={()=>void refresh()}><RefreshCw size={17} className={loading?'media-spin':''}/></Button>{feed.canUpload&&<><Button variant="outline" onClick={()=>{createAttempt.current=null;setFolderName('');setFolderDate(today());setFolderError('');setCreating(true);}}><FolderPlus size={17}/>Nueva carpeta</Button><Button className="primary" onClick={()=>fileInput.current?.click()}><Upload size={17}/>Subir archivos</Button></>}</div></div>
   <div className="media-search-row"><div><h3>{feed.folder.id===feed.root.id?'Archivo de shows':feed.folder.name}</h3><span>{feed.items.length} {feed.items.length===1?'elemento':'elementos'}{feed.canUpload?' · Organiza por show o día de trabajo':''}</span></div><Input aria-label="Buscar en esta carpeta" value={search} onChange={event=>setSearch(event.target.value)} placeholder="Buscar en esta carpeta"/></div>
   <input ref={fileInput} className="media-file-input" type="file" accept={ACCEPT} multiple aria-label="Seleccionar fotos y videos" onChange={event=>{addFiles(Array.from(event.target.files||[]));event.target.value='';}}/>
   {feed.canUpload&&<div className={'media-dropzone'+(dragging?' dragging':'')} onDragEnter={event=>{event.preventDefault();dragDepth.current++;setDragging(true);}} onDragOver={event=>{event.preventDefault();event.dataTransfer.dropEffect='copy';}} onDragLeave={event=>{event.preventDefault();dragDepth.current--;if(dragDepth.current<=0)setDragging(false);}} onDrop={dropped}><span className="media-drop-icon"><Upload size={22}/></span><div><strong>{dragging?'Suelta los archivos aquí':'Arrastra aquí tus fotos y videos'}</strong><p>Se guardan en esta carpeta de Drive. También puedes <button onClick={()=>fileInput.current?.click()}>seleccionarlos en tu equipo</button>.</p></div><span className="media-drop-hint">Fotos y video · Hasta 20 GB por archivo</span></div>}
   {!!uploads.length&&<section className="media-uploads" aria-label="Estado de las subidas"><div className="media-upload-heading"><h3>{activeUploads?'Subiendo al archivo':'Archivos guardados'}</h3><span role="status">{uploads.filter(x=>x.state==='done').length} de {uploads.length} completados</span><Button variant="ghost" disabled={!uploads.some(x=>x.state==='done')} onClick={()=>{queue.current=queue.current.filter(x=>x.state!=='done');setUploads([...queue.current]);}}>Ocultar completados</Button></div>{uploads.map(item=><div className={'media-upload-row '+item.state} key={item.id}><span className="media-upload-symbol">{item.state==='done'?<Check size={20}/>:item.state==='uploading'?<LoaderCircle size={20} className="media-spin"/>:<Upload size={20}/>}</span><div><strong>{item.file.name}</strong><small>{item.folderName} · {bytes(item.offset)} de {bytes(item.file.size)}{item.state==='waiting'?' · En espera':item.state==='done'?' · Guardado':''}</small>{item.state!=='done'&&<progress max={item.file.size} value={item.offset} aria-label={'Avance de '+item.file.name}/>} {item.error&&<p role="alert">{item.error}</p>}</div>{item.state==='error'&&<Button variant="outline" onClick={()=>{updateUpload(item.id,{state:'waiting',error:''});void processQueue();}}>Reintentar</Button>}</div>)}</section>}
   {!items.length?<div className="media-empty"><ImageIcon/><h3>{search?'No hay coincidencias':'El próximo recuerdo empieza aquí'}</h3><p>{search?'Prueba otro nombre en esta carpeta.':feed.canUpload?'Crea una carpeta para el show o sube sus fotos y videos.':'Esta carpeta aún no tiene fotos ni videos.'}</p></div>:<>
    {!!folders.length&&<section className="media-section"><h4>Carpetas</h4><div className="media-folder-grid">{folders.map(item=><button key={item.id} className="media-folder-card" onClick={()=>navigate(item.id)}><span><Folder size={24}/></span><div><strong>{item.name}</strong><small>{fileDate(item.modifiedAt)}</small></div><ChevronRight size={17}/></button>)}</div></section>}
    {!!files.length&&<section className="media-section"><h4>Fotos y videos</h4><div className="media-file-grid">{files.map(item=><button key={item.id} className="media-file-card" onClick={()=>{setPreviewError('');setPreviewThumbnail(item.thumbnailAvailable&&/^image\/(heic|heif|tiff)$/.test(item.mimeType));setPreview(item);}} aria-label={'Abrir '+item.name}><span className="media-thumbnail">{item.kind==='video'?<Video className="media-thumbnail-fallback" size={40}/>:<ImageIcon className="media-thumbnail-fallback" size={40}/>} {item.thumbnailAvailable&&<img src={fileURL(item.id,true)} alt="" loading="lazy" onError={event=>{event.currentTarget.style.display='none';}}/>}{item.kind==='video'&&<span className="media-video-badge"><Video size={14}/>Video</span>}</span><span className="media-file-caption"><strong>{item.name}</strong><small>{bytes(item.size)}<span>·</span>{fileDate(item.modifiedAt)}</small></span></button>)}</div></section>}
   </>}
   {feed.nextPageToken&&<div className="media-load-more"><Button variant="outline" disabled={loading} onClick={()=>{loadedPages.current++;void refresh();}}>{loading?'Cargando…':'Ver más archivos'}</Button></div>}
  </>}
  <Dialog open={creating} onOpenChange={value=>{if(!saving){setCreating(value);if(!value)createAttempt.current=null;}}}><DialogContent className="media-folder-dialog"><DialogTitle>Nueva carpeta</DialogTitle><DialogDescription>Organiza las fotos y los videos de un show o día de trabajo.</DialogDescription><form onSubmit={event=>{event.preventDefault();void createFolder();}}><label>Nombre del show o jornada<Input autoFocus aria-label="Nombre de la carpeta" maxLength={160} required value={folderName} disabled={saving||!!createAttempt.current} placeholder="Ej. Pereira · Show principal" onChange={event=>setFolderName(event.target.value)}/></label><label>Día de trabajo<Input aria-label="Día de trabajo" type="date" required value={folderDate} disabled={saving||!!createAttempt.current} onChange={event=>setFolderDate(event.target.value)}/></label>{folderError&&<p className="message error" role="alert">{folderError}</p>}<div className="media-dialog-actions"><Button type="button" variant="outline" disabled={saving} onClick={()=>{setCreating(false);createAttempt.current=null;}}>Cancelar</Button><Button type="submit" className="primary" disabled={saving||!folderName.trim()||!folderDate}>{saving?'Creando…':createAttempt.current?'Reintentar creación':'Crear carpeta'}</Button></div></form></DialogContent></Dialog>
  <Dialog open={!!preview} onOpenChange={value=>{if(!value){setPreview(null);setPreviewError('');}}}><DialogContent className="media-preview"><DialogTitle>{preview?.name||'Vista previa'}</DialogTitle><DialogDescription>{preview?bytes(preview.size)+' · '+fileDate(preview.modifiedAt):'Fotos y videos de JAC Music'}</DialogDescription>{preview&&<><div className="media-preview-stage">{preview.kind==='video'?<video key={preview.id} controls playsInline preload="metadata" src={fileURL(preview.id)} onError={()=>{setPreviewError('Este video no se puede reproducir aquí. Puedes descargar el original para abrirlo en tu dispositivo.');void refresh(currentFolder.current,loadedPages.current,true);}}/>:<img key={preview.id+String(previewThumbnail)} src={fileURL(preview.id,previewThumbnail)} alt={preview.name} onError={()=>{if(!previewThumbnail&&preview.thumbnailAvailable){setPreviewThumbnail(true);setPreviewError('Mostrando una vista previa compatible. El archivo original está disponible para descargar.');}else setPreviewError('No pudimos mostrar esta imagen. Puedes descargar el original si tu navegador no admite su formato.');void refresh(currentFolder.current,loadedPages.current,true);}}/>}</div>{previewError&&<p className="media-preview-error" role="alert">{previewError}</p>}<div className="media-preview-footer"><span>{previewThumbnail?'Vista previa optimizada':'Archivo original'} · JAC Music</span><a href={fileURL(preview.id)} download={preview.name}><Download size={17}/>Descargar original</a></div></>}</DialogContent></Dialog>
 </section>;
}
