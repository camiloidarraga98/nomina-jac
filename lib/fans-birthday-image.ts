import {env} from 'cloudflare:workers';
import render from '../design/fans/cumpleanos/render-v4.json';
import {decodePng,encodePng,type PngImage} from './fans-png';
import {isBirthdayHEIC} from './fans-image-format';

type Images={info(stream:ReadableStream):Promise<{width?:number;height?:number}>;input(stream:ReadableStream):{transform(options:Record<string,unknown>):{output(options:{format:string;quality:number}):Promise<{response():Response}>}}};
type ImageEnv={OPENAI_API_KEY?:string;ASSETS?:{fetch(request:Request):Promise<Response>};IMAGES?:Images};
const bindings=()=>env as unknown as ImageEnv;
export class BirthdayImageFailure extends Error{
 constructor(message:string,readonly paidAttempt=false,readonly status=502){super(message);}
}
const PROVIDER='https://api.openai.com/v1/images/edits';
// A 1024x1280 RGBA PNG has ~5 MiB of raw pixels; its ordinary stored-deflate
// PNG plus base64 fits below 7 MiB. Bound the complete JSON envelope at 8 MiB
// rather than retaining ten independent 16 MiB responses in the isolate.
const PROVIDER_RESPONSE_LIMIT=8*1024*1024;
// Provider requests remain concurrent. Only response materialization and the
// CPU/memory-heavy decode/resize/encode stages share this one-isolate permit.
let responseProcessing:Promise<void>=Promise.resolve();
async function acquireResponseProcessing(){
 const preceding=responseProcessing;let release!:()=>void;
 responseProcessing=new Promise<void>(resolve=>{release=resolve;});
 await preceding;return release;
}
// Pin the quality-oriented editor so an alias update cannot silently change the pilot.
// GPT Image 2.5 uses high-fidelity references without the legacy input_fidelity field.
export const BIRTHDAY_MODEL='gpt-image-2.5-sunburst-2026-09-08';
export const BIRTHDAY_PROMPT=`Edit the complete birthday photograph in image 1 into one coherent, realistic photograph. Use no mask, cutout, patch border or artificially clipped overlap. Image 1 is the approved scene and supplies its composition, perspective, lighting and the artist Jhon Alex on the LEFT. Replace ONLY the existing companion on the RIGHT with the adult from image 2, which is the ONLY identity and wardrobe reference for that new companion. Reconstruct their entire person naturally in the right-hand seat: head, hair, neck, shoulders, torso, arms, hands, clothing and visible legs. Remove all remnants of the previous companion, including their face, black shirt, hair, birthday hat, hands, glass and legs. This is a complete-person reconstruction, not a face swap or a cutout pasted onto an existing body.
Preserve the fan's recognizable facial features and proportions, complexion, hairstyle, visible body proportions, glasses and other visible accessories. Respect their appearance, whether a woman or a man. Preserve the actual visible outfit from image 2: garment type, neckline, sleeves, colors, patterns and fit. Re-create its fabric and folds for the new seated pose; do not copy the source pose, source background or source lighting. Do not force a black shirt, trousers, short hair or a masculine body onto the fan. Long hair, dresses and different body shapes may occupy the surrounding background and chair. If only a face or upper body is visible in image 2, complete the unseen parts plausibly and consistently with what IS visible.
Seat the fan beside Jhon Alex at the same distance from the camera and the same eye-level perspective. Use realistic head-to-body scale, a coherent neck and shoulders, a relaxed camera-facing pose and a warm, happy expression that retains the fan's identity. Put a red cone-shaped birthday hat naturally on their head. Pose one anatomically correct hand holding its own COMPLETE, fully visible small shot glass of golden-YELLOW aguardiente in a toast toward Jhon Alex. Show the continuous rim, transparent sides, yellow liquid and base of the glass, the fingers gripping it and a continuous wrist and arm. Prefer holding it near the fan's own chest so both glasses remain distinct and clearly readable. If the fan's glass, hand or hair naturally overlaps the artist's velvet suit or adjacent chair, show that foreground overlap in full with coherent perspective, transparent glass refraction and contact shadows: never erase it or stop it at an invisible boundary. Do not merge or duplicate the two people's hands, arms or glasses; retain Jhon Alex's original hand and original glass.
Re-light the entire fan for THIS scene from scratch. Image 2 provides identity and wardrobe, NEVER lighting, exposure, color grading or white balance. Use Jhon Alex's face, his suit and the ivory upholstery in image 1 to infer the scene's key-light direction, height and softness, fill-light strength, warm white balance, shadow depth and highlight roll-off. Apply that same lighting setup to the fan's face, hair, neck, hands and clothing, including warm reflected light from the gold furniture and realistic contact shadows beneath the hat, chin, arms and seated body. Preserve the fan's own natural complexion and the actual garment colors; do not copy Jhon Alex's skin pigmentation. Remove any source-photo flash, cold screen tint or colored glare on eyeglasses and replace it with restrained reflections consistent with this room. Match the master photograph's exposure, black levels, saturation, local contrast, skin texture, detail and grain, so both people look photographed together with the same camera. Keep natural pores and fabric detail without beauty smoothing or artificial sharpening halos.
Reconstruct crisp, natural hair edges with individual strands: never fade, feather or blur the head into the curtain. Rebuild the right chair and curtain only where needed around the new person, with no remnants of an old person, duplicate limbs, straight cutout seams or pasted photographic patches. Complete every visible part of the fan and their glass naturally; there is no editing-mask boundary that can hide part of them.
Keep the entire composition registered exactly to image 1: no zoom, crop, camera change, border, letterbox or layout shift. Preserve Jhon Alex on the LEFT as faithfully as possible: his exact recognizable face and facial proportions, smile, expression, eye direction, hair, beard, skin texture, pose, body proportions, green velvet suit, jewelry, hands, original glass and red hat. Do not reinterpret, beautify, age or replace him. Keep his visible suit unchanged except where the new companion naturally occludes it. Preserve the approved upper caption with exactly the same words, spelling, lettering, colors and placement: "Ya estoy listo pa celebrar el cumpleaños del Rey del Chupe en el Movistar Arena". Preserve the foreground cake, candles, table and Aguardiente Amarillo de Manzanares bottle, their labels, shapes and positions. Keep the background, chairs, light and decorative details wherever the new companion does not require a natural change. Add no other people, text or logos. Return one opaque photograph covering the FULL canvas, composed as a single natural exposure. This is a fictional personal birthday fan souvenir.`;

