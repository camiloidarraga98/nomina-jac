import {env} from 'cloudflare:workers';
import render from '../design/fans/cumpleanos/render-v2.json';
import {decodePng,encodePng,type PngImage} from './fans-png';

type Images={input(stream:ReadableStream):{transform(options:Record<string,unknown>):{output(options:{format:string;quality:number}):Promise<{response():Response}>}}};
type ImageEnv={OPENAI_API_KEY?:string;ASSETS?:{fetch(request:Request):Promise<Response>};IMAGES?:Images};
const bindings=()=>env as unknown as ImageEnv;
export class BirthdayImageFailure extends Error{
 constructor(message:string,readonly paidAttempt=false,readonly status=502){super(message);}
}
const PROVIDER='https://api.openai.com/v1/images/edits';
// Pin the quality-oriented editor so an alias update cannot silently change the pilot.
// GPT Image 2.5 uses high-fidelity references without the legacy input_fidelity field.
export const BIRTHDAY_MODEL='gpt-image-2.5-sunburst-2026-09-08';
export const BIRTHDAY_PROMPT=`Create one coherent, realistic birthday photograph by filling the transparent region on the RIGHT of image 1. Image 1 supplies the fixed composition and the artist on the LEFT. Its right companion has deliberately been erased completely. Image 2 is the ONLY identity and wardrobe reference for the new adult companion. Reconstruct that entire person naturally in the right-hand seat: head, hair, neck, shoulders, torso, arms, hands, clothing and visible legs. This is a complete-person reconstruction, not a face swap or a cutout pasted onto an existing body.
Preserve the fan's recognizable facial features and proportions, complexion, hairstyle, visible body proportions, glasses and other visible accessories. Respect their appearance, whether a woman or a man. Preserve the actual visible outfit from image 2: garment type, neckline, sleeves, colors, patterns and fit. Re-create its fabric and folds for the new seated pose; do not copy the source pose, source background or source lighting. Do not force a black shirt, trousers, short hair or a masculine body onto the fan. Long hair, dresses and different body shapes may occupy the surrounding editable background and chair. If only a face or upper body is visible in image 2, complete the unseen parts plausibly and consistently with what IS visible.
Seat the fan beside Jhon Alex at the same distance from the camera and the same eye-level perspective. Use realistic head-to-body scale, a coherent neck and shoulders, a relaxed camera-facing pose and a warm, happy expression that retains the fan's identity. Put a red cone-shaped birthday hat naturally on their head. Pose one anatomically correct hand holding its own small shot glass of golden-YELLOW aguardiente in a toast toward Jhon Alex; keep the two people's hands, arms and glasses distinct. Match the scene's warm light direction, exposure, white balance, skin texture, sharpness and grain. Include believable contact shadows, hair edges, fabric shading and seat contact. Rebuild the right chair and curtain wherever needed around the person's new silhouette, with no remnants of an old person, duplicate limbs, straight cutout seams or pasted photographic patches.
Keep the entire unmasked composition registered exactly to image 1: no zoom, crop, camera change, border or layout shift. Preserve Jhon Alex on the LEFT exactly, including his face, smile, hair, beard, green velvet suit, jewelry, hands, glass and red hat. Preserve the approved upper caption and the protected foreground cake, candles, table and Aguardiente Amarillo de Manzanares bottle. Add no other people, text or logos. Return an opaque photograph covering the full canvas. This is a fictional personal birthday fan souvenir.`;

async function boundedBytes(response:Response,limit:number){
 const length=Number(response.headers.get('content-length')||0);if(length>limit)throw new Error('Image response too large');
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
 const mime=mimeType.toLowerCase(),size=dimensions(bytes,mime);
 if(!['image/jpeg','image/png','image/webp'].includes(mime)||bytes.length>8*1024*1024||!size||!size.width||!size.height||size.width>12000||size.height>12000||size.width*size.height>64_000_000)throw new BirthdayImageFailure('Sube una foto JPG, PNG o WebP válida de hasta 8 MB.',false,400);
 const images=bindings().IMAGES;if(!images)throw new BirthdayImageFailure('Estamos preparando la experiencia. Intenta más tarde.',false,503);
 try{
  const bytesCopy=new Uint8Array(bytes),output=await deadline(images.input(new Response(bytesCopy).body!).transform({width:1536,height:1536,fit:'scale-down'}).output({format:'image/jpeg',quality:90}),25000),response=output.response();
  if(!response.ok)throw new Error('Image decode failed');const normalized=await boundedBytes(response,3*1024*1024),normalizedSize=dimensions(normalized,'image/jpeg');
  if(!normalizedSize||!normalizedSize.width||!normalizedSize.height||normalizedSize.width>1536||normalizedSize.height>1536)throw new Error('Invalid normalized image');
  return {bytes:normalized,mimeType:'image/jpeg'};
 }catch{throw new BirthdayImageFailure('No pudimos leer esa foto. Prueba otra imagen JPG, PNG o WebP.',false,400);}
}

