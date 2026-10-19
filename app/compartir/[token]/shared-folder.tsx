'use client';
import {useEffect,useRef,useState} from 'react';
import type {MediaItem} from '@/lib/media-core';
import './shared.css';
type Folder={id:string;name:string};
type Feed={folder:Folder;breadcrumbs:Folder[];items:MediaItem[];nextPageToken:string;expiresAt:string};
export default function SharedFolder({token}:{token:string}){
 const [feed,setFeed]=useState<Feed|null>(null),[folder,setFolder]=useState(''),[page,setPage]=useState(''),[error,setError]=useState(''),[loading,setLoading]=useState(false),[preview,setPreview]=useState<MediaItem|null>(null);
 const feedRef=useRef<Feed|null>(null);
 const base='/api/media/shared?token='+encodeURIComponent(token);
 const file=(item:MediaItem,thumbnail=false)=>base+'&id='+encodeURIComponent(item.id)+'&revision='+encodeURIComponent(item.modifiedAt)+(thumbnail?'&thumbnail=1':'');
 useEffect(()=>{const controller=new AbortController();setLoading(true);setError('');
  void(async()=>{try{if(!token)throw new Error('Este enlace no es válido.');const response=await fetch(base+'&folder='+encodeURIComponent(folder)+'&pageToken='+encodeURIComponent(page),{signal:controller.signal,credentials:'omit',cache:'no-store',referrerPolicy:'no-referrer'}),body=await response.json() as Feed & {error?:string};if(!response.ok){feedRef.current=null;setFeed(null);setPreview(null);throw new Error(body.error||'Este enlace ya no está disponible.');}
   if(controller.signal.aborted)return;const next=body as Feed;if(page&&feedRef.current?.folder.id===next.folder.id){const seen=new Set<string>();next.items=[...feedRef.current.items,...next.items].filter(item=>!seen.has(item.id)&&!!seen.add(item.id));}feedRef.current=next;setFeed(next);
  }catch(e){if(!controller.signal.aborted)setError(e instanceof Error?e.message:'No pudimos abrir esta carpeta.');}finally{if(!controller.signal.aborted)setLoading(false);}})();return()=>controller.abort();
 },[base,folder,page,token]);
 // Revalidate an open share too. A revoked link must retire an already-open
 // gallery rather than leave its images or video visible indefinitely.
 useEffect(()=>{if(!feed)return;const check=async()=>{try{const r=await fetch(base+'&folder='+encodeURIComponent(feed.folder.id),{credentials:'omit',cache:'no-store',referrerPolicy:'no-referrer'});if([403,404,410].includes(r.status)){feedRef.current=null;setFeed(null);setPreview(null);setError('Este enlace ya no está disponible.');}}catch{/* A transient network loss does not authorize new content. */}};const timer=setInterval(()=>void check(),30000);const visible=()=>{if(document.visibilityState==='visible')void check();};document.addEventListener('visibilitychange',visible);return()=>{clearInterval(timer);document.removeEventListener('visibilitychange',visible);};},[base,feed?.folder.id]);
 function open(id:string){setPreview(null);setPage('');setFolder(id);setFeed(null);feedRef.current=null;}
 return <main className="jac-shared"><header><span>JAC MUSIC</span><h1>{feed?.folder.name||'Carpeta compartida'}</h1><p>Fotos y videos compartidos contigo</p>{token&&<a href={'jacnomina://compartir/'+encodeURIComponent(token)}>Abrir en la app JAC</a>}</header>
 {error&&<p role="alert">{error}</p>}{loading&&<p role="status">Abriendo carpeta…</p>}
 {feed&&<><nav aria-label="Carpetas">{feed.breadcrumbs.map(item=><button key={item.id} onClick={()=>open(item.id)} disabled={loading}>{item.name}</button>)}</nav>
 <div className="jac-shared-grid">{feed.items.map(item=>item.kind==='folder'?<button key={item.id} onClick={()=>open(item.id)} className="jac-shared-folder">📁 {item.name}</button>:<button key={item.id} onClick={()=>setPreview(item)}><span className="jac-shared-thumb">{item.thumbnailAvailable?<img src={file(item,true)} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer"/>:item.kind==='video'?'▶':'▧'}</span><strong>{item.name}</strong>{item.kind==='video'&&<small>Video</small>}</button>)}</div>
 {!feed.items.length&&!loading&&<p>Esta carpeta está vacía.</p>}{feed.nextPageToken&&<button disabled={loading} onClick={()=>setPage(feed.nextPageToken)}>Cargar más</button>}
 <footer>Enlace disponible hasta {new Date(feed.expiresAt).toLocaleDateString('es-CO')}.</footer></>}
 {preview&&<div className="jac-shared-modal" role="dialog" aria-modal="true" aria-label={preview.name}><button onClick={()=>setPreview(null)}>Cerrar</button><h2>{preview.name}</h2>{preview.kind==='video'?<video key={preview.id} controls playsInline preload="metadata" src={file(preview)}/>:<img src={file(preview)} alt={preview.name} referrerPolicy="no-referrer"/>}<a href={file(preview)+'&download=1'} download={preview.name} referrerPolicy="no-referrer">Descargar archivo</a></div>}
 </main>;
}