async function boundedBytes(response:Response,limit:number){
 const length=Number(response.headers.get('content-length')||0);if(length>limit){await response.body?.cancel().catch(()=>{});throw new Error('Image response too large');}
 if(!response.body)throw new Error('Empty image response');
 const reader=response.body.getReader(),chunks:Uint8Array[]=[];let total=0;
 try{for(;;){const next=await reader.read();if(next.done)break;total+=next.value.byteLength;if(total>limit){await reader.cancel();throw new Error('Image response too large');}chunks.push(next.value);}}finally{reader.releaseLock();}
 const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}return bytes;
}
async function deadline<T>(promise:Promise<T>,ms:number){let timer:ReturnType<typeof setTimeout>|undefined;try{return await Promise.race([promise,new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new Error('Image processing timeout')),ms);})]);}finally{if(timer)clearTimeout(timer);}}
function dimensions(bytes:Uint8Array,mime:string):{width:number;height:number}|null{
 const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
 if(mime==='image/png'&&bytes.length>=33&&[137,80,78,71,13,10,26,10].every((n,i)=>bytes[i]===n)&&String.fromCharCode(...bytes.subarray(12,16))==='IHDR')return {width:view.getUint32(16),height:view.getUint32(20)};
 if(mime==='image/jpeg'&&bytes.length>=4&&bytes[0]===255&&bytes[1]===216&&bytes[2]===255){
  let at=2;while(at+4<=bytes.length){if(bytes[at++]!==255)return null;while(at<bytes.length&&bytes[at]===255)at++;const marker=bytes[at++];if(marker===217||marker===218)return null;if(marker===1||marker>=208&&marker<=215)continue;if(at+2>bytes.length)return null;const length=view.getUint16(at);if(length<2||at+length>bytes.length)return null;if([192,193,194,195,197,198,199,201,202,203,205,206,207].includes(marker)){if(length<8)return null;return {width:view.getUint16(at+5),height:view.getUint16(at+3)};}at+=length;}
 }
 if(mime==='image/webp'&&bytes.length>=30&&String.fromCharCode(...bytes.subarray(0,4))==='RIFF'&&String.fromCharCode(...bytes.subarray(8,12))==='WEBP'){
  const kind=String.fromCharCode(...bytes.subarray(12,16));
  if(kind==='VP8X')return {width:1+bytes[24]+(bytes[25]<<8)+(bytes[26]<<16),height:1+bytes[27]+(bytes[28]<<8)+(bytes[29]<<16)};
  if(kind==='VP8 '&&bytes[23]===157&&bytes[24]===1&&bytes[25]===42)return {width:view.getUint16(26,true)&16383,height:view.getUint16(28,true)&16383};
  if(kind==='VP8L'&&bytes[20]===47){const bits=view.getUint32(21,true);return {width:(bits&16383)+1,height:((bits>>>14)&16383)+1};}
 }
 return null;
}