type Template={master:PngImage;blend:PngImage;canvas:Uint8Array;mask:Uint8Array};
let templatePromise:Promise<Template>|null=null;
async function digest(bytes:Uint8Array){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes)))).map(n=>n.toString(16).padStart(2,'0')).join('');}
async function asset(spec:{file:string;sha256:string;bytes:number}){
 const assets=bindings().ASSETS;if(!assets)throw new Error('Template unavailable');
 const response=await assets.fetch(new Request('https://jhonalexcastano.com/cumpleanos/'+spec.file));
 if(!response.ok)throw new Error('Template unavailable');const bytes=await boundedBytes(response,4*1024*1024);
 if(bytes.length!==spec.bytes||await digest(bytes)!==spec.sha256)throw new Error('Template version mismatch');return bytes;
}
async function template(){
 if(!templatePromise)templatePromise=(async()=>{const [masterBytes,canvas,mask,blendBytes]=await Promise.all([asset(render.master),asset(render.canvas),asset(render.mask),asset(render.blend)]),master=decodePng(masterBytes),blend=decodePng(blendBytes);
  if(master.width!==render.master.width||master.height!==render.master.height||blend.width!==master.width||blend.height!==master.height)throw new Error('Template dimensions mismatch');
  // Verify the mask's fixed geometry before the only billable provider request.
  const maskImage=decodePng(mask);if(maskImage.width!==render.canvas.width||maskImage.height!==render.canvas.height)throw new Error('Mask dimensions mismatch');
  return {master,blend,canvas,mask};
 })().catch(error=>{templatePromise=null;throw error;});
 return templatePromise;
}

// All four channels of protected pixels come directly from the approved master.
// Resampling is restricted to the generated patch inside the source-space mask.
export function compositeBirthdayPhoto(master:PngImage,generated:PngImage,blend:PngImage){
 if(master.width!==render.master.width||master.height!==render.master.height||blend.width!==master.width||blend.height!==master.height||generated.width!==render.canvas.width||generated.height!==render.canvas.height)throw new Error('Unexpected image dimensions');
 // An opaque photo was requested. Reject transparent output rather than letting
 // fragments of the old companion show through the reconstructed person.
 for(let at=3;at<generated.rgba.length;at+=4)if(generated.rgba[at]!==255)throw new Error('Unexpected transparent photo');
 const {x:sceneX,y:sceneY,width:sceneWidth,height:sceneHeight}=render.sceneRect,output=new Uint8Array(master.rgba),gw=generated.width;
 for(let y=0;y<master.height;y++)for(let x=0;x<master.width;x++){
  const at=(y*master.width+x)*4,weight=blend.rgba[at+3];if(!weight)continue;
  const sx=Math.max(sceneX,Math.min(sceneX+sceneWidth-1,sceneX+(x+.5)*sceneWidth/master.width-.5)),sy=Math.max(sceneY,Math.min(sceneY+sceneHeight-1,sceneY+(y+.5)*sceneHeight/master.height-.5));
  const x0=Math.floor(sx),y0=Math.floor(sy),x1=Math.min(sceneX+sceneWidth-1,x0+1),y1=Math.min(sceneY+sceneHeight-1,y0+1),fx=sx-x0,fy=sy-y0;
  const a=(y0*gw+x0)*4,b=(y0*gw+x1)*4,c=(y1*gw+x0)*4,d=(y1*gw+x1)*4;
  const w=weight/255;
  for(let channel=0;channel<3;channel++){
   const value=(generated.rgba[a+channel]*(1-fx)+generated.rgba[b+channel]*fx)*(1-fy)+(generated.rgba[c+channel]*(1-fx)+generated.rgba[d+channel]*fx)*fy;
   output[at+channel]=Math.round(master.rgba[at+channel]*(1-w)+value*w);
  }
 }
 return {width:master.width,height:master.height,rgba:output};
}

export async function generateBirthdayPhoto(photo:Uint8Array,mimeType:string):Promise<Uint8Array>{
 const key=bindings().OPENAI_API_KEY;if(!key)throw new BirthdayImageFailure('La experiencia todavía no está disponible.',false,503);
 if(!dimensions(photo,mimeType)||photo.length>3*1024*1024)throw new BirthdayImageFailure('La foto de referencia no está disponible.',false,400);
 let approved:Template;try{approved=await template();}catch{throw new BirthdayImageFailure('No pudimos preparar la imagen. Intenta más tarde.',false,503);}
 const body=new FormData();body.append('model',BIRTHDAY_MODEL);body.append('prompt',BIRTHDAY_PROMPT);body.append('n','1');body.append('size',`${render.canvas.width}x${render.canvas.height}`);body.append('quality','high');body.append('output_format','png');body.append('background','opaque');
 body.append('image[]',new Blob([new Uint8Array(approved.canvas)],{type:'image/png'}),'birthday-master.png');body.append('image[]',new Blob([new Uint8Array(photo)],{type:mimeType}),'fan-reference.jpg');body.append('mask',new Blob([new Uint8Array(approved.mask)],{type:'image/png'}),'birthday-mask.png');
 let response:Response;
 try{response=await fetch(PROVIDER,{method:'POST',headers:{Authorization:'Bearer '+key},body,redirect:'manual',signal:AbortSignal.timeout(5*60*1000)});}catch{throw new BirthdayImageFailure('No pudimos confirmar la generación. No la repetiremos automáticamente.',true);}
 if(!response.ok){await response.body?.cancel().catch(()=>{});const definite=[400,401,403,404,413,422,429].includes(response.status);throw new BirthdayImageFailure('No pudimos completar la generación. Intenta más tarde.',!definite);}
 try{
  const json=JSON.parse(new TextDecoder().decode(await boundedBytes(response,16*1024*1024))) as {data?:{b64_json?:string}[]};
  const base64=json.data?.length===1?json.data[0].b64_json:undefined;if(typeof base64!=='string'||base64.length>16*1024*1024||!/^[A-Za-z0-9+/]*={0,2}$/.test(base64))throw new Error('Invalid provider output');
  const binary=atob(base64),bytes=Uint8Array.from(binary,c=>c.charCodeAt(0)),generated=decodePng(bytes);
  return encodePng(compositeBirthdayPhoto(approved.master,generated,approved.blend));
 }catch{throw new BirthdayImageFailure('La generación no quedó confirmada. No la repetiremos automáticamente.',true);}
}
