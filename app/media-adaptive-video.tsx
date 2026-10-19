'use client';
import {useEffect,useRef,useState,type RefObject} from 'react';
import type Hls from 'hls.js';

type Info={ready:boolean;url?:string;status?:string;message?:string;error?:string};
export default function MediaAdaptiveVideo({infoURL,onRevoked,videoRef}:{infoURL:string;onRevoked:()=>void;videoRef?:RefObject<HTMLVideoElement|null>}){
 const own=useRef<HTMLVideoElement|null>(null),[message,setMessage]=useState('Preparando reproducción…'),[retry,setRetry]=useState(0);
 const revoked=useRef(onRevoked);revoked.current=onRevoked;
 useEffect(()=>{
  const controller=new AbortController();let active=true,timer:ReturnType<typeof setTimeout>|undefined,hls:Hls|undefined;
  const video=own.current;if(!video)return;
  const fail=(text:string)=>{if(active)setMessage(text);};
  const load=async()=>{try{
   const response=await fetch(infoURL,{signal:controller.signal,credentials:'same-origin',cache:'no-store',referrerPolicy:'no-referrer'});
   if([401,403,404,410].includes(response.status)){revoked.current();return;}
   const info=await response.json() as Info;if(!response.ok)throw new Error(info.error||'No pudimos abrir el video.');if(!active)return;
   if(!info.ready||!info.url){fail(info.message||'Preparando la versión para reproducción…');timer=setTimeout(()=>void load(),8000);return;}
   const url=new URL(info.url,location.origin);if(url.origin!==location.origin||url.pathname!=='/api/media/playback')throw new Error('La dirección de reproducción no es válida.');
   if(video.canPlayType('application/vnd.apple.mpegurl'))video.src=url.toString();
   else{
    const {default:Player}=await import('hls.js');if(!active)return;
    if(!Player.isSupported())throw new Error('Este navegador no admite reproducción adaptativa. Puedes descargar el archivo.');
    hls=new Player({capLevelToPlayerSize:true,maxBufferLength:20,maxMaxBufferLength:40});
    hls.on(Player.Events.ERROR,(_,data)=>{if(!data.fatal)return;if([401,403,404,410].includes(data.response?.code||0)){revoked.current();return;}hls?.stopLoad();fail('La reproducción se interrumpió. Puedes reintentar.');});
    hls.attachMedia(video);hls.loadSource(url.toString());
   }
   setMessage('');void video.play().catch(()=>{});
  }catch(error){if(active&&!controller.signal.aborted)fail(error instanceof Error?error.message:'No pudimos abrir el video.');}};
  void load();return()=>{active=false;controller.abort();if(timer)clearTimeout(timer);hls?.destroy();video.pause();video.removeAttribute('src');video.load();};
 },[infoURL,retry]);
 return <div style={{width:'100%',height:'100%',minHeight:0,display:'flex',flexDirection:'column',justifyContent:'center'}}>
  <video ref={element=>{own.current=element;if(videoRef)videoRef.current=element;}} controls playsInline preload="metadata" style={{width:'100%',height:message?'calc(100% - 72px)':'100%',minHeight:0,objectFit:'contain'}} onError={()=>setMessage('No pudimos reproducir este video. Puedes reintentar o descargarlo.')}/>
  {message&&<div role="status" style={{padding:12,color:'white',fontSize:13,textAlign:'center'}}>{message} <button type="button" onClick={()=>setRetry(value=>value+1)} style={{marginLeft:8,padding:8,borderRadius:8,color:'#163449',background:'white'}}>Reintentar</button></div>}
 </div>;
}
