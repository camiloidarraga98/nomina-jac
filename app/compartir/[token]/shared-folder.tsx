'use client';
import {useCallback,useEffect,useRef,useState,type PointerEvent} from 'react';
import {Check,CheckSquare,Download,Folder,Image as ImageIcon,Video,X} from 'lucide-react';
import type {MediaItem} from '@/lib/media-core';
import './shared.css';
import SharedViewer,{type SharedMediaFeed as Feed} from './shared-viewer';
export default function SharedFolder({token}:{token:string}){
 const [feed,setFeed]=useState<Feed|null>(null),[folder,setFolder]=useState(''),[page,setPage]=useState(''),[error,setError]=useState(''),[loading,setLoading]=useState(false),[preview,setPreview]=useState<MediaItem|null>(null);
 const feedRef=useRef<Feed|null>(null);
 const [selecting,setSelecting]=useState(false),[selected,setSelected]=useState<Record<string,string>>({}),[downloadNotice,setDownloadNotice]=useState('');
 const hold=useRef<ReturnType<typeof setTimeout>|null>(null),press=useRef<{x:number;y:number}|null>(null),heldClick=useRef(''),touchPress=useRef(false);
 function clearHold(){if(hold.current!==null)clearTimeout(hold.current);hold.current=null;press.current=null;}
 useEffect(()=>()=>{if(hold.current!==null)clearTimeout(hold.current);},[]);
 const retire=useCallback(()=>{feedRef.current=null;setFeed(null);setPreview(null);setSelected({});setSelecting(false);setError('Este enlace ya no está disponible.');},[]);
 const appendPage=useCallback((next:Feed)=>{const previous=feedRef.current;if(previous?.folder.id!==next.folder.id)return;const known=new Set<string>(),merged={...next,items:[...previous.items,...next.items].filter(item=>!known.has(item.id)&&!!known.add(item.id))};feedRef.current=merged;setFeed(merged);},[]);
 const base='/api/media/shared?token='+encodeURIComponent(token);
 const file=(item:MediaItem,thumbnail=false)=>base+'&id='+encodeURIComponent(item.id)+'&revision='+encodeURIComponent(item.modifiedAt)+(thumbnail?'&thumbnail=1':'');
 useEffect(()=>{const controller=new AbortController();setLoading(true);setError('');
  void(async()=>{try{if(!token)throw new Error('Este enlace no es válido.');const response=await fetch(base+'&folder='+encodeURIComponent(folder)+'&pageToken='+encodeURIComponent(page),{signal:controller.signal,credentials:'omit',cache:'no-store',referrerPolicy:'no-referrer'}),body=await response.json() as Feed & {error?:string};if(!response.ok){feedRef.current=null;setFeed(null);setPreview(null);setSelected({});throw new Error(body.error||'Este enlace ya no está disponible.');}
   if(controller.signal.aborted)return;const next=body as Feed;if(page&&feedRef.current?.folder.id===next.folder.id){const seen=new Set<string>();next.items=[...feedRef.current.items,...next.items].filter(item=>!seen.has(item.id)&&!!seen.add(item.id));}feedRef.current=next;setFeed(next);
  }catch(e){if(!controller.signal.aborted)setError(e instanceof Error?e.message:'No pudimos abrir esta carpeta.');}finally{if(!controller.signal.aborted)setLoading(false);}})();return()=>controller.abort();
 },[base,folder,page,token]);
 // Revalidate an open share too. A revoked link must retire an already-open
 // gallery rather than leave its images or video visible indefinitely.
 useEffect(()=>{if(!feed)return;const check=async()=>{try{const r=await fetch(base+'&folder='+encodeURIComponent(feed.folder.id),{credentials:'omit',cache:'no-store',referrerPolicy:'no-referrer'});if([403,404,410].includes(r.status)){retire();}}catch{/* A transient network loss does not authorize new content. */}};const timer=setInterval(()=>void check(),30000);const visible=()=>{if(document.visibilityState==='visible')void check();};document.addEventListener('visibilitychange',visible);return()=>{clearInterval(timer);document.removeEventListener('visibilitychange',visible);};},[base,feed?.folder.id,retire]);
 function open(id:string){clearHold();setPreview(null);setPage('');setFolder(id);setFeed(null);feedRef.current=null;setSelected({});setSelecting(false);setDownloadNotice('');}
 function toggle(item:MediaItem){setSelecting(true);setSelected(previous=>{const next={...previous};if(item.id in next)delete next[item.id];else next[item.id]=item.modifiedAt;return next;});}
 function beginPress(event:PointerEvent,item:MediaItem){clearHold();heldClick.current='';touchPress.current=event.pointerType==='touch'||event.pointerType==='pen';if(!touchPress.current||selecting||!event.isPrimary)return;press.current={x:event.clientX,y:event.clientY};hold.current=setTimeout(()=>{heldClick.current=item.id;toggle(item);clearHold();},450);}
 const selection=Object.entries(selected).map(([id,revision])=>({id,revision})),files=feed?.items.filter(item=>item.kind!=='folder')||[];
 return <main className="jac-shared"><header><span>JAC MUSIC</span><h1>{feed?.folder.name||'Carpeta compartida'}</h1><p>Fotos y videos compartidos contigo</p>{token&&<a href={'jacnomina://compartir/'+encodeURIComponent(token)}>Abrir en la app JAC</a>}</header>
 {error&&<p role="alert">{error}</p>}{loading&&<p role="status">Abriendo carpeta…</p>}
 {feed&&<><nav aria-label="Carpetas">{feed.breadcrumbs.map(item=><button key={item.id} onClick={()=>open(item.id)} disabled={loading}>{item.name}</button>)}</nav>
 <section className="jac-shared-downloads" aria-label="Descargar archivos">
 <div className="jac-shared-download-heading"><div><h2>Guarda tus recuerdos</h2><p>Descarga un ZIP con los archivos completos. Las opciones de toda la carpeta incluyen sus subcarpetas.</p></div><button type="button" className="jac-shared-select-toggle" aria-pressed={selecting} disabled={!files.length||loading} onClick={()=>{setSelecting(value=>!value);setSelected({});}}>{selecting?<X/>:<CheckSquare/>}{selecting?'Terminar selección':'Seleccionar archivos'}</button></div>
 {selecting&&<div className="jac-shared-selection" role="group" aria-label="Selección de archivos"><strong aria-live="polite">{selection.length} {selection.length===1?'seleccionado':'seleccionados'}</strong><button type="button" onClick={()=>setSelected(previous=>({...previous,...Object.fromEntries(files.map(item=>[item.id,item.modifiedAt]))}))}>Seleccionar visibles</button><button type="button" disabled={!selection.length} onClick={()=>setSelected({})}>Quitar selección</button></div>}
 <form action="/api/media/shared/download" method="post" target="_blank" rel="noreferrer" onSubmit={()=>setDownloadNotice('Descarga solicitada. Revisa las descargas de tu navegador.')}>
 <input type="hidden" name="token" value={token}/><input type="hidden" name="folder" value={feed.folder.id}/><input type="hidden" name="selection" value={JSON.stringify(selection)}/>
 {selecting&&<button className="jac-shared-primary" name="mode" value="selected" disabled={!selection.length||loading}><Download/>Descargar selección ({selection.length})</button>}
 <button name="mode" value="photos" disabled={loading}><ImageIcon/>Descargar todas las fotos</button><button name="mode" value="all" disabled={loading}><Download/>Descargar todas las fotos y videos</button></form>
 {downloadNotice&&<p role="status">{downloadNotice}</p>}
 </section>
 <div className={'jac-shared-grid'+(selecting?' is-selecting':'')}>{feed.items.map(item=>item.kind==='folder'?<button key={item.id} onClick={()=>open(item.id)} className="jac-shared-folder"><Folder/><span>{item.name}</span></button>:<article key={item.id} className={'jac-shared-file'+(item.id in selected?' is-selected':'')} onPointerDown={event=>beginPress(event,item)} onPointerMove={event=>{const start=press.current;if(start&&(Math.abs(event.clientX-start.x)>10||Math.abs(event.clientY-start.y)>10))clearHold();}} onPointerUp={clearHold} onPointerCancel={clearHold} onPointerLeave={clearHold} onContextMenu={event=>{if(touchPress.current)event.preventDefault();}}><button className="jac-shared-file-open" onClick={event=>{if(heldClick.current===item.id){heldClick.current='';event.preventDefault();return;}selecting?toggle(item):setPreview(item);}} aria-label={(selecting?'Seleccionar ':'Abrir ')+item.name}><span className="jac-shared-thumb">{item.thumbnailAvailable?<img src={file(item,true)} alt="" draggable={false} loading="lazy" decoding="async" referrerPolicy="no-referrer"/>:item.kind==='video'?<Video/>:<ImageIcon/>}</span><strong>{item.name}</strong>{item.kind==='video'&&<small>Video</small>}</button><label className="jac-shared-checkbox"><input type="checkbox" checked={item.id in selected} aria-label={'Seleccionar '+item.name} onChange={()=>toggle(item)}/><Check aria-hidden="true"/></label></article>)}</div>
 {!feed.items.length&&!loading&&<p>Esta carpeta está vacía.</p>}{feed.nextPageToken&&<button disabled={loading} onClick={()=>setPage(feed.nextPageToken)}>Cargar más</button>}
 <footer>Enlace disponible hasta {new Date(feed.expiresAt).toLocaleDateString('es-CO')}.</footer></>}
 {preview&&feed&&<SharedViewer key={preview.id} token={token} initial={preview} feed={feed} onPage={appendPage} onRevoked={retire} onClose={()=>setPreview(null)}/>}
 </main>;
}
