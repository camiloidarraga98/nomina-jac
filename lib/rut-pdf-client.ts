import workerURL from 'pdfjs-dist/legacy/build/pdf.worker.min.mjs?url';
import {extractRut,type RutPage,type RutExtraction} from './rut-extract';

export const RUT_MAX_BYTES=10*1024*1024;
const cancelled=()=>new DOMException('Lectura cancelada.','AbortError');
/** Browser-only local text extraction. The selected document is never sent to a server. */
export async function readRutPDF(file:File,signal:AbortSignal,progress?:(page:number,total:number)=>void):Promise<RutExtraction>{
 if(file.size===0||file.size>RUT_MAX_BYTES)throw Error('Selecciona un RUT en PDF de hasta 10 MB.');
 const header=new TextDecoder('latin1').decode(await file.slice(0,1024).arrayBuffer());
 if(!header.includes('%PDF-'))throw Error('El archivo seleccionado no es un PDF.');
 if(signal.aborted)throw cancelled();
 const pdfjs=await import('pdfjs-dist/legacy/build/pdf.mjs');
 if(signal.aborted)throw cancelled();
 // Supplying our own same-origin port avoids a fallback running on the UI thread.
 const port=new Worker(workerURL,{type:'module'});
 let worker:InstanceType<typeof pdfjs.PDFWorker>|undefined,task:ReturnType<typeof pdfjs.getDocument>|undefined,timedOut=false,closed=false,timer:ReturnType<typeof setTimeout>|undefined;
 let rejectStop:(reason:Error)=>void=()=>{};
 const stopped=new Promise<never>((_,reject)=>{rejectStop=reject;});
 const stop=()=>{closed=true;rejectStop(timedOut?Error('La lectura tardó demasiado. Prueba otro PDF del RUT o completa los datos manualmente.'):cancelled());port.terminate();void task?.destroy().catch(()=>{});worker?.destroy();};
 try{
  worker=pdfjs.PDFWorker.create({port,verbosity:0});
  signal.addEventListener('abort',stop,{once:true});
  timer=setTimeout(()=>{timedOut=true;stop();},30000);
  return await Promise.race([stopped,(async()=>{
  const data=new Uint8Array(await file.arrayBuffer());if(signal.aborted||closed)throw cancelled();
  task=pdfjs.getDocument({data,worker,verbosity:0,useWorkerFetch:false,useWasm:false,disableFontFace:true,useSystemFonts:false,enableXfa:false,isOffscreenCanvasSupported:false,isImageDecoderSupported:false,maxImageSize:0,disableAutoFetch:true,disableRange:true,disableStream:true,stopAtErrors:true});
  const pdf=await task.promise;if(pdf.numPages>20)throw Error('Este PDF tiene demasiadas páginas. Selecciona un único RUT de hasta 20 páginas.');
  const pages:RutPage[]=[];let textCount=0;
  for(let number=1;number<=pdf.numPages;number++){
   if(signal.aborted)throw cancelled();progress?.(number,pdf.numPages);
   const page=await pdf.getPage(number),viewport=page.getViewport({scale:1}),text=await page.getTextContent();
   if(text.items.length>15000)throw Error('El documento es demasiado complejo. Usa el PDF original del RUT.');
   const items:RutPage['items']=[];
   for(const item of text.items){if(!('str' in item)||!item.str.trim())continue;
    textCount+=item.str.length;if(textCount>200000)throw Error('El documento contiene demasiado texto. Selecciona un único RUT.');
    const matrix=pdfjs.Util.transform(viewport.transform,item.transform),height=Math.hypot(matrix[2],matrix[3]),ascent=text.styles[item.fontName]?.ascent??.8;
    items.push({text:item.str,x:matrix[4],y:matrix[5]-height*ascent,width:Math.abs(item.width),height});
   }
   pages.push({width:viewport.width,height:viewport.height,items});page.cleanup();
  }
  return extractRut(pages);
 })()]);
 }catch(e){if(signal.aborted)throw cancelled();if(e instanceof Error&&e.name==='PasswordException')throw Error('Este PDF está protegido con contraseña. Selecciona una copia accesible o completa los datos manualmente.');throw e;}
 finally{closed=true;if(timer)clearTimeout(timer);signal.removeEventListener('abort',stop);try{await task?.destroy();}catch{}worker?.destroy();port.terminate();}
}
