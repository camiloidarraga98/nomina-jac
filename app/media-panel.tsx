'use client';

import {useCallback,useEffect,useRef,useState,type DragEvent} from 'react';
import {Camera,Check,ChevronLeft,ChevronRight,Cloud,Download,Folder,FolderPlus,Image as ImageIcon,LoaderCircle,MoreHorizontal,RefreshCw,Share,Trash2,Upload,Video,X} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {Input} from '@/components/ui/input';
import {Dialog,DialogContent,DialogDescription,DialogTitle} from '@/components/ui/dialog';
import './media.css';
import MediaFolderSharing from './media-folder-sharing';
import {prepareMediaImage,savedMediaImageLimit,saveMediaImageLimit} from '@/lib/media-image-client';
import {MEDIA_IMAGE_LIMITS,mediaImageQualityLabel,type MediaImageLimit} from '@/lib/media-image-policy';
import {mediaBrowserThumbnail} from '@/lib/media-thumbnail-client';
import {MediaUploadMeter} from '@/lib/media-upload-meter';
import {sendMediaDirectChunk,directMediaUploadURL} from '@/lib/media-upload-client';

import type {MediaItem} from '@/lib/media-core';
import {clearMediaOffline,connectMediaOffline,fetchMediaPhoto,saveMediaPhoto,listMediaOffline,removeMediaOffline,reconcileMediaOffline} from '@/public/jac-media-offline.js';
type MediaFolder={id:string;name:string};
type MediaDeletion={id:string;parentId:string;name:string;removed:number;complete?:boolean;waiting?:boolean};
type MediaFeed={canDelete?:boolean;pendingFileDeletions?:MediaDeletion[];deletedFiles?:string[];pendingDeletions?:MediaDeletion[];deletedFolders?:string[];provider?:string;collectionID?:string;connected:boolean;canRead:boolean;canUpload:boolean;canConnect:boolean;root:MediaFolder;folder:MediaFolder;breadcrumbs:MediaFolder[];items:MediaItem[];nextPageToken?:string};
type UploadState={id:string;offset:number;chunkSize:number;complete:boolean;uploadURL?:string;provider?:string;fileId?:string};
type PendingUpload={id:string;parentId:string;folderName:string;file:File;mimeType:string;state:'waiting'|'uploading'|'done'|'error';offset:number;sent?:number;phase?:string;error:string;prepared?:boolean;imageLimit:MediaImageLimit};
type FolderAttempt={id:string;parentId:string;name:string;date:string};
type Thumbnail={url?:string;state:'loading'|'ready'|'pending'|'error'};
class MediaFailure extends Error {constructor(message:string,readonly status=0){super(message);}}
const CHUNK=1024*1024,DIRECT_CHUNK=8*1024*1024,MAX_FILE=20*1024*1024*1024;
const FILE_TYPES:Record<string,string>={jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',gif:'image/gif',webp:'image/webp',heic:'image/heic',heif:'image/heif',tif:'image/tiff',tiff:'image/tiff',mp4:'video/mp4',mov:'video/quicktime',webm:'video/webm',m4v:'video/x-m4v'};
const ACCEPT=Object.keys(FILE_TYPES).map(x=>'.'+x).join(',');
const fileURL=(id:string,thumbnail=false)=>'/api/media/file?id='+encodeURIComponent(id)+(thumbnail?'&thumbnail=1':'');
const message=(e:unknown)=>e instanceof Error?e.message:'No pudimos completar la operación. Reintenta cuando tengas conexión.';
const bytes=(value:number)=>{if(value<1024)return Math.round(value)+' B';if(value<1024*1024)return (value/1024).toFixed(0)+' KB';if(value<1024**3)return (value/1024**2).toFixed(1)+' MB';return (value/1024**3).toFixed(2)+' GB';};
const fileDate=(value:string)=>{const date=new Date(value);return Number.isNaN(date.getTime())?'':new Intl.DateTimeFormat('es-CO',{dateStyle:'medium',timeZone:'America/Bogota'}).format(date);};
const today=()=>new Intl.DateTimeFormat('en-CA',{year:'numeric',month:'2-digit',day:'2-digit',timeZone:'America/Bogota'}).format(new Date());
const newestFirst=(a:MediaItem,b:MediaItem)=>(a.kind==='folder'?0:1)-(b.kind==='folder'?0:1)||(b.createdAt||'').localeCompare(a.createdAt||'')||a.name.localeCompare(b.name,'es',{numeric:true})||a.id.localeCompare(b.id);

// Private, bounded thumbnails only. Object URLs live in memory for the open
// folder and are discarded on navigation, access revocation or unmount.
function useMediaThumbnails(feed:MediaFeed|null,onRevoked:()=>void){
 const [images,setImages]=useState<Record<string,Thumbnail>>({}),[retryGeneration,setRetryGeneration]=useState(0),cache=useRef(new Map<string,{version:string;url:string}>()),failures=useRef(new Map<string,{version:string;available:boolean;state:'pending'|'error';attempt:number;retryAt:number}>()),folderID=useRef(''),generation=useRef(0);
 useEffect(()=>{
  const controller=new AbortController(),revision=++generation.current,current=()=>!controller.signal.aborted&&generation.current===revision;
  const files=feed?.connected?feed.items.filter(item=>item.kind!=='folder'):[],ids=new Set(files.map(item=>item.id)),nextFolder=feed?.connected?feed.folder.id:'';
  for(const [id,saved] of cache.current)if(nextFolder!==folderID.current||!ids.has(id)||files.find(item=>item.id===id)?.modifiedAt!==saved.version){URL.revokeObjectURL(saved.url);cache.current.delete(id);}
  for(const [id,saved] of failures.current)if(nextFolder!==folderID.current||!ids.has(id)||files.find(item=>item.id===id)?.modifiedAt!==saved.version)failures.current.delete(id);
  const due=(item:MediaItem)=>{const failure=failures.current.get(item.id);return !failure||failure.available!==item.thumbnailAvailable||Date.now()>=failure.retryAt;};
  folderID.current=nextFolder;setImages(Object.fromEntries(files.map(item=>[item.id,cache.current.has(item.id)?{state:'ready',url:cache.current.get(item.id)!.url}:!due(item)?{state:failures.current.get(item.id)!.state}:{state:'loading'}])));
  function failed(item:MediaItem,state:'pending'|'error'){const attempt=(failures.current.get(item.id)?.attempt||0)+1;failures.current.set(item.id,{version:item.modifiedAt,available:item.thumbnailAvailable,state,attempt,retryAt:Date.now()+Math.min(300000,30000*2**Math.min(attempt-1,4))});setImages(previous=>({...previous,[item.id]:{state}}));}
  const waiting=files.filter(item=>!cache.current.has(item.id)&&due(item));let at=0;
  async function worker(){while(current()&&at<waiting.length){const item=waiting[at++];try{
   const response=await fetch(fileURL(item.id,true),{credentials:'same-origin',cache:'no-store',signal:controller.signal});
   if(!current())return;
   if(response.status===401||response.status===403){controller.abort();onRevoked();if(response.status===401)location.assign('/acceso?returnTo=%2Ffotografia');return;}
   if(!response.ok){await response.body?.cancel();if(current())failed(item,response.status===404?'pending':'error');continue;}
   if(!/^image\/(jpeg|png|gif|webp)(?:;|$)/i.test(response.headers.get('content-type')||'')||Number(response.headers.get('content-length')||0)>512*1024){await response.body?.cancel();throw new Error('Vista previa inválida.');}
   const blob=await response.blob();if(!blob.size||blob.size>512*1024)throw new Error('Vista previa inválida.');if(!current())return;
   const url=URL.createObjectURL(blob);failures.current.delete(item.id);cache.current.set(item.id,{version:item.modifiedAt,url});setImages(previous=>({...previous,[item.id]:{state:'ready',url}}));
  }catch{if(current())failed(item,'error');}}}
  for(let i=0;i<Math.min(6,waiting.length);i++)void worker();
  return()=>controller.abort();
 },[feed,onRevoked,retryGeneration]);
 useEffect(()=>()=>{generation.current++;for(const saved of cache.current.values())URL.revokeObjectURL(saved.url);cache.current.clear();failures.current.clear();},[]);
 const failed=useCallback((id:string)=>{const saved=cache.current.get(id);if(saved)URL.revokeObjectURL(saved.url);cache.current.delete(id);setImages(previous=>({...previous,[id]:{state:'error'}}));},[]);
 const retry=useCallback(()=>{failures.current.clear();setRetryGeneration(previous=>previous+1);},[]);
 return {images,failed,retry};
}

export default function MediaPanel(){

 const [feed,setFeed]=useState<MediaFeed|null>(null),[folder,setFolder]=useState(''),[loading,setLoading]=useState(true),[error,setError]=useState(''),[notice,setNotice]=useState(''),[search,setSearch]=useState(''),[dragging,setDragging]=useState(false),[preview,setPreview]=useState<MediaItem|null>(null),[previewThumbnail,setPreviewThumbnail]=useState(false),[previewError,setPreviewError]=useState(''),[creating,setCreating]=useState(false),[folderName,setFolderName]=useState(''),[folderDate,setFolderDate]=useState(today),[folderError,setFolderError]=useState(''),[saving,setSaving]=useState(false),[uploads,setUploads]=useState<PendingUpload[]>([]);
 const [uploadOpen,setUploadOpen]=useState(false),[draftFiles,setDraftFiles]=useState<File[]>([]),[draftError,setDraftError]=useState(''),[destinationMode,setDestinationMode]=useState<'current'|'new'|'existing'>('current'),[eventName,setEventName]=useState(''),[eventDate,setEventDate]=useState(today),[destination,setDestination]=useState<MediaFeed|null>(null),[destinationLoading,setDestinationLoading]=useState(false),[destinationError,setDestinationError]=useState('');
 const mounted=useRef(false),authorized=useRef(false),uploadAllowed=useRef(false),currentFolder=useRef(''),loadedPages=useRef(1),readGeneration=useRef(0),readController=useRef<AbortController|null>(null),uploadControllers=useRef(new Set<AbortController>()),queue=useRef<PendingUpload[]>([]),working=useRef(false),fileInput=useRef<HTMLInputElement>(null),createAttempt=useRef<FolderAttempt|null>(null),uploadFolderAttempt=useRef<FolderAttempt|null>(null),destinationController=useRef<AbortController|null>(null),destinationGeneration=useRef(0),dragDepth=useRef(0);
 const meter=useRef(new MediaUploadMeter()),preparing=useRef<Promise<unknown>>(Promise.resolve());
 const [speed,setSpeed]=useState(0);
 useEffect(()=>{const timer=setInterval(()=>setSpeed(meter.current.rate()),500);return()=>clearInterval(timer);},[]);
 const [sharingFolder,setSharingFolder]=useState<MediaFolder|null>(null);
 const [qualityOpen,setQualityOpen]=useState(false),[imageLimit,setImageLimit]=useState<MediaImageLimit>(2_000_000);
 useEffect(()=>setImageLimit(savedMediaImageLimit()),[]);
 const [deleteFolder,setDeleteFolder]=useState<MediaFolder|null>(null),[deleteBusy,setDeleteBusy]=useState(false),[deleteError,setDeleteError]=useState('');
 const deleteController=useRef<AbortController|null>(null);
 const [deletePhoto,setDeletePhoto]=useState<MediaItem|MediaDeletion|null>(null),[photoBusy,setPhotoBusy]=useState(''),[offlineReady,setOfflineReady]=useState(false),[offlineIDs,setOfflineIDs]=useState(new Set<string>());
 const photoController=useRef<AbortController|null>(null);
 const [previewURL,setPreviewURL]=useState('');
 const [slides,setSlides]=useState<{items:MediaItem[];token:string;folder:string;collection?:string}|null>(null),[slideLoading,setSlideLoading]=useState(false);
 const slideController=useRef<AbortController|null>(null),touch=useRef<{x:number;y:number}|null>(null);
 const selectPhoto=useCallback((item:MediaItem)=>{setPreviewURL('');setPreviewError('');setPreviewThumbnail(item.thumbnailAvailable&&/^image\/(heic|heif|tiff)$/.test(item.mimeType));setPreview(item);},[]);
 const openPreview=(item:MediaItem)=>{slideController.current?.abort();setSlideLoading(false);setSlides(item.kind==='image'&&feed?{items:feed.items.filter(x=>x.kind==='image'),token:feed.nextPageToken||'',folder:feed.folder.id,collection:feed.collectionID}:null);selectPhoto(item);};

 const originalCache=useRef(new Map<string,{revision:string;size:number;mime:string;url:string}>());
 const clearOriginals=useCallback(()=>{for(const cached of originalCache.current.values())URL.revokeObjectURL(cached.url);originalCache.current.clear();setPreviewURL('');},[]);
 currentFolder.current=folder;
 const revoke=useCallback(()=>{setSharingFolder(null);void clearMediaOffline().catch(()=>{});photoController.current?.abort();setDeletePhoto(null);setOfflineReady(false);setOfflineIDs(new Set());deleteController.current?.abort();setDeleteFolder(null);clearOriginals();authorized.current=false;uploadAllowed.current=false;readGeneration.current++;for(const controller of uploadControllers.current)controller.abort();destinationController.current?.abort();destinationGeneration.current++;uploadFolderAttempt.current=null;queue.current=[];if(mounted.current){setFeed(null);setPreview(null);setCreating(false);setUploadOpen(false);setDraftFiles([]);setDestination(null);setUploads([]);setLoading(false);setError('Tu cuenta ya no tiene acceso a la galería.');}},[clearOriginals]);
 const {images:thumbnails,failed:thumbnailFailed,retry:retryThumbnails}=useMediaThumbnails(feed,revoke);
 useEffect(()=>{let active=true;const update=()=>{void listMediaOffline().then(photos=>{if(active)setOfflineIDs(new Set(photos.map(p=>p.item.id)));}).catch(()=>{});};window.addEventListener('jac-media-offline-changed',update);update();return()=>{active=false;window.removeEventListener('jac-media-offline-changed',update);};},[]);
 useEffect(()=>{if(!feed?.connected||!feed.collectionID)return;let active=true;setOfflineReady(false);void(async()=>{await connectMediaOffline(feed.collectionID);if(!('serviceWorker' in navigator))return;const registration=await navigator.serviceWorker.register('/jac-push-sw.js',{scope:'/',updateViaCache:'none'}),worker=registration.installing??registration.waiting;if(worker&&worker.state!=='activated')await new Promise<void>((resolve,reject)=>{const finish=()=>{if(worker.state==='activated'||worker.state==='redundant'){clearTimeout(timer);worker.removeEventListener('statechange',finish);worker.state==='activated'?resolve():reject(new Error('No se pudo preparar la vista sin conexión.'));}},timer=setTimeout(()=>{worker.removeEventListener('statechange',finish);reject(new Error('No se pudo preparar la vista sin conexión.'));},30000);worker.addEventListener('statechange',finish);finish();});await navigator.serviceWorker.ready;if(active)setOfflineReady(true);})().catch(()=>{});return()=>{active=false;};},[feed?.connected,feed?.collectionID]);
 const request=useCallback(async<T,>(path:string,init:RequestInit={},signal?:AbortSignal):Promise<T>=>{
  const response=await fetch(path,{...init,cache:'no-store',credentials:'same-origin',signal});
  if(response.status===401||response.status===403){revoke();if(response.status===401)location.assign('/acceso?returnTo=%2Ffotografia');throw new MediaFailure('Tu sesión cambió o ya no tienes acceso a la galería.',response.status);}
  let data:T&{error?:string};try{data=await response.json();}catch{throw new MediaFailure('La galería no pudo responder. Conservamos los archivos pendientes para reintentar.',response.status);}
  if(!response.ok)throw new MediaFailure(data.error||'No pudimos completar la operación. Reintenta.',response.status);
  return data;
 },[revoke]);
 useEffect(()=>{
  setPreviewURL('');if(!preview||preview.kind!=='image')return;
  if(previewThumbnail||preview.size>24*1024*1024){setPreviewURL(fileURL(preview.id,previewThumbnail));return;}
  const selected=preview,controller=new AbortController();
  void(async()=>{try{
   let cached=originalCache.current.get(selected.id);
   if(cached){
    const {item}=await request<{item:MediaItem}>(fileURL(selected.id)+'&metadata=1',{},controller.signal);
    if(item.id!==selected.id||item.modifiedAt!==selected.modifiedAt||item.size!==selected.size||item.mimeType!==selected.mimeType)throw new Error('La foto cambió. Actualiza la carpeta.');
    if(cached.revision!==item.modifiedAt||cached.size!==item.size||cached.mime!==item.mimeType){URL.revokeObjectURL(cached.url);originalCache.current.delete(item.id);cached=undefined;}
   }
   if(!cached){
    const response=await fetch(fileURL(selected.id)+'&revision='+encodeURIComponent(selected.modifiedAt),{credentials:'same-origin',cache:'no-store',signal:controller.signal});
    if(response.status===401||response.status===403){revoke();if(response.status===401)location.assign('/acceso?returnTo=%2Ffotografia');throw new Error('Tu cuenta ya no tiene acceso a esta foto.');}
    if(!response.ok||response.headers.get('content-type')?.split(';')[0]!==selected.mimeType){await response.body?.cancel();throw new Error('No pudimos descargar esta foto. Actualiza la carpeta.');}
    const reader=response.body?.getReader();if(!reader)throw new Error('La foto no tiene contenido.');const parts:BlobPart[]=[];let size=0;
    try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>selected.size||size>24*1024*1024){await reader.cancel();throw new Error('La foto cambió. Actualiza la carpeta.');}parts.push(value as BlobPart);}}finally{reader.releaseLock();}
    if(size!==selected.size)throw new Error('La foto llegó incompleta. Intenta de nuevo.');
    if(controller.signal.aborted)return;
    cached={revision:selected.modifiedAt,size,mime:selected.mimeType,url:URL.createObjectURL(new Blob(parts,{type:selected.mimeType}))};originalCache.current.set(selected.id,cached);
    let total=[...originalCache.current.values()].reduce((sum,v)=>sum+v.size,0);
    for(const [id,value]of originalCache.current){if(total<=48*1024*1024)break;if(id===selected.id)continue;URL.revokeObjectURL(value.url);originalCache.current.delete(id);total-=value.size;}
   }
   if(!controller.signal.aborted&&authorized.current)setPreviewURL(cached.url);
  }catch(e){if(!controller.signal.aborted){if(selected.thumbnailAvailable){setPreviewThumbnail(true);setPreviewError('Mostrando una vista previa compatible.');}else setPreviewError(message(e));}}})();
  return()=>controller.abort();
 },[preview,previewThumbnail,request,revoke]);
 useEffect(()=>()=>{for(const cached of originalCache.current.values())URL.revokeObjectURL(cached.url);originalCache.current.clear();},[]);
 useEffect(()=>{if(!preview){slideController.current?.abort();setSlideLoading(false);setSlides(null);}return()=>{slideController.current?.abort();};},[!!preview]);
 const moveSlide=useCallback(async(direction:number)=>{
  if(!slides||!preview||slideLoading)return;
  const index=slides.items.findIndex(x=>x.id===preview.id),next=slides.items[index+direction];
  if(next){selectPhoto(next);return;}
  if(direction<0||!slides.token)return;
  const controller=new AbortController();slideController.current?.abort();slideController.current=controller;setSlideLoading(true);setPreviewError('');
  try{
   let token=slides.token,photos=[...slides.items];const seen=new Set<string>();
   while(token&&!controller.signal.aborted){
    if(seen.has(token))throw new Error('No pudimos continuar la carpeta. Cierra el visor y actualiza.');seen.add(token);
    const result=await request<MediaFeed>('/api/media?'+new URLSearchParams({folder:slides.folder,pageToken:token}),{},controller.signal);
    if(controller.signal.aborted||!mounted.current||!authorized.current)return;
    if(!result.connected||!result.canRead||result.folder.id!==slides.folder||result.collectionID!==slides.collection)throw new Error('La carpeta cambió. Cierra el visor y actualiza.');
    photos=[...photos,...result.items.filter(x=>x.kind==='image')].filter((x,i,all)=>all.findIndex(v=>v.id===x.id)===i);token=result.nextPageToken||'';
    if(photos.length>slides.items.length||!token)break;
   }
   if(controller.signal.aborted)return;
   setSlides({...slides,items:photos,token});if(photos[index+1])selectPhoto(photos[index+1]);
  }catch(e){if(!controller.signal.aborted)setPreviewError(message(e));}
  finally{if(slideController.current===controller){slideController.current=null;setSlideLoading(false);}}
 },[slides,preview,slideLoading,request,selectPhoto]);
 useEffect(()=>{if(!preview||preview.kind!=='image')return;const key=(e:KeyboardEvent)=>{if(e.altKey||e.ctrlKey||e.metaKey||e.shiftKey||/INPUT|TEXTAREA|SELECT/.test((e.target as HTMLElement)?.tagName))return;if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();void moveSlide(e.key==='ArrowLeft'?-1:1);}};window.addEventListener('keydown',key);return()=>window.removeEventListener('keydown',key);},[preview,moveSlide]);
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
   if(!result.connected){clearOriginals();setPreview(null);uploadAllowed.current=false;}
   await reconcileMediaOffline(result).catch(()=>{});
   if(!mounted.current||generation!==readGeneration.current)return;
   if(result.deletedFiles?.length){const removed=new Set(result.deletedFiles);setPreview(previous=>previous&&removed.has(previous.id)?null:previous);for(const id of removed){const cached=originalCache.current.get(id);if(cached){URL.revokeObjectURL(cached.url);originalCache.current.delete(id);}}}
   setFeed({...result,items:items.filter((item,index,all)=>all.findIndex(x=>x.id===item.id)===index).sort(newestFirst)});setError('');
  }catch(e){if(controller.signal.aborted)return;if(mounted.current&&generation===readGeneration.current)setError(message(e));}
  finally{if(mounted.current&&generation===readGeneration.current)setLoading(false);}
 },[request,revoke,clearOriginals]);
 useEffect(()=>{
  mounted.current=true;void refresh(folder,1);
  const foreground=()=>{if(document.visibilityState==='visible')void refresh();},timer=setInterval(foreground,30000);
  window.addEventListener('focus',foreground);window.addEventListener('online',foreground);document.addEventListener('visibilitychange',foreground);
  return()=>{mounted.current=false;readController.current?.abort();readGeneration.current++;clearInterval(timer);window.removeEventListener('focus',foreground);window.removeEventListener('online',foreground);document.removeEventListener('visibilitychange',foreground);};
 },[folder,refresh]);
 useEffect(()=>()=>{authorized.current=false;uploadAllowed.current=false;photoController.current?.abort();deleteController.current?.abort();for(const controller of uploadControllers.current)controller.abort();destinationController.current?.abort();destinationGeneration.current++;queue.current=[];},[]);
 function navigate(next:string){if(next===folder)return;currentFolder.current=next;loadedPages.current=1;setFolder(next);setFeed(null);setSearch('');setPreview(null);setError('');setLoading(true);}
 function updateUpload(id:string,update:Partial<PendingUpload>){queue.current=queue.current.map(item=>item.id===id?{...item,...update}:item);if(mounted.current)setUploads([...queue.current]);}
 async function uploadRequest<T>(path:string,init:RequestInit):Promise<T>{const controller=new AbortController();uploadControllers.current.add(controller);const timer=setTimeout(()=>controller.abort(),90000);try{return await request<T>(path,init,controller.signal);}finally{clearTimeout(timer);uploadControllers.current.delete(controller);}}
 const uploadPost=<T,>(body:unknown)=>uploadRequest<T>('/api/media/upload',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 function validateProgress(state:UploadState,item:PendingUpload){if(state.id!==item.id||!Number.isSafeInteger(state.offset)||state.offset<0||state.offset>item.file.size||![CHUNK,DIRECT_CHUNK].includes(state.chunkSize)||(state.complete&&state.offset!==item.file.size))throw new Error('No se pudo confirmar el avance del archivo. Reintenta para consultar su estado.');return state;}
 async function reconcile(item:PendingUpload,error:unknown):Promise<UploadState>{if(!mounted.current||!uploadAllowed.current||error instanceof MediaFailure&&[400,401,403,404,410,413,415,422].includes(error.status))throw error;return validateProgress(await uploadPost<UploadState>({action:'status',transport:'direct',id:item.id}),item);}
 async function processQueue(){
  if(working.current)return;working.current=true;
  meter.current.reset();
  async function worker(){while(mounted.current&&uploadAllowed.current){const item=queue.current.find(x=>x.state==='waiting');if(!item)break;updateUpload(item.id,{state:'uploading',error:''});
   try{
    if(!item.prepared){updateUpload(item.id,{phase:'Preparando imagen…'});const preparation=preparing.current.catch(()=>{}).then(()=>prepareMediaImage(item.file,item.mimeType,item.imageLimit));preparing.current=preparation;item.file=await preparation;item.mimeType=item.file.type||item.mimeType;item.prepared=true;updateUpload(item.id,{file:item.file,mimeType:item.mimeType,prepared:true});if(!mounted.current||!uploadAllowed.current)throw new Error('La subida se ha detenido.');}
    let state:UploadState;try{state=validateProgress(await uploadPost<UploadState>({action:'start',transport:'direct',id:item.id,parentId:item.parentId,filename:item.file.name,mimeType:item.mimeType,size:item.file.size,imageLimit:item.mimeType.startsWith('image/')?item.imageLimit:0}),item);}catch(e){state=await reconcile(item,e);}
    updateUpload(item.id,{offset:state.offset,sent:state.offset,phase:'Subiendo…'});let compatible=false;
    while(!state.complete){if(!mounted.current||!uploadAllowed.current)throw new Error('La subida se ha detenido.');const offset=state.offset,chunk=item.file.slice(offset,Math.min(offset+(compatible?CHUNK:state.chunkSize),item.file.size));
     try{
      if(state.uploadURL&&!compatible){
       try{directMediaUploadURL(state.uploadURL);}catch{throw new MediaFailure('La autorización de subida no es válida.',422);}
       const controller=new AbortController();uploadControllers.current.add(controller);const timer=setTimeout(()=>controller.abort(),120000);
       try{await sendMediaDirectChunk(state.uploadURL,item.mimeType,chunk,offset,item.file.size,controller.signal,sent=>{if(mounted.current&&uploadAllowed.current){meter.current.record(item.id,sent);updateUpload(item.id,{sent:offset+sent,phase:'Subiendo…'});}});updateUpload(item.id,{phase:'Confirmando archivo…'});}
       finally{meter.current.finish(item.id);clearTimeout(timer);uploadControllers.current.delete(controller);}
       if(!mounted.current||!uploadAllowed.current)throw new Error('La subida se ha detenido.');
       state=validateProgress(await uploadPost<UploadState>({action:'status',transport:'direct',id:item.id}),item);
      }else state=validateProgress(await uploadRequest<UploadState>('/api/media/upload?id='+encodeURIComponent(item.id)+'&offset='+offset+(state.uploadURL?'&transport=direct':''),{method:'PUT',headers:{'Content-Type':'application/octet-stream'},body:chunk}),item);
     }catch(e){state=await reconcile(item,e);if(state.provider!=='r2'&&state.uploadURL&&!compatible&&state.offset===offset){compatible=true;continue;}}
     if(state.offset<=offset&&!state.complete)throw new Error('La conexión se interrumpió. Pulsa Reintentar para continuar desde el último tramo confirmado.');
     updateUpload(item.id,{offset:state.offset,sent:state.offset});
    }
    if(state.provider==='r2'){updateUpload(item.id,{phase:'Preparando miniatura…'});const thumbnail=await mediaBrowserThumbnail(item.file,item.mimeType);if(!thumbnail)throw new Error('Archivo subido. No se pudo generar su miniatura; reintenta o usa la app para este formato.');await uploadRequest('/api/media/upload?thumbnail=1&id='+encodeURIComponent(item.id),{method:'PUT',headers:{'Content-Type':'image/jpeg'},body:thumbnail});}
    updateUpload(item.id,{state:'done',offset:item.file.size});
   }catch(e){if(mounted.current&&authorized.current)updateUpload(item.id,{state:'error',sent:queue.current.find(x=>x.id===item.id)?.offset||0,error:message(e)});}
  }}
  try{await Promise.all([worker(),worker()]);}finally{working.current=false;setSpeed(0);if(mounted.current)void refresh(currentFolder.current,loadedPages.current,true);}
 }
 function checkedFiles(files:File[]){const accepted:File[]=[],rejected:string[]=[];for(const file of files){const ext=file.name.split('.').pop()?.toLowerCase()||'';if(!FILE_TYPES[ext]){rejected.push(file.name+': formato no compatible.');continue;}if(!file.size||file.size>MAX_FILE){rejected.push(file.name+': el tamaño debe ser mayor que cero y hasta 20 GB.');continue;}if(file.name.length>180||/[\u0000-\u001f\u007f/\\]/.test(file.name)){rejected.push(file.name+': el nombre debe tener hasta 180 caracteres y no incluir barras.');continue;}accepted.push(file);}return {accepted,rejected};}
 function addFiles(files:File[],target:MediaFolder){
  if(!feed?.connected||!uploadAllowed.current)return;setError('');const added:PendingUpload[]=[],{accepted,rejected}=checkedFiles(files);
  for(const file of accepted){const mimeType=FILE_TYPES[file.name.split('.').pop()!.toLowerCase()];added.push({id:crypto.randomUUID(),parentId:target.id,folderName:target.name,file,mimeType,state:'waiting',offset:0,error:'',imageLimit});}
  queue.current=[...queue.current,...added];setUploads([...queue.current]);if(rejected.length)setError(rejected.join(' '));if(added.length)void processQueue();
 }
 function stageFiles(files:File[]){const {accepted,rejected}=checkedFiles(files);setDraftFiles(previous=>[...previous,...accepted]);setDraftError(rejected.join(' '));}
 function beginUpload(files:File[]=[]){if(!feed?.connected||!uploadAllowed.current)return;const {accepted,rejected}=checkedFiles(files);uploadFolderAttempt.current=null;setDraftFiles(accepted);setDraftError(rejected.join(' '));setDestinationMode(feed.folder.id===feed.root.id?'new':'current');setEventName('');setEventDate(today());setDestination(null);setDestinationError('');setUploadOpen(true);}
 function dropped(event:DragEvent){event.preventDefault();dragDepth.current=0;setDragging(false);if(uploadAllowed.current)beginUpload(Array.from(event.dataTransfer.files));}
 async function browseDestination(target:string,more=false){
  if(!uploadAllowed.current)return;destinationController.current?.abort();const controller=new AbortController();destinationController.current=controller;const revision=++destinationGeneration.current;setDestinationLoading(true);setDestinationError('');
  try{const query=new URLSearchParams({folder:target});if(more&&destination?.nextPageToken)query.set('pageToken',destination.nextPageToken);const result=await request<MediaFeed>('/api/media?'+query,{},controller.signal);if(!mounted.current||revision!==destinationGeneration.current)return;if(!result.connected||!result.canUpload)throw new Error('Esta carpeta no está disponible para subir archivos.');setDestination(previous=>({...result,items:(more&&previous?.folder.id===target?[...previous.items,...result.items]:result.items).filter((item,index,all)=>all.findIndex(x=>x.id===item.id)===index).sort(newestFirst)}));}
  catch(e){if(!controller.signal.aborted&&mounted.current&&revision===destinationGeneration.current)setDestinationError(message(e));}finally{if(mounted.current&&revision===destinationGeneration.current)setDestinationLoading(false);}
 }
 function closeUpload(){if(saving)return;setUploadOpen(false);setDraftFiles([]);uploadFolderAttempt.current=null;destinationController.current?.abort();destinationGeneration.current++;setDestination(null);}
 async function submitUpload(){
  if(saving||!draftFiles.length||!feed?.canUpload||!uploadAllowed.current)return;setSaving(true);setDraftError('');
  try{
   let target=destinationMode==='existing'?destination?.folder:feed.folder;if(destinationMode==='new'){
    if(!eventName.trim())throw new Error('Escribe el nombre de la carpeta.');
    uploadFolderAttempt.current??={id:crypto.randomUUID(),parentId:feed.folder.id,name:eventName.trim(),date:eventDate};
    target=(await post<{folder:MediaFolder}>('/api/media',{action:'createFolder',...uploadFolderAttempt.current})).folder;
   }
   if(!target)throw new Error('Elige una carpeta para estos archivos.');if(!mounted.current||!uploadAllowed.current)return;
   addFiles(draftFiles,target);setUploadOpen(false);setDraftFiles([]);uploadFolderAttempt.current=null;destinationController.current?.abort();destinationGeneration.current++;setDestination(null);navigate(target.id===feed.root.id?'':target.id);
  }catch(e){if(e instanceof MediaFailure&&e.status===400)uploadFolderAttempt.current=null;if(mounted.current&&authorized.current)setDraftError(message(e));}finally{if(mounted.current)setSaving(false);}
 }
 function askDeleteFolder(target:MediaFolder){if(!feed?.canDelete||working.current)return;setDeleteError('');setDeleteFolder(target);}
 async function confirmDeleteFolder(){
  if(!deleteFolder||deleteBusy||!feed?.canDelete)return;const target=deleteFolder,controller=new AbortController();deleteController.current=controller;setDeleteBusy(true);setDeleteError('');
  // Discard a list read that predates the durable deletion marker.
  readController.current?.abort();readGeneration.current++;
  try{
   let result:MediaDeletion;
   do{
    result=await post<MediaDeletion>('/api/media',{action:'deleteFolder',id:target.id},controller.signal);
    if(result.id!==target.id||typeof result.complete!=='boolean'||typeof result.parentId!=='string'||!result.parentId||!Number.isSafeInteger(result.removed)||result.removed<0)throw new Error('No se pudo confirmar la eliminación. Reintenta para consultar su estado.');
    if(controller.signal.aborted||!mounted.current||!authorized.current)return;
    clearOriginals();
    if(!result.complete)await new Promise<void>((resolve,reject)=>{const finish=()=>{controller.signal.removeEventListener('abort',stop);resolve();},timer=setTimeout(finish,result.waiting?1000:100),stop=()=>{clearTimeout(timer);reject(new DOMException('Cancelled','AbortError'));};controller.signal.addEventListener('abort',stop,{once:true});});
   }while(!result.complete&&!controller.signal.aborted);
   if(controller.signal.aborted)return;
   setDeleteFolder(null);setNotice('Carpeta eliminada.');
   if(feed.folder.id===target.id){const parent=result.parentId===feed.root.id?'':result.parentId;navigate(parent);}else await refresh();
  }catch(e){if(!controller.signal.aborted){setDeleteError(message(e));void refresh(currentFolder.current,loadedPages.current,true);}}
  finally{if(deleteController.current===controller){deleteController.current=null;setDeleteBusy(false);}}
 }
 function retirePhoto(id:string){
  readController.current?.abort();readGeneration.current++;slideController.current?.abort();
  const cached=originalCache.current.get(id);if(cached){URL.revokeObjectURL(cached.url);originalCache.current.delete(id);}
  setFeed(previous=>previous?{...previous,items:previous.items.filter(x=>x.id!==id)}:previous);
  setPreview(previous=>previous?.id===id?null:previous);setSlides(previous=>previous?{...previous,items:previous.items.filter(x=>x.id!==id)}:previous);
 }
 async function savePhoto(item:MediaItem){
  if(photoBusy||!feed?.collectionID||!offlineReady)return;const controller=new AbortController();photoController.current=controller;setPhotoBusy(item.id);setError('');
  try{const blob=await fetchMediaPhoto(item,controller.signal);if(controller.signal.aborted||!authorized.current||!mounted.current)return;await saveMediaPhoto(item,blob,feed.breadcrumbs,feed.collectionID);if(!controller.signal.aborted&&authorized.current&&mounted.current)setNotice('Foto disponible sin conexión en este navegador.');}
  catch(e){const status=(e as {status?:number})?.status;if(status===401||status===403){revoke();if(status===401)location.assign('/acceso?returnTo=%2Ffotografia');}else if(status===404||status===410)retirePhoto(item.id);if(!controller.signal.aborted&&mounted.current)setError(message(e));}
  finally{if(photoController.current===controller){photoController.current=null;setPhotoBusy('');}}
 }
 async function confirmDeletePhoto(){
  if(!deletePhoto||deleteBusy||!feed?.canDelete)return;const target=deletePhoto,controller=new AbortController();deleteController.current=controller;setDeleteBusy(true);setDeleteError('');photoController.current?.abort();
  readController.current?.abort();readGeneration.current++;
  try{let result:MediaDeletion;do{
   result=await post<MediaDeletion>('/api/media',{action:'deleteFile',id:target.id,...('modifiedAt' in target?{revision:target.modifiedAt}:{})},controller.signal);
   if(result.id!==target.id||typeof result.complete!=='boolean'||!result.parentId||!Number.isSafeInteger(result.removed))throw new Error('No se pudo confirmar el archivo eliminado. Reintenta.');
   if(controller.signal.aborted||!mounted.current||!authorized.current)return;retirePhoto(target.id);await removeMediaOffline([target.id]);
   if(!result.complete)await new Promise<void>((resolve,reject)=>{const timer=setTimeout(resolve,result.waiting?1000:100);controller.signal.addEventListener('abort',()=>{clearTimeout(timer);reject(new DOMException('Cancelled','AbortError'));},{once:true});});
  }while(!result.complete&&!controller.signal.aborted);
  if(controller.signal.aborted)return;setDeletePhoto(null);setNotice('Archivo eliminado.');await refresh();
  }catch(e){if(!controller.signal.aborted){setDeleteError(message(e));void refresh(currentFolder.current,loadedPages.current,true);}}
  finally{if(deleteController.current===controller){deleteController.current=null;setDeleteBusy(false);}}
 }
 function deleteAction(item:MediaItem){return feed?.canDelete&&<button type="button" className="media-photo-delete" disabled={deleteBusy||working.current} onClick={()=>{setDeleteError('');setDeletePhoto(item);}}><Trash2 size={16}/>{item.kind==='video'?'Eliminar video':'Eliminar foto'}</button>;}
 function photoActions(item:MediaItem){return <>
  <a href={fileURL(item.id)+'&revision='+encodeURIComponent(item.modifiedAt)} download={item.name}><Download size={16}/>Descargar foto</a>
  <button type="button" disabled={!!photoBusy||!offlineReady||offlineIDs.has(item.id)} onClick={()=>void savePhoto(item)}>{photoBusy===item.id?<LoaderCircle size={16} className="media-spin"/>:<Cloud size={16}/>} {offlineIDs.has(item.id)?'Disponible sin conexión':'Guardar sin conexión'}</button>
  {deleteAction(item)}
 </>;}
 async function createFolder(){if(saving||!feed?.canUpload||!uploadAllowed.current)return;const name=folderName.trim();if(!name)return;setSaving(true);setFolderError('');
  if(!createAttempt.current)createAttempt.current={id:crypto.randomUUID(),parentId:feed.folder.id,name,date:folderDate};
  try{const result=await post<{folder:MediaFolder}>('/api/media',{action:'createFolder',...createAttempt.current});if(mounted.current){setCreating(false);createAttempt.current=null;navigate(result.folder.id);setNotice('Carpeta creada. Ya puedes guardar aquí las fotos y videos.');}}catch(e){if(e instanceof MediaFailure&&e.status===400)createAttempt.current=null;if(mounted.current&&authorized.current)setFolderError(message(e));}finally{if(mounted.current)setSaving(false);}
 }

 const items=(feed?.items||[]).filter(item=>item.name.toLocaleLowerCase('es').includes(search.toLocaleLowerCase('es'))),folders=items.filter(x=>x.kind==='folder'),files=items.filter(x=>x.kind!=='folder'),activeUploads=uploads.filter(x=>x.state==='waiting'||x.state==='uploading').length;
 const uploadTotal=uploads.reduce((n,x)=>n+x.file.size,0),uploadBytes=uploads.reduce((n,x)=>n+(x.state==='done'?x.file.size:Math.min(x.file.size,x.sent??x.offset)),0),uploadPercent=uploadTotal?Math.min(uploads.every(x=>x.state==='done')?100:99,Math.floor(uploadBytes/uploadTotal*100)):0;
 return <section className="media-gallery" aria-label="Galería de fotografía">
  <MediaFolderSharing folder={sharingFolder} onClose={()=>setSharingFolder(null)}/>
  <a className="media-offline-link" href="/fotografia-offline.html"><Cloud size={17}/>Fotos sin conexión en este navegador</a>
  {error&&<p className="message error media-feedback" role="alert">{error}</p>}{notice&&<p className="message success media-feedback" role="status">{notice}<button aria-label="Cerrar mensaje" onClick={()=>setNotice('')}><X size={16}/></button></p>}
  {!feed&&loading?<div className="media-empty" role="status"><LoaderCircle className="media-spin"/><h3>Abriendo la galería…</h3></div>:!feed?<div className="media-empty"><Camera/><h3>No pudimos abrir la galería</h3><p>Comprueba tu conexión o los permisos de tu cuenta.</p><Button variant="outline" onClick={()=>void refresh()}>Reintentar</Button></div>:!feed.connected?<div className="media-empty media-connect"><Cloud/><h3>Preparando el archivo de JAC</h3><p>El archivo privado de Fotografía se administra en Configuración general → Servicios conectados.</p></div>:<>
   <div className="media-toolbar"><div className="media-toolbar-context"><nav className="media-breadcrumb" aria-label="Carpetas de fotografía">{(feed.breadcrumbs.length?feed.breadcrumbs:[feed.root]).map((part,index,all)=><span key={part.id}>{index>0&&<ChevronRight size={15}/>}<button aria-current={index===all.length-1?'page':undefined} onClick={()=>navigate(part.id===feed.root.id?'':part.id)}>{index===0&&<Folder size={16}/>}<span>{index===0?'Archivo JAC':part.name}</span></button></span>)}</nav><span className="media-sync"><Cloud size={13}/>{feed.provider==='r2'?'Archivo JAC · R2':'Archivo JAC'}</span></div><div className="media-toolbar-actions"><Button variant="outline" size="icon" aria-label="Actualizar galería" title="Actualizar galería" disabled={loading} onClick={()=>{retryThumbnails();void refresh();}}><RefreshCw size={17} className={loading?'media-spin':''}/></Button>{feed.canUpload&&<><details className="media-options"><summary aria-label="Opciones de la galería"><MoreHorizontal size={19}/></summary><div><button onClick={event=>{event.currentTarget.closest('details')?.removeAttribute('open');createAttempt.current=null;setFolderName('');setFolderDate(today());setFolderError('');setCreating(true);}}><FolderPlus size={16}/>Nueva carpeta</button><button onClick={event=>{event.currentTarget.closest('details')?.removeAttribute('open');setQualityOpen(true);}}><ImageIcon size={16}/>Calidad de las imágenes</button>{feed.canDelete&&feed.folder.id!==feed.root.id&&<button onClick={event=>{event.currentTarget.closest('details')?.removeAttribute('open');askDeleteFolder(feed.folder);}} disabled={deleteBusy||working.current}><Trash2 size={16}/>Eliminar esta carpeta</button>}</div></details><Button className="primary" onClick={()=>beginUpload()}><Upload size={17}/>Subir fotos y videos</Button></>}</div></div>
   <div className="media-search-row"><div><h3>{feed.folder.id===feed.root.id?'Shows y jornadas':feed.folder.name}</h3><span>{feed.items.length} {feed.items.length===1?'elemento':'elementos'} · Más recientes primero</span></div><Input aria-label="Buscar en esta carpeta" value={search} onChange={event=>setSearch(event.target.value)} placeholder="Buscar en esta carpeta"/></div>

   {feed.canUpload&&<div className={'media-dropzone'+(dragging?' dragging':'')} onDragEnter={event=>{event.preventDefault();dragDepth.current++;setDragging(true);}} onDragOver={event=>{event.preventDefault();event.dataTransfer.dropEffect='copy';}} onDragLeave={event=>{event.preventDefault();dragDepth.current--;if(dragDepth.current<=0)setDragging(false);}} onDrop={dropped}><span className="media-drop-icon"><Upload size={22}/></span><div><strong>{dragging?'Suelta para preparar la subida':'Arrastra fotos y videos'}</strong><p>Elige el destino antes de subir. <button onClick={()=>beginUpload()}>Seleccionar archivos</button></p></div><span className="media-drop-hint">{mediaImageQualityLabel(imageLimit)} en fotos · Videos originales</span></div>}
   {!!uploads.length&&<section className="media-uploads" aria-label="Estado de las subidas">
    <div className="media-upload-summary">
     <div className="media-upload-ring" role="progressbar" aria-label="Progreso general de subida" aria-valuemin={0} aria-valuemax={100} aria-valuenow={uploadPercent} style={{'--upload-progress':uploadPercent+'%'} as React.CSSProperties}><span>{uploadPercent}%</span></div>
     <div className="media-upload-summary-text"><h3>{activeUploads?'Subiendo al archivo':uploads.some(x=>x.state==='error')?'Revisa los archivos pendientes':'Archivos guardados'}</h3><p>{uploads.filter(x=>x.state==='done').length} de {uploads.length} completados · {bytes(uploadBytes)} de {bytes(uploadTotal)}</p><strong className="media-upload-speed" data-testid="media.upload.speed">{activeUploads?(speed>0?bytes(speed)+'/s':'Esperando transferencia…'):uploads.some(x=>x.state==='error')?'Subida con pendientes':'Subida finalizada'}</strong><small>La velocidad corresponde a los datos enviados; cada archivo se confirma antes de guardarlo.</small></div>
     <Button variant="ghost" disabled={!!activeUploads||!uploads.some(x=>x.state==='done')} onClick={()=>{queue.current=queue.current.filter(x=>x.state!=='done');setUploads([...queue.current]);}}>Ocultar completados</Button>
    </div>
    <details className="media-upload-details"><summary>Ver archivos{uploads.some(x=>x.state==='error')?' · Hay archivos por reintentar':''}</summary><div className="media-upload-items">{uploads.map(item=><div className={'media-upload-row '+item.state} key={item.id}><span className="media-upload-symbol">{item.state==='done'?<Check size={20}/>:item.state==='uploading'?<LoaderCircle size={20} className="media-spin"/>:<Upload size={20}/>}</span><div><strong>{item.file.name}</strong><small>{item.folderName} · {item.state==='waiting'?'En espera':item.state==='done'?'Guardado':item.state==='error'?'Pendiente':item.phase||'Pendiente'}</small>{item.error&&<p role="alert">{item.error}</p>}</div>{item.state==='error'&&<Button variant="outline" onClick={()=>{updateUpload(item.id,{state:'waiting',error:''});void processQueue();}}>Reintentar</Button>}</div>)}</div></details>
   </section>}
   {!items.length?<div className="media-empty"><ImageIcon/><h3>{search?'No hay coincidencias':'El próximo recuerdo empieza aquí'}</h3><p>{search?'Prueba otro nombre en esta carpeta.':feed.canUpload?'Pulsa Subir fotos y videos para elegir o crear la carpeta del evento.':'Esta carpeta aún no tiene fotos ni videos.'}</p></div>:<>
    {!!folders.length&&<section className="media-section"><h4>Carpetas</h4><div className="media-folder-grid">{folders.map(item=><div key={item.id} className="media-folder-row"><button className="media-folder-card" onClick={()=>navigate(item.id)}><span><Folder size={24}/></span><div><strong>{item.name}</strong><small>{fileDate(item.createdAt||'')}</small></div><ChevronRight size={17}/></button><span className="media-folder-actions">{feed.canUpload&&<button type="button" className="media-share-folder" aria-label={'Compartir carpeta '+item.name} title="Compartir carpeta" onClick={()=>setSharingFolder(item)}><Share size={18}/></button>}{feed.canDelete&&<button type="button" className="media-delete-folder" aria-label={'Eliminar carpeta '+item.name} title="Eliminar carpeta" disabled={deleteBusy||working.current} onClick={()=>askDeleteFolder(item)}><Trash2 size={17}/></button>}</span></div>)}</div></section>}
    {!!files.length&&<section className="media-section"><h4>Fotos y videos</h4><div className="media-file-grid">{files.map(item=><div key={item.id} className="media-file-entry"><button className="media-file-card" onClick={()=>openPreview(item)} aria-label={'Abrir '+item.name}><span className="media-thumbnail">{thumbnails[item.id]?.state==='loading'?<LoaderCircle className="media-spin media-thumbnail-fallback" size={25}/>:item.kind==='video'?<Video className="media-thumbnail-fallback" size={34}/>:<ImageIcon className="media-thumbnail-fallback" size={34}/>} {thumbnails[item.id]?.url?<img src={thumbnails[item.id].url} alt="" loading="eager" decoding="async" onError={()=>thumbnailFailed(item.id)}/>:thumbnails[item.id]?.state==='pending'?<span className="media-thumbnail-message">Vista previa en proceso</span>:thumbnails[item.id]?.state==='error'?<span className="media-thumbnail-message">Vista previa no disponible</span>:null}{item.kind==='video'&&<span className="media-video-badge"><Video size={14}/>Video</span>}</span><span className="media-file-caption"><strong>{item.name}</strong><small>{bytes(item.size)}<span>·</span>{fileDate(item.modifiedAt)}</small></span></button>{(item.kind==='image'||feed.canDelete)&&<details className="media-photo-options"><summary aria-label={'Opciones de '+item.name}><MoreHorizontal size={20}/><span>Opciones</span></summary><div className="media-photo-menu">{item.kind==='image'?photoActions(item):deleteAction(item)}</div></details>}</div>)}</div></section>}
   </>}
   {feed.nextPageToken&&<div className="media-load-more"><Button variant="outline" disabled={loading} onClick={()=>{loadedPages.current++;void refresh();}}>{loading?'Cargando…':'Ver más archivos'}</Button></div>}
  </>}
  <Dialog open={uploadOpen} onOpenChange={value=>{if(!value)closeUpload();}}><DialogContent className="media-upload-dialog" showCloseButton={!saving} onEscapeKeyDown={event=>{if(saving)event.preventDefault();}} onInteractOutside={event=>{if(saving)event.preventDefault();}}><DialogTitle>Subir fotos y videos</DialogTitle><DialogDescription>Elige la carpeta del evento y agrega todos sus archivos.</DialogDescription><form onSubmit={event=>{event.preventDefault();void submitUpload();}}>
   <fieldset className="media-destination-fields" disabled={saving||!!uploadFolderAttempt.current}><label>Guardar en<select aria-label="Destino de la subida" value={destinationMode} onChange={event=>{const mode=event.target.value as 'current'|'new'|'existing';setDestinationMode(mode);setDestinationError('');if(mode==='existing'&&feed)void browseDestination(feed.root.id);}}><option value="new">Nuevo evento o jornada</option><option value="current">{feed?.folder.id===feed?.root.id?'Archivo JAC (raíz)':'Esta carpeta'}</option><option value="existing">Elegir otra carpeta</option></select></label>
   {destinationMode==='new'&&<><p className="media-parent-context"><Folder size={14}/>Dentro de {feed?.folder.id===feed?.root.id?'Archivo JAC':feed?.folder.name}</p><div className="media-event-fields"><label>Nombre del evento<Input autoFocus aria-label="Nombre del evento para las fotos" required maxLength={160} placeholder="Ej. Pereira · Show principal" value={eventName} onChange={event=>setEventName(event.target.value)}/></label></div></>}
   {destinationMode==='current'&&<div className="media-current-destination"><Folder size={19}/><span>{feed?.folder.name}</span></div>}
   {destinationMode==='existing'&&<div className="media-destination-browser"><nav aria-label="Destino de los archivos">{(destination?.breadcrumbs||[feed?.root]).filter((part):part is MediaFolder=>!!part).map((part,index)=><span key={part.id}>{index>0&&<ChevronRight size={12}/>}<button type="button" onClick={()=>void browseDestination(part.id)}>{part.id===feed?.root.id?'Archivo JAC':part.name}</button></span>)}</nav>{destinationLoading&&<p role="status"><LoaderCircle size={15} className="media-spin"/>Buscando carpetas…</p>}{destinationError&&<p className="media-destination-error" role="alert">{destinationError}</p>}{!destinationLoading&&destination&&<><div className="media-destination-list">{destination.items.filter(item=>item.kind==='folder').map(item=><button type="button" key={item.id} onClick={()=>void browseDestination(item.id)}><Folder size={17}/><span>{item.name}</span><ChevronRight size={15}/></button>)}{!destination.items.some(item=>item.kind==='folder')&&<p>No hay subcarpetas.</p>}</div>{destination.nextPageToken&&<button type="button" className="media-more-folders" onClick={()=>void browseDestination(destination.folder.id,true)}>Ver más carpetas</button>}<div className="media-selected-destination"><Check size={15}/><span>Destino: {destination.folder.id===destination.root.id?'Archivo JAC':destination.folder.name}</span></div></>}</div>}
   </fieldset>
   <div className="media-quality-shortcut"><span>Imágenes: {mediaImageQualityLabel(imageLimit)}</span><button type="button" onClick={()=>setQualityOpen(true)}>Cambiar calidad</button></div><div className="media-staged-files"><input ref={fileInput} className="media-file-input" type="file" accept={ACCEPT} multiple aria-label="Seleccionar fotos y videos" disabled={saving} onChange={event=>{stageFiles(Array.from(event.target.files||[]));event.target.value='';}}/><button type="button" className="media-file-picker" disabled={saving} onClick={()=>fileInput.current?.click()} onDragOver={event=>{event.preventDefault();event.dataTransfer.dropEffect='copy';}} onDrop={event=>{event.preventDefault();if(!saving)stageFiles(Array.from(event.dataTransfer.files));}}><Upload size={23}/><strong>{draftFiles.length?'Agregar más archivos':'Seleccionar fotos y videos'}</strong><span>{mediaImageQualityLabel(imageLimit)} en fotos · Videos originales</span></button>
   {!!draftFiles.length&&<><div className="media-selection-heading"><strong>{draftFiles.length} {draftFiles.length===1?'archivo seleccionado':'archivos seleccionados'}</strong><span>{bytes(draftFiles.reduce((sum,file)=>sum+file.size,0))}</span></div><ul className="media-selection-list">{draftFiles.map((file,index)=><li key={index}><span>{file.name}<small>{bytes(file.size)}</small></span><button type="button" disabled={saving} aria-label={'Quitar '+file.name} onClick={()=>setDraftFiles(previous=>previous.filter((_,at)=>at!==index))}><X size={15}/></button></li>)}</ul></>}
   </div>
   {draftError&&<p className="message error" role="alert">{draftError}</p>}<div className="media-dialog-actions"><Button type="button" variant="outline" disabled={saving} onClick={closeUpload}>Cancelar</Button><Button className="primary" type="submit" disabled={saving||!draftFiles.length||destinationMode==='new'&&!eventName.trim()||destinationMode==='existing'&&(!destination||destinationLoading||!!destinationError)}>{saving?<><LoaderCircle size={16} className="media-spin"/>Preparando…</>:uploadFolderAttempt.current?'Reintentar creación y subir':destinationMode==='new'?'Crear carpeta y subir':'Subir '+draftFiles.length+' '+(draftFiles.length===1?'archivo':'archivos')}</Button></div>
  </form></DialogContent></Dialog>
  {!!feed?.pendingDeletions?.length&&<div className="media-pending-deletes" role="status">{feed.pendingDeletions.map(item=><div key={item.id}><span>Eliminación pendiente: {item.name}</span><Button variant="outline" disabled={deleteBusy} onClick={()=>askDeleteFolder(item)}>Continuar eliminación</Button></div>)}</div>}
  <Dialog open={!!deleteFolder} onOpenChange={open=>{if(!open&&!deleteBusy)setDeleteFolder(null);}}><DialogContent className="media-folder-dialog" showCloseButton={!deleteBusy} onEscapeKeyDown={event=>{if(deleteBusy)event.preventDefault();}} onInteractOutside={event=>{if(deleteBusy)event.preventDefault();}}><DialogTitle>Eliminar carpeta</DialogTitle><DialogDescription>¿Estás seguro de eliminar «{deleteFolder?.name}» y todo su contenido?</DialogDescription>{deleteError&&<p className="message error" role="alert">{deleteError}</p>}<div className="media-dialog-actions"><Button variant="outline" disabled={deleteBusy} onClick={()=>setDeleteFolder(null)}>Cancelar</Button><Button variant="destructive" disabled={deleteBusy} onClick={()=>void confirmDeleteFolder()}>{deleteBusy?<><LoaderCircle size={16} className="media-spin"/>Eliminando…</>:deleteError?'Reintentar eliminación':'Eliminar'}</Button></div></DialogContent></Dialog>
  {!!feed?.pendingFileDeletions?.length&&<div className="media-pending-deletes">{feed.pendingFileDeletions.map(item=><div key={item.id}><span>Eliminación pendiente: {item.name}</span><Button variant="outline" disabled={deleteBusy} onClick={()=>{setDeleteError('');setDeletePhoto(item);}}>Continuar eliminación</Button></div>)}</div>}
  <Dialog open={!!deletePhoto} onOpenChange={open=>{if(!open&&!deleteBusy)setDeletePhoto(null);}}><DialogContent className="media-folder-dialog" showCloseButton={!deleteBusy} onEscapeKeyDown={event=>{if(deleteBusy)event.preventDefault();}} onInteractOutside={event=>{if(deleteBusy)event.preventDefault();}}><DialogTitle>Eliminar archivo</DialogTitle><DialogDescription>¿Estás seguro de eliminar «{deletePhoto?.name}» de Fotografía? Se eliminará para todo el equipo.</DialogDescription>{deleteError&&<p role="alert" className="message error">{deleteError}</p>}<div className="media-dialog-actions"><Button variant="outline" disabled={deleteBusy} onClick={()=>setDeletePhoto(null)}>Cancelar</Button><Button variant="destructive" disabled={deleteBusy} onClick={()=>void confirmDeletePhoto()}>{deleteBusy?'Eliminando…':deleteError?'Reintentar eliminación':'Eliminar archivo'}</Button></div></DialogContent></Dialog>
  <Dialog open={qualityOpen} onOpenChange={setQualityOpen}><DialogContent className="media-folder-dialog"><DialogTitle>Calidad de las imágenes</DialogTitle><DialogDescription>Se usará en las próximas selecciones de este navegador. Los videos siempre se suben completos.</DialogDescription><label>Tamaño máximo por imagen<select aria-label="Calidad de las imágenes" value={imageLimit} onChange={e=>{const value=Number(e.target.value) as MediaImageLimit;setImageLimit(value);try{saveMediaImageLimit(value);}catch(error){setError(message(error));}}}>{MEDIA_IMAGE_LIMITS.map(value=><option key={value} value={value}>{mediaImageQualityLabel(value)}</option>)}</select></label><p className="media-quality-help">Las imágenes que ya pesan menos se conservan. Cuando se reducen, se guardan como JPG; tu archivo de origen queda intacto. Sin compresión conserva todos los bytes. Las miniaturas se generan por separado.</p><Button onClick={()=>setQualityOpen(false)}>Listo</Button></DialogContent></Dialog>
  <Dialog open={creating} onOpenChange={value=>{if(!saving){setCreating(value);if(!value)createAttempt.current=null;}}}><DialogContent className="media-folder-dialog"><DialogTitle>Nueva carpeta</DialogTitle><DialogDescription>Organiza las fotos y los videos de un show o día de trabajo.</DialogDescription><form onSubmit={event=>{event.preventDefault();void createFolder();}}><label>Nombre del show o jornada<Input autoFocus aria-label="Nombre de la carpeta" maxLength={160} required value={folderName} disabled={saving||!!createAttempt.current} placeholder="Ej. Pereira · Show principal" onChange={event=>setFolderName(event.target.value)}/></label>{folderError&&<p className="message error" role="alert">{folderError}</p>}<div className="media-dialog-actions"><Button type="button" variant="outline" disabled={saving} onClick={()=>{setCreating(false);createAttempt.current=null;}}>Cancelar</Button><Button type="submit" className="primary" disabled={saving||!folderName.trim()}>{saving?'Creando…':createAttempt.current?'Reintentar creación':'Crear carpeta'}</Button></div></form></DialogContent></Dialog>
  <Dialog open={!!preview} onOpenChange={value=>{if(!value){setPreview(null);setPreviewError('');}}}><DialogContent className="media-preview"><DialogTitle>{preview?.name||'Vista previa'}</DialogTitle><DialogDescription>{preview?bytes(preview.size)+' · '+fileDate(preview.modifiedAt):'Fotos y videos de JAC Music'}</DialogDescription>{preview&&<><div className="media-preview-stage" onTouchStart={e=>{touch.current=e.touches.length===1?{x:e.touches[0].clientX,y:e.touches[0].clientY}:null;}} onTouchEnd={e=>{const start=touch.current;touch.current=null;if(start&&e.changedTouches.length===1){const dx=e.changedTouches[0].clientX-start.x,dy=e.changedTouches[0].clientY-start.y;if(Math.abs(dx)>60&&Math.abs(dx)>Math.abs(dy)*1.5)void moveSlide(dx<0?1:-1);}}}>{preview.kind==='video'?<video key={preview.id} controls playsInline preload="metadata" src={fileURL(preview.id)} onError={()=>{setPreviewError('Este video no se puede reproducir aquí. Puedes descargar el original para abrirlo en tu dispositivo.');void refresh(currentFolder.current,loadedPages.current,true);}}/>:!previewURL?<LoaderCircle className="media-spin" size={28} aria-label="Abriendo foto"/>:<img key={preview.id+String(previewThumbnail)} src={previewURL} alt={preview.name} onError={()=>{if(!previewThumbnail&&preview.thumbnailAvailable){setPreviewThumbnail(true);setPreviewError('Mostrando una vista previa compatible. El archivo original está disponible para descargar.');}else setPreviewError('No pudimos mostrar esta imagen. Puedes descargar el original si tu navegador no admite su formato.');void refresh(currentFolder.current,loadedPages.current,true);}}/>}</div>{slides&&<div className="media-slide-controls" aria-label="Navegar fotos"><button type="button" aria-label="Foto anterior" disabled={slideLoading||slides.items.findIndex(x=>x.id===preview.id)<=0} onClick={()=>void moveSlide(-1)}><ChevronLeft size={22}/><span>Anterior</span></button><span role="status" aria-live="polite">{slideLoading?<><LoaderCircle size={16} className="media-spin"/>Cargando…</>:`${slides.items.findIndex(x=>x.id===preview.id)+1} de ${slides.items.length}${slides.token?'+':''}`}</span><button type="button" aria-label="Foto siguiente" disabled={slideLoading||(!slides.token&&slides.items.findIndex(x=>x.id===preview.id)>=slides.items.length-1)} onClick={()=>void moveSlide(1)}><span>Siguiente</span><ChevronRight size={22}/></button></div>}{previewError&&<p className="media-preview-error" role="alert">{previewError}</p>}<div className="media-preview-footer"><span>{previewThumbnail?'Vista previa optimizada':'Archivo guardado'} · JAC Music</span>{(preview.kind==='image'||feed?.canDelete)&&<div className="media-photo-actions">{preview.kind==='image'?photoActions(preview):deleteAction(preview)}</div>}<a href={fileURL(preview.id)} download={preview.name}><Download size={17}/>Descargar archivo</a></div></>}</DialogContent></Dialog>
 </section>;
}