// Decode in Images rather than trusting file extensions or preserving EXIF.
// Only this normalized JPEG is stored in the private fan upload queue.
export async function normalizeBirthdayUpload(bytes:Uint8Array,mimeType:string){
 const mime=mimeType.toLowerCase(),heic=['image/heic','image/heif'].includes(mime),size=heic?null:dimensions(bytes,mime);
 const validSize=(value:{width?:number;height?:number}|null):boolean=>{
  if(!value)return false;const {width,height}=value;
  return typeof width==='number'&&typeof height==='number'&&Number.isSafeInteger(width)&&Number.isSafeInteger(height)&&width>0&&height>0&&width<=12000&&height<=12000&&width*height<=64_000_000;
 };
 if(bytes.length>8*1024*1024||(heic?!isBirthdayHEIC(bytes):!['image/jpeg','image/png','image/webp'].includes(mime)||!validSize(size)))throw new BirthdayImageFailure('Sube una foto JPG, PNG, WebP o HEIC válida de hasta 8 MB.',false,400);
 const images=bindings().IMAGES;if(!images)throw new BirthdayImageFailure('Estamos preparando la experiencia. Intenta más tarde.',false,503);
 try{
  // HEIC dimensions belong to the decoded primary image, not an arbitrary ispe
  // thumbnail/tile in its container. Keep the same bounds before transforming.
  if(heic&&!validSize(await deadline(images.info(new Response(new Uint8Array(bytes)).body!),25000)))throw new Error('Invalid HEIC dimensions');
  const bytesCopy=new Uint8Array(bytes),output=await deadline(images.input(new Response(bytesCopy).body!).transform({width:1536,height:1536,fit:'scale-down'}).output({format:'image/jpeg',quality:90}),25000),response=output.response();
  if(!response.ok)throw new Error('Image decode failed');const normalized=await boundedBytes(response,3*1024*1024),normalizedSize=dimensions(normalized,'image/jpeg');
  if(!normalizedSize||!normalizedSize.width||!normalizedSize.height||normalizedSize.width>1536||normalizedSize.height>1536)throw new Error('Invalid normalized image');
  return {bytes:normalized,mimeType:'image/jpeg'};
 }catch{throw new BirthdayImageFailure('No pudimos leer esa foto. Prueba otra imagen JPG, PNG, WebP o HEIC.',false,400);}
}

type Template={canvas:Blob};
let templatePromise:Promise<Template>|null=null;
async function digest(bytes:Uint8Array){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes)))).map(n=>n.toString(16).padStart(2,'0')).join('');}
async function asset(spec:{file:string;sha256:string;bytes:number}){
 const assets=bindings().ASSETS;if(!assets)throw new Error('Template unavailable');
 const response=await assets.fetch(new Request('https://jhonalexcastano.com/cumpleanos/'+spec.file));
 if(!response.ok)throw new Error('Template unavailable');const bytes=await boundedBytes(response,4*1024*1024);
 if(bytes.length!==spec.bytes||await digest(bytes)!==spec.sha256)throw new Error('Template version mismatch');return bytes;
}
async function template(){
 if(!templatePromise)templatePromise=(async()=>{const [masterBytes,canvas]=await Promise.all([asset(render.master),asset(render.canvas)]),master=decodePng(masterBytes),reference=decodePng(canvas);
  if(master.width!==render.master.width||master.height!==render.master.height||reference.width!==render.canvas.width||reference.height!==render.canvas.height)throw new Error('Template dimensions mismatch');
  // Supply the approved photo in full, including both original people and
  // the scene. No input region is erased or assigned an editing mask.
  for(let at=3;at<reference.rgba.length;at+=4)if(reference.rgba[at]!==255)throw new Error('Unexpected transparent reference');
  // Blob snapshots the verified bytes once. All concurrent multipart requests
  // reference this immutable Blob instead of allocating another master copy.
  return {canvas:new Blob([canvas as Uint8Array<ArrayBuffer>],{type:'image/png'})};
 })().catch(error=>{templatePromise=null;throw error;});
 return templatePromise;
}

