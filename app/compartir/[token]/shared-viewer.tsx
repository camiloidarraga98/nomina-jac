'use client';
import MediaAdaptiveVideo from '@/app/media-adaptive-video';
import {useCallback,useEffect,useRef,useState} from 'react';
import {ChevronLeft,ChevronRight,Download,LoaderCircle,X} from 'lucide-react';
import {Dialog,DialogContent,DialogDescription,DialogTitle} from '@/components/ui/dialog';
import type {MediaItem} from '@/lib/media-core';

export type SharedMediaFeed={folder:{id:string;name:string};breadcrumbs:{id:string;name:string}[];items:MediaItem[];nextPageToken:string;expiresAt:string};
export default function SharedViewer({token,initial,feed,onPage,onRevoked,onClose}:{token:string;initial:MediaItem;feed:SharedMediaFeed;onPage:(feed:SharedMediaFeed)=>void;onRevoked:()=>void;onClose:()=>void}){
 const [item,setItem]=useState(initial),[items,setItems]=useState(()=>feed.items.filter(item=>item.kind!=='folder')),[nextPage,setNextPage]=useState(feed.nextPageToken),[loading,setLoading]=useState(false),[error,setError]=useState(''),[compatibleID,setCompatibleID]=useState('');
 const request=useRef<AbortController|null>(null),busy=useRef(false),video=useRef<HTMLVideoElement|null>(null),touch=useRef<{x:number;y:number}|null>(null);
 const base='/api/media/shared?token='+encodeURIComponent(token),index=items.findIndex(value=>value.id===item.id);
 const compatible=item.kind==='image'&&item.thumbnailAvailable&&(/^image\/(heic|heif|tiff)$/.test(item.mimeType)||compatibleID===item.id);
 const file=(thumbnail=false)=>base+'&id='+encodeURIComponent(item.id)+'&revision='+encodeURIComponent(item.modifiedAt)+(thumbnail?'&thumbnail=1':'');
 useEffect(()=>()=>request.current?.abort(),[]);
 const select=useCallback((next:MediaItem)=>{video.current?.pause();setError('');setItem(next);},[]);
 const close=()=>{request.current?.abort();video.current?.pause();onClose();};
 const move=useCallback(async(direction:-1|1)=>{
  if(busy.current)return;const at=items.findIndex(value=>value.id===item.id),next=items[at+direction];
  if(next){select(next);return;}if(direction<0||!nextPage)return;
  const controller=new AbortController();request.current?.abort();request.current=controller;busy.current=true;setLoading(true);setError('');
  try{
   let page=nextPage,all=[...items];const visited=new Set<string>();
   while(page){
    if(visited.has(page))throw new Error('No pudimos cargar el siguiente archivo. Reintenta.');visited.add(page);
    const response=await fetch(base+'&folder='+encodeURIComponent(feed.folder.id)+'&pageToken='+encodeURIComponent(page),{signal:controller.signal,credentials:'omit',cache:'no-store',referrerPolicy:'no-referrer'});
    if([403,404,410].includes(response.status)){onRevoked();return;}
    const body=await response.json() as SharedMediaFeed&{error?:string};if(!response.ok)throw new Error(body.error||'No pudimos cargar el siguiente archivo.');
    if(body.folder.id!==feed.folder.id)throw new Error('La carpeta cambió. Cierra el visor y vuelve a abrirla.');
    if(controller.signal.aborted)return;
    const known=new Set(all.map(value=>value.id));all=[...all,...body.items.filter(value=>value.kind!=='folder'&&!known.has(value.id)&&!!known.add(value.id))];page=body.nextPageToken||'';onPage(body);
    if(all[at+1]||!page)break;
   }
   if(controller.signal.aborted)return;setItems(all);setNextPage(page);if(all[at+1])select(all[at+1]);
  }catch(e){if(!controller.signal.aborted)setError(e instanceof Error?e.message:'No pudimos cargar el siguiente archivo.');}
  finally{if(request.current===controller){request.current=null;busy.current=false;if(!controller.signal.aborted)setLoading(false);}}
 },[base,feed.folder.id,item.id,items,nextPage,onPage,onRevoked,select]);
 return <Dialog open onOpenChange={open=>{if(!open)close();}}><DialogContent className="jac-shared-viewer" overlayClassName="jac-shared-viewer-backdrop" showCloseButton={false} onKeyDown={event=>{if(event.target instanceof HTMLInputElement||event.target instanceof HTMLTextAreaElement||event.target instanceof HTMLVideoElement)return;if(event.key==='ArrowLeft'||event.key==='ArrowRight'){event.preventDefault();void move(event.key==='ArrowLeft'?-1:1);}}}>
 <DialogTitle>{item.name}</DialogTitle><DialogDescription>{item.kind==='video'?'Video':'Fotografía'} · {feed.folder.name}</DialogDescription>
 <div className="jac-shared-viewer-stage" onTouchStart={event=>{const point=event.touches[0];touch.current=event.touches.length===1?{x:point.clientX,y:point.clientY}:null;if(event.target instanceof HTMLVideoElement&&point.clientY>event.target.getBoundingClientRect().bottom-55)touch.current=null;}} onTouchEnd={event=>{const start=touch.current;touch.current=null;if(start&&event.changedTouches.length===1){const dx=event.changedTouches[0].clientX-start.x,dy=event.changedTouches[0].clientY-start.y;if(Math.abs(dx)>60&&Math.abs(dx)>Math.abs(dy)*1.5)void move(dx<0?1:-1);}}}>
 {item.kind==='video'?<MediaAdaptiveVideo key={item.id} infoURL={base+'&id='+encodeURIComponent(item.id)+'&playback=1'} videoRef={video} onRevoked={onRevoked}/>:<img key={item.id+String(compatible)} src={file(compatible)+(compatible?'':'&preview=1')} alt={item.name} draggable={false} referrerPolicy="no-referrer" onError={()=>{if(!compatible&&item.thumbnailAvailable)setCompatibleID(item.id);else setError('No pudimos mostrar esta imagen. Puedes descargar el archivo completo.');}}/>}
 </div>
 <div className="jac-shared-viewer-navigation" aria-label="Navegar archivos"><button type="button" aria-label="Archivo anterior" disabled={loading||index<=0} onClick={()=>void move(-1)}><ChevronLeft/><span>Anterior</span></button><span role="status" aria-live="polite">{loading?<><LoaderCircle className="jac-shared-spin"/>Cargando…</>:`${index+1} de ${items.length}${nextPage?'+':''}`}</span><button type="button" aria-label="Archivo siguiente" disabled={loading||(!nextPage&&index>=items.length-1)} onClick={()=>void move(1)}><span>Siguiente</span><ChevronRight/></button></div>
 {error&&<p role="alert" className="jac-shared-viewer-error">{error}</p>}
 <footer>{compatible&&<small>Vista previa compatible</small>}<a href={file()+'&download=1'} download={item.name} referrerPolicy="no-referrer"><Download/>Descargar archivo</a></footer>
 <button type="button" data-slot="dialog-close" aria-label="Cerrar visor" onClick={close}><X/></button>
 </DialogContent></Dialog>;
}
