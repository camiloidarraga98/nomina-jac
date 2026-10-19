'use client';
import {useEffect,useRef,useState} from 'react';
import {ArrowLeft,ArrowDownToLine,Check,ChevronRight,CircleAlert,Flame,Headphones,LoaderCircle,Mic2,Music2,Pause,Play,Search,SkipBack,SkipForward,SlidersHorizontal,Trash2,Upload,X} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {Input} from '@/components/ui/input';
import {Dialog,DialogContent,DialogDescription,DialogTitle} from '@/components/ui/dialog';
import {musicSections,musicSearch,musicOrder,type MusicLibrary,type MusicTrack,type MusicSection,audioType,MUSIC_CHUNK} from '@/lib/music-core';
import {musicOffline,clearMusicOffline} from '@/lib/music-offline';
import './music.css';
const icons={flame:Flame,mic:Mic2,headphones:Headphones,sliders:SlidersHorizontal};
const time=(n:number)=>Number.isFinite(n)?`${Math.floor(n/60)}:${String(Math.floor(n%60)).padStart(2,'0')}`:'0:00';
type MusicPlan={offset:number;ready:boolean;chunkSize:number};
async function json<T=Record<string,unknown>>(path:string,init?:RequestInit):Promise<T>{const r=await fetch(path,{...init,credentials:'same-origin',cache:'no-store'});if([401,403].includes(r.status))await clearMusicOffline().catch(()=>{});const b=await r.json() as {error?:string};if(!r.ok)throw Object.assign(new Error(b.error||'No se pudo completar la operación.'),{status:r.status});return b as T;}
const command=(body:unknown,signal?:AbortSignal)=>json<MusicPlan>('/api/music/upload',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal});
type ImportFile={id:string;file:File;state:'pending'|'uploading'|'confirming'|'complete'|'error';loaded:number;message?:string};
const bytes=(n:number)=>n<1024*1024?`${(n/1024).toLocaleString('es-CO',{maximumFractionDigits:0})} KB`:`${(n/1024/1024).toLocaleString('es-CO',{maximumFractionDigits:1})} MB`;
const filePercent=(item:ImportFile)=>item.state==='complete'?100:Math.min(99,Math.floor(item.loaded/Math.max(1,item.file.size)*100));
// XHR exposes bytes sent within each block; fetch only reports the final response.
function sendBlock(id:string,offset:number,body:Blob,signal:AbortSignal,onProgress:(sent:number)=>void):Promise<MusicPlan>{
 return new Promise((resolve,reject)=>{
  const xhr=new XMLHttpRequest(),abort=()=>xhr.abort();
  const fail=(message:string,status?:number)=>reject(Object.assign(new Error(message),{status}));
  const cleanup=()=>signal.removeEventListener('abort',abort);
  xhr.open('PUT','/api/music/upload?'+new URLSearchParams({id,offset:String(offset)}));
  xhr.setRequestHeader('Content-Type','application/octet-stream');xhr.withCredentials=true;
  xhr.upload.onprogress=e=>onProgress(Math.min(body.size,e.loaded));
  xhr.onload=()=>{cleanup();void(async()=>{
   if([401,403].includes(xhr.status))await clearMusicOffline().catch(()=>{});
   let result:MusicPlan&{error?:string};try{result=JSON.parse(xhr.responseText);}catch{fail('No se recibió la respuesta de subida. Puedes reintentar.',xhr.status);return;}
   if(xhr.status<200||xhr.status>=300){fail(result.error||'No se pudo subir este audio.',xhr.status);return;}
   resolve(result);
  })();};
  xhr.onerror=()=>{cleanup();fail('Se interrumpió la conexión. Puedes reintentar los pendientes.');};
  xhr.onabort=()=>{cleanup();reject(new DOMException('Subida interrumpida.','AbortError'));};
  if(signal.aborted){reject(new DOMException('Subida interrumpida.','AbortError'));return;}
  signal.addEventListener('abort',abort,{once:true});xhr.send(body);
 });
}
export default function MusicPanel({active}:{active:boolean}){
 const [library,setLibrary]=useState<MusicLibrary|null>(null),[section,setSection]=useState<MusicSection|null>(null),[search,setSearch]=useState(''),[error,setError]=useState(''),[notice,setNotice]=useState(''),[saved,setSaved]=useState<Set<string>>(new Set()),[offline,setOffline]=useState(false),[loading,setLoading]=useState(true),[imports,setImports]=useState<ImportFile[]>([]),[destination,setDestination]=useState<MusicSection>('warmup'),[uploading,setUploading]=useState(false),[uploadMessage,setUploadMessage]=useState(''),[progress,setProgress]=useState(''),[downloading,setDownloading]=useState(false),[deleting,setDeleting]=useState<MusicTrack|null>(null),[current,setCurrent]=useState<MusicTrack|null>(null),[playing,setPlaying]=useState(false),[elapsed,setElapsed]=useState(0),[duration,setDuration]=useState(0);
 const loadGeneration=useRef(0),audio=useRef<HTMLAudioElement>(null),queue=useRef<MusicTrack[]>([]),position=useRef(-1),generation=useRef(0),downloadAbort=useRef<AbortController|null>(null),uploadAbort=useRef<AbortController|null>(null),input=useRef<HTMLInputElement>(null),startRef=useRef<(track:MusicTrack)=>Promise<void>>(async()=>{}),importSection=useRef<MusicSection|null>(null);
 const stop=()=>{generation.current++;audio.current?.pause();audio.current?.removeAttribute('src');audio.current?.load();queue.current=[];position.current=-1;setCurrent(null);setPlaying(false);if('mediaSession'in navigator){navigator.mediaSession.metadata=null;navigator.mediaSession.playbackState='none';}};
 async function load(){const own=++loadGeneration.current;setError('');try{const data=await json<MusicLibrary>('/api/music');if(own!==loadGeneration.current)return;setLibrary(data);setOffline(false);try{const cache=await musicOffline();if(own!==loadGeneration.current)return;await cache.connect(data);}catch{if(own===loadGeneration.current)setNotice('Puedes escuchar en línea. Este navegador no pudo preparar el almacenamiento sin conexión.');}}catch(e){if(own!==loadGeneration.current)return;if(e instanceof TypeError){try{const cache=await musicOffline(),tracks=await cache.catalog();if(own!==loadGeneration.current)return;setLibrary({tracks,canUpload:false,canDelete:false,scope:'',key:''});setOffline(true);}catch{setError('Conéctate a internet para abrir Música. No se pudo leer una copia local.');}}else{setError(e instanceof Error?e.message:'No se pudo cargar Música.');}}finally{if(own===loadGeneration.current)setLoading(false);}}
 useEffect(()=>{let live=true;const revoked=()=>{loadGeneration.current++;stop();downloadAbort.current?.abort();uploadAbort.current?.abort();setLibrary(null);setSaved(new Set());setError('Tu sesión o tus permisos cambiaron. Vuelve a iniciar sesión.');};const storage=(e:StorageEvent)=>{if(e.key==='jac.music.revoked')revoked();};const update=()=>{void musicOffline().then(c=>c.saved()).then(items=>{if(live)setSaved(new Set(items.map(i=>i.id+':'+i.revision)));}).catch(()=>{});};update();window.addEventListener('jac-music-offline-changed',update);window.addEventListener('jac-music-stop',revoked);window.addEventListener('storage',storage);window.addEventListener('online',load);void load();void navigator.serviceWorker?.register('/jac-push-sw.js',{scope:'/',updateViaCache:'none'}).catch(()=>{});return()=>{live=false;loadGeneration.current++;generation.current++;downloadAbort.current?.abort();uploadAbort.current?.abort();audio.current?.pause();window.removeEventListener('jac-music-offline-changed',update);window.removeEventListener('jac-music-stop',revoked);window.removeEventListener('storage',storage);window.removeEventListener('online',load);};},[]);
 async function start(track:MusicTrack){const own=++generation.current;setError('');setCurrent(track);setElapsed(0);setDuration(0);try{const cache=await musicOffline().catch(()=>undefined),record=cache?(await cache.saved().catch(()=>[])).find(t=>t.id===track.id&&t.revision===track.revision):undefined;let url:string;if(record&&cache){if(!navigator.serviceWorker?.controller)throw new Error('Vuelve a abrir Música para activar la reproducción sin conexión.');url=cache.url(record.scope,track);}else{if(!navigator.onLine)throw new Error('Descarga este audio antes de escucharlo sin conexión.');url=(await json<{url:string}>('/api/music?'+new URLSearchParams({play:'1',id:track.id,revision:track.revision}))).url;}
 if(own!==generation.current||!audio.current)return;audio.current.src=url;await audio.current.play();if(own!==generation.current)return;if('mediaSession'in navigator)navigator.mediaSession.metadata=new MediaMetadata({title:track.title,artist:'Jhon Alex Castaño',album:musicSections.find(s=>s.id===track.section)?.title});}catch(e){if(own===generation.current){setPlaying(false);setError(e instanceof Error?e.message:'No se pudo reproducir el audio.');}}}
 startRef.current=start;
 function next(){if(position.current+1<queue.current.length){position.current++;void startRef.current(queue.current[position.current]);}}
 function previous(){if(audio.current&&audio.current.currentTime>3){audio.current.currentTime=0;}else if(position.current>0){position.current--;void startRef.current(queue.current[position.current]);}}
 useEffect(()=>{if(!('mediaSession'in navigator))return;const handlers:Partial<Record<MediaSessionAction,MediaSessionActionHandler>>={play:()=>{void audio.current?.play();},pause:()=>audio.current?.pause(),nexttrack:next,previoustrack:previous,seekto:e=>{if(audio.current&&e.seekTime!==undefined)audio.current.currentTime=e.seekTime;},seekbackward:e=>{if(audio.current)audio.current.currentTime=Math.max(0,audio.current.currentTime-(e.seekOffset||10));},seekforward:e=>{if(audio.current)audio.current.currentTime=Math.min(audio.current.duration,audio.current.currentTime+(e.seekOffset||10));}};for(const [name,handler]of Object.entries(handlers))try{navigator.mediaSession.setActionHandler(name as MediaSessionAction,handler!);}catch{}return()=>{for(const name of Object.keys(handlers))try{navigator.mediaSession.setActionHandler(name as MediaSessionAction,null);}catch{}};},[]);
 const tracks=(library?.tracks||[]).filter(t=>(!section||t.section===section)&&musicSearch(t.title).includes(musicSearch(search))).sort(musicOrder);
 function choose(id:MusicSection|null){setSection(id);setSearch('');setNotice('');}
 function pick(files:FileList|File[]){
  if(uploadAbort.current)return;
  try{const values=Array.from(files);for(const f of values)audioType(f.name);setImports(values.map(file=>({id:crypto.randomUUID(),file,state:'pending',loaded:0})));setDestination(section||'warmup');importSection.current=null;setError('');setUploadMessage('');setNotice('');}catch(e){setError((e as Error).message);}
 }
 function closeImports(){if(uploadAbort.current)return;setImports([]);importSection.current=null;setUploadMessage('');}
 function updateImport(id:string,change:Partial<ImportFile>){setImports(old=>old.map(item=>item.id===id?{...item,...change}:item));}
 async function upload(){
  const selected=imports.filter(item=>item.state!=='complete');
  if(!selected.length||uploadAbort.current)return;
  setUploading(true);setUploadMessage('');
  const controller=new AbortController();uploadAbort.current=controller;
  const target=importSection.current||destination;importSection.current=target;
  setImports(old=>old.map(item=>item.state==='complete'?item:{...item,state:'pending',message:undefined}));
  let done=0,failures=0;
  try{
   for(const entry of selected){
    try{
     controller.signal.throwIfAborted();updateImport(entry.id,{state:'uploading',message:undefined});
     let plan=await command({action:'start',id:entry.id,section:target,filename:entry.file.name,size:entry.file.size},controller.signal);
     updateImport(entry.id,{loaded:plan.offset});
     while(!plan.ready&&plan.offset<entry.file.size){
      controller.signal.throwIfAborted();
      const offset=plan.offset,b=entry.file.slice(offset,offset+MUSIC_CHUNK);
      plan=await sendBlock(entry.id,offset,b,controller.signal,sent=>updateImport(entry.id,{loaded:offset+sent}));
      updateImport(entry.id,{loaded:plan.offset});
     }
     if(!plan.ready){updateImport(entry.id,{state:'confirming'});await command({action:'complete',id:entry.id},controller.signal);}
     controller.signal.throwIfAborted();done++;updateImport(entry.id,{state:'complete',loaded:entry.file.size});
    }catch(e){
     const failure=e as Error&{status?:number};failures++;
     updateImport(entry.id,{state:'error',message:failure.name==='AbortError'?'La subida se interrumpió. Puedes reintentar.':failure.message});
     // Rejected files do not starve the batch; connection/auth/service failures stop writes.
     if(![400,413,415,422].includes(failure.status||0))break;
    }
   }
   if(done&&!controller.signal.aborted){setNotice(`${done} ${done===1?'audio subido':'audios subidos'} a ${musicSections.find(s=>s.id===target)?.title}.`);await load();}
   if(failures)setUploadMessage(`Se subieron ${done} de ${selected.length} audios en este intento. Quedan ${selected.length-done} pendientes; puedes reintentarlos o quitarlos de la lista.`);
  }finally{uploadAbort.current=null;setUploading(false);}
 }
 const totalBytes=imports.reduce((n,item)=>n+item.file.size,0);
 const sentBytes=imports.reduce((n,item)=>n+item.loaded,0);
 const completed=imports.filter(item=>item.state==='complete').length;
 const pending=imports.length-completed,hasUploadErrors=imports.some(item=>item.state==='error');
 const overallPercent=imports.length&&completed===imports.length?100:Math.min(99,Math.floor(imports.reduce((n,item)=>n+item.file.size*filePercent(item)/100,0)/Math.max(1,totalBytes)*100));
 const activeImport=imports.find(item=>item.state==='uploading'||item.state==='confirming');
 async function download(items:MusicTrack[]){if(downloading)return;setDownloading(true);setError('');downloadAbort.current=new AbortController();try{const cache=await musicOffline();for(let n=0;n<items.length;n++){setProgress(`Guardando ${n+1}/${items.length} · ${items[n].title}`);await cache.download(items[n],p=>setProgress(`Guardando ${n+1}/${items.length} · ${Math.round(p*100)}%`),downloadAbort.current.signal);}void navigator.storage?.persist?.();setNotice(items.length===1?'Audio disponible sin conexión.':'Sección disponible sin conexión.');}catch(e){if((e as Error).name!=='AbortError')setError((e as Error).message);}finally{downloadAbort.current=null;setDownloading(false);setProgress('');}}
 return <><audio ref={audio} onPlay={()=>{setPlaying(true);if('mediaSession'in navigator)navigator.mediaSession.playbackState='playing';}} onPause={()=>{setPlaying(false);if('mediaSession'in navigator)navigator.mediaSession.playbackState='paused';}} onTimeUpdate={()=>{const a=audio.current;if(a){setElapsed(a.currentTime);setDuration(Number.isFinite(a.duration)?a.duration:0);if('mediaSession'in navigator&&Number.isFinite(a.duration)&&a.duration>0)try{navigator.mediaSession.setPositionState({duration:a.duration,position:Math.min(a.currentTime,a.duration),playbackRate:a.playbackRate});}catch{}}}} onEnded={next} onError={()=>{setPlaying(false);setError('No se pudo reproducir este audio. Revisa la conexión o vuelve a descargarlo.');}} preload="metadata"/>
 <section className="music-workspace" hidden={!active} onDragOver={e=>{if(library?.canUpload)e.preventDefault();}} onDrop={e=>{if(library?.canUpload){e.preventDefault();pick(e.dataTransfer.files);}}}>
 <div className="music-toolbar">{section&&<Button variant="ghost" onClick={()=>choose(null)}><ArrowLeft/>Música</Button>}<label className="music-search"><Search size={19}/><Input type="search" aria-label={section?'Buscar en '+musicSections.find(s=>s.id===section)?.title:'Buscar en toda Música'} placeholder={section?'Buscar en esta sección…':'Buscar en toda Música…'} value={search} onChange={e=>setSearch(e.target.value)}/></label>{library?.canUpload&&<Button onClick={()=>input.current?.click()}><Upload/>Subir audios</Button>}<input hidden ref={input} type="file" multiple accept=".mp3,.m4a,.aac,.wav,audio/mpeg,audio/mp4,audio/aac,audio/wav" onChange={e=>{if(e.target.files)pick(e.target.files);e.target.value='';}}/></div>
 {error&&<p className="message error" role="alert">{error}</p>}{notice&&<p className="message success" role="status">{notice}</p>}{progress&&<div className="music-progress" role="status">{progress}{downloading&&<Button variant="ghost" onClick={()=>downloadAbort.current?.abort()}>Cancelar</Button>}</div>}{offline&&<p className="music-hint">Sin conexión · Puedes escuchar los audios descargados.</p>}
 {!section&&!search&&<div className="music-sections">{musicSections.map(s=>{const Icon=icons[s.icon],items=library?.tracks.filter(t=>t.section===s.id)||[];return <button key={s.id} className="music-section" onClick={()=>choose(s.id)}><span className={'music-section-art '+s.id}><Icon size={27}/></span><span className="music-section-description"><strong>{s.title}</strong><small>{s.description}</small><small>{items.length} audios</small></span><ChevronRight/></button>;})}</div>}
 {(section||search)&&<><div className="music-list-heading"><div><h2>{section?musicSections.find(s=>s.id===section)?.title:'Resultados en Música'}</h2><p>{tracks.length} audios{section==='tracks'?' · Orden alfabético':''}</p></div>{section&&!!library?.tracks.some(t=>t.section===section)&&<Button variant="outline" disabled={downloading||offline} onClick={()=>download(library.tracks.filter(t=>t.section===section))}><ArrowDownToLine/>Descargar sección</Button>}</div><div className="music-tracks" role="list">{tracks.map((t,i)=><div role="listitem" key={t.id} className={'music-track '+(current?.id===t.id?'is-current':'')}><button className="music-play" aria-label={'Reproducir '+t.title} onClick={()=>{queue.current=tracks;position.current=i;void start(t);}}>{current?.id===t.id&&playing?<span className="music-equalizer">▂▆▃</span>:<Play size={19}/>}</button><div className="music-track-title"><strong>{t.title}</strong><small>{!section?musicSections.find(s=>s.id===t.section)?.title+' · ':''}{t.filename.split('.').at(-1)?.toUpperCase()} · {(t.size/1024/1024).toFixed(1)} MB</small></div><div className="music-track-actions">{saved.has(t.id+':'+t.revision)?<button aria-label={'Quitar descarga de '+t.title} title="Disponible sin conexión. Quitar descarga" onClick={async()=>{if(current?.id===t.id)stop();await(await musicOffline()).remove(t.id);}}><Check size={20}/></button>:<button disabled={downloading||offline} aria-label={'Descargar '+t.title+' sin conexión'} title="Descargar sin conexión" onClick={()=>download([t])}><ArrowDownToLine size={20}/></button>}<a title="Exportar archivo de audio" aria-label={'Exportar '+t.title} href={'/api/music/file?'+new URLSearchParams({id:t.id,revision:t.revision,download:'1'})}><Music2 size={19}/></a>{library?.canDelete&&<button aria-label={'Eliminar '+t.title} onClick={()=>setDeleting(t)}><Trash2 size={18}/></button>}</div></div>)}</div>{!loading&&!tracks.length&&<div className="music-empty"><Headphones size={35}/><h3>{search?'No encontramos ese audio':'Esta lista está lista para escuchar'}</h3><p>{search?'Prueba con otro nombre.':library?.canUpload?'Sube o arrastra los primeros audios aquí.':'Los audios aparecerán cuando el equipo los suba.'}</p></div>}</>}
 {loading&&<p role="status">Cargando Música…</p>}<div className="music-offline-link"><a href="/musica-offline.html"><ArrowDownToLine size={17}/>Mis audios sin conexión</a><small>Las descargas se guardan en este dispositivo.</small></div>
 </section>
 {current&&<div className="music-player" aria-label="Reproductor de Música"><div className="music-now-playing"><span className="music-player-art"><Music2/></span><div><strong>{current.title}</strong><small>{musicSections.find(s=>s.id===current.section)?.title}</small></div></div><div className="music-player-controls"><div><button onClick={previous} aria-label="Audio anterior"><SkipBack size={21}/></button><button className="music-main-play" onClick={()=>{if(playing)audio.current?.pause();else void audio.current?.play().catch(()=>setError('Pulsa reproducir para continuar.'));}} aria-label={playing?'Pausar música':'Reproducir música'}>{playing?<Pause/>:<Play/>}</button><button onClick={next} aria-label="Siguiente audio"><SkipForward size={21}/></button></div><label><span>{time(elapsed)}</span><input aria-label="Posición del audio" type="range" min={0} max={duration||1} value={Math.min(elapsed,duration||0)} step="0.1" onChange={e=>{if(audio.current)audio.current.currentTime=Number(e.target.value);}}/><span>{time(duration)}</span></label></div><button onClick={stop} aria-label="Cerrar reproductor"><X size={21}/></button></div>}
 <Dialog open={!!imports.length} onOpenChange={open=>{if(!open)closeImports();}}>
  <DialogContent className="music-upload-dialog" showCloseButton={!uploading}>
   <header className="music-upload-heading"><span className="music-upload-art"><Upload size={24}/></span><div><DialogTitle>Subir audios</DialogTitle><DialogDescription>Tu música, lista para el equipo.</DialogDescription></div></header>
   <label className="music-destination">Guardar en<select aria-label="Sección de destino" value={destination} disabled={uploading||importSection.current!==null} onChange={e=>setDestination(e.target.value as MusicSection)}>{musicSections.map(s=><option key={s.id} value={s.id}>{s.title}</option>)}</select></label>
   <div className={'music-upload-overview '+(!pending?'is-complete':'')}>
    <div className="music-upload-total"><div><strong>{!pending?'Subida completada':uploading?'Subiendo tu música':hasUploadErrors?'Hay audios pendientes':'Listo para subir'}</strong><small>{imports.length} {imports.length===1?'audio':'audios'} · {bytes(totalBytes)}</small></div><span>{overallPercent}%</span></div>
    <div className="music-upload-bar" role="progressbar" aria-label="Progreso general de subida" aria-valuemin={0} aria-valuemax={100} aria-valuenow={overallPercent} aria-valuetext={`${overallPercent}%, ${completed} de ${imports.length} audios completados`}><span style={{width:overallPercent+'%'}}/></div>
    <div className="music-upload-count"><span>{completed} de {imports.length} completados</span><span>{bytes(sentBytes)} transferidos</span></div>
    <p className="music-upload-current" role="status">{activeImport?`${activeImport.state==='confirming'?'Confirmando':'Subiendo'}: ${activeImport.file.name}`:!pending?'Todos los audios están disponibles en Música.':hasUploadErrors?'Revisa los archivos marcados y reintenta los pendientes.':'Elige la sección y revisa los archivos antes de empezar.'}</p>
   </div>
   <div className="music-upload-list-heading"><strong>Archivos del lote</strong><span>{pending?`${pending} pendientes`:'Todo listo'}</span></div>
   <ul className="music-imports" aria-label="Archivos del lote">{imports.map(item=><li key={item.id} data-state={item.state}>
    <span className="music-import-icon" aria-hidden="true">{item.state==='complete'?<Check size={20}/>:item.state==='error'?<CircleAlert size={20}/>:item.state==='uploading'||item.state==='confirming'?<LoaderCircle className="music-upload-spinner" size={20}/>:<Music2 size={20}/>}</span>
    <div className="music-import-detail"><strong>{item.file.name}</strong><div className="music-import-meta"><span>{bytes(item.file.size)}</span><span>{item.state==='complete'?'Completado':item.state==='error'?'Necesita reintento':item.state==='confirming'?'Confirmando…':item.state==='uploading'?`Subiendo · ${filePercent(item)}%`:'En espera'}</span></div>{(item.state==='uploading'||item.state==='confirming')&&<div className="music-import-bar"><span style={{width:filePercent(item)+'%'}}/></div>}{item.message&&<p className="music-import-error">{item.message}</p>}</div>
    {item.state!=='complete'&&<button type="button" disabled={uploading} aria-label={'Quitar '+item.file.name+' del lote'} onClick={()=>{setImports(old=>old.filter(f=>f.id!==item.id));setUploadMessage('');if(imports.length===1)importSection.current=null;}}><X size={17}/></button>}
   </li>)}</ul>
   {uploadMessage&&<p className="music-upload-alert" role="alert">{uploadMessage}</p>}
   <footer className="music-upload-footer"><p>{uploading?'Mantén esta pestaña abierta hasta terminar.':'Puedes seguir escuchando música mientras subes tus audios.'}</p><div>{!uploading&&<Button variant={pending?'outline':'default'} onClick={closeImports}>{pending?'Cerrar':'Listo'}</Button>}{pending>0&&<Button disabled={uploading} onClick={upload}>{uploading?<><LoaderCircle className="music-upload-spinner" size={18}/>Subiendo…</>:hasUploadErrors?'Reintentar pendientes':<><Upload size={18}/>Subir audios</>}</Button>}</div></footer>
  </DialogContent>
 </Dialog>
 <Dialog open={!!deleting} onOpenChange={open=>{if(!open)setDeleting(null);}}><DialogContent className="payroll-dialog"><DialogTitle>Eliminar audio</DialogTitle><DialogDescription>Se eliminará «{deleting?.title}» de Música y dejará de estar disponible para el equipo.</DialogDescription><Button className="danger" onClick={async()=>{if(!deleting)return;try{await json('/api/music',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'delete',id:deleting.id,revision:deleting.revision})});if(current?.id===deleting.id)stop();await(await musicOffline()).remove(deleting.id);setDeleting(null);await load();}catch(e){setError((e as Error).message);setDeleting(null);}}}>Eliminar audio</Button></DialogContent></Dialog>
 </>;
}