// Resize the ENTIRE provider photograph. Artist/scene preservation is a prompt
// instruction, not a pixel guarantee: pasting the master back caused the glass
// and hands to be cut at the previous mask boundary.
export function renderBirthdayPhoto(generated:PngImage){
 if(generated.width!==render.canvas.width||generated.height!==render.canvas.height||generated.rgba.length!==generated.width*generated.height*4)throw new Error('Unexpected image dimensions');
 for(let at=3;at<generated.rgba.length;at+=4)if(generated.rgba[at]!==255)throw new Error('Unexpected transparent photo');
 const {x:sceneX,y:sceneY,width:sceneWidth,height:sceneHeight}=render.sceneRect,{width,height}=render.master,output=new Uint8Array(width*height*4),gw=generated.width;
 for(let y=0;y<height;y++)for(let x=0;x<width;x++){
  const at=(y*width+x)*4;
  const sx=Math.max(sceneX,Math.min(sceneX+sceneWidth-1,sceneX+(x+.5)*sceneWidth/width-.5)),sy=Math.max(sceneY,Math.min(sceneY+sceneHeight-1,sceneY+(y+.5)*sceneHeight/height-.5));
  const x0=Math.floor(sx),y0=Math.floor(sy),x1=Math.min(sceneX+sceneWidth-1,x0+1),y1=Math.min(sceneY+sceneHeight-1,y0+1),fx=sx-x0,fy=sy-y0;
  const a=(y0*gw+x0)*4,b=(y0*gw+x1)*4,c=(y1*gw+x0)*4,d=(y1*gw+x1)*4;
  for(let channel=0;channel<3;channel++){
   const value=(generated.rgba[a+channel]*(1-fx)+generated.rgba[b+channel]*fx)*(1-fy)+(generated.rgba[c+channel]*(1-fx)+generated.rgba[d+channel]*fx)*fy;
   output[at+channel]=Math.round(value);
  }
  output[at+3]=255;
 }
 return {width,height,rgba:output};
}

export async function generateBirthdayPhoto(photo:Uint8Array,mimeType:string):Promise<Uint8Array>{
 const key=bindings().OPENAI_API_KEY;if(!key)throw new BirthdayImageFailure('La experiencia todavía no está disponible.',false,503);
 if(!dimensions(photo,mimeType)||photo.length>3*1024*1024)throw new BirthdayImageFailure('La foto de referencia no está disponible.',false,400);
 let approved:Template;try{approved=await template();}catch{throw new BirthdayImageFailure('No pudimos preparar la imagen. Intenta más tarde.',false,503);}
 const body=new FormData();body.append('model',BIRTHDAY_MODEL);body.append('prompt',BIRTHDAY_PROMPT);body.append('n','1');body.append('size',`${render.canvas.width}x${render.canvas.height}`);body.append('quality','high');body.append('output_format','png');body.append('background','opaque');
 body.append('image[]',approved.canvas,'birthday-master.png');body.append('image[]',new Blob([photo as Uint8Array<ArrayBuffer>],{type:mimeType}),'fan-reference.jpg');
 // Blob already snapshots the source; do not retain an extra upload array
 // throughout a long provider call. The queue caller releases its own copy.
 photo=new Uint8Array(0);
 let response:Response;
 try{response=await fetch(PROVIDER,{method:'POST',headers:{Authorization:'Bearer '+key},body,redirect:'manual',signal:AbortSignal.timeout(5*60*1000)});}catch{throw new BirthdayImageFailure('No pudimos confirmar la generación. No la repetiremos automáticamente.',true);}finally{body.delete('image[]');}
 if(!response.ok){await response.body?.cancel().catch(()=>{});const definite=[400,401,403,404,413,422,429].includes(response.status);throw new BirthdayImageFailure('No pudimos completar la generación. Intenta más tarde.',!definite);}
 const release=await acquireResponseProcessing();
 try{
  let json=JSON.parse(new TextDecoder().decode(await boundedBytes(response,PROVIDER_RESPONSE_LIMIT))) as {data?:{b64_json?:string}[]};
  let base64=json.data?.length===1?json.data[0].b64_json:undefined;json={};
  if(typeof base64!=='string'||base64.length>PROVIDER_RESPONSE_LIMIT||!/^[A-Za-z0-9+/]*={0,2}$/.test(base64))throw new Error('Invalid provider output');
  let binary=atob(base64);base64=undefined;
  let bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);binary='';
  const generated=decodePng(bytes);bytes=new Uint8Array(0);
  return encodePng(renderBirthdayPhoto(generated));
 }catch{await response.body?.cancel().catch(()=>{});throw new BirthdayImageFailure('La generación no quedó confirmada. No la repetiremos automáticamente.',true);}finally{release();}
}
