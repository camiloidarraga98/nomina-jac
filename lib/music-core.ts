export const musicSections=[
 {id:'warmup',title:'Para Calentar',description:'Pistas y ejercicios para antes del show.',icon:'flame'},
 {id:'tracks',title:'Pistas',description:'Las canciones de Jhon Alex, de la A a la Z.',icon:'mic'},
 {id:'demos',title:'Maquetas',description:'Ideas y demos para escuchar y elegir.',icon:'headphones'},
 {id:'studio',title:'Música estudio',description:'Lo que está tomando forma en el estudio.',icon:'sliders'},
] as const;
export type MusicSection=typeof musicSections[number]['id'];
export type MusicTrack={id:string;section:MusicSection;title:string;filename:string;mimeType:string;size:number;revision:string;createdAt:string};
export type MusicLibrary={tracks:MusicTrack[];canUpload:boolean;canDelete:boolean;scope:string;key:string};
export const MUSIC_CHUNK=8*1024*1024;
export class MusicFailure extends Error{constructor(message:string,public status=400){super(message);}}
export function musicSection(value:unknown):MusicSection{if(!musicSections.some(s=>s.id===value))throw new MusicFailure('Elige una sección de Música.');return value as MusicSection;}
export function musicID(value:unknown):string{if(typeof value!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value))throw new MusicFailure('El audio no es válido.');return value;}
export const musicSearch=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('es').trim();
export function musicOrder(a:MusicTrack,b:MusicTrack){return a.title.localeCompare(b.title,'es',{sensitivity:'base',numeric:true})||a.id.localeCompare(b.id);}
export function audioType(name:string):string{const ext=name.split('.').at(-1)?.toLowerCase();const mime:Record<string,string>={mp3:'audio/mpeg',m4a:'audio/mp4',aac:'audio/aac',wav:'audio/wav'};if(!ext||!mime[ext])throw new MusicFailure('Selecciona audio MP3, M4A, AAC o WAV.',415);return mime[ext];}
type MPEGFrame={length:number;version:number;layer:number;rate:number};
function mpegFrame(bytes:Uint8Array,offset:number):MPEGFrame|null{
 if(offset+4>bytes.length||bytes[offset]!==255||(bytes[offset+1]&224)!==224)return null;
 const version=(bytes[offset+1]>>3)&3,layer=(bytes[offset+1]>>1)&3,index=bytes[offset+2]>>4,rateIndex=(bytes[offset+2]>>2)&3;
 if(version===1||layer===0||index===15||rateIndex===3||(bytes[offset+3]&3)===2)return null;
 const rates=version===3?(layer===3?[0,32,64,96,128,160,192,224,256,288,320,352,384,416,448]:layer===2?[0,32,48,56,64,80,96,112,128,160,192,224,256,320,384]:[0,32,40,48,56,64,80,96,112,128,160,192,224,256,320]):layer===3?[0,32,48,56,64,80,96,112,128,144,160,176,192,224,256]:[0,8,16,24,32,40,48,56,64,80,96,112,128,144,160];
 const rate=[44100,48000,32000][rateIndex]/(version===3?1:version===2?2:4),padding=(bytes[offset+2]>>1)&1;
 if(index===0)return {length:0,version,layer,rate};
 const length=layer===3?(Math.floor(12*rates[index]*1000/rate)+padding)*4:Math.floor((layer===1&&version!==3?72:144)*rates[index]*1000/rate)+padding;
 return {length,version,layer,rate};
}
// Inspect a bounded prefix. Encoders may prepend tags, padding or container
// boxes; the filename is a hint and must not override a recognizable format.
export function detectedAudioMime(bytes:Uint8Array,totalSize=bytes.length):string|null{
 if(bytes.length<12)return null;
 const text=(offset:number,length:number)=>new TextDecoder().decode(bytes.subarray(offset,offset+length));
 if(['RIFF','RIFX','RF64','BW64'].includes(text(0,4))&&text(8,4)==='WAVE')return 'audio/wav';
 let offset=0,tagged=false;
 if(text(0,3)==='ID3'){
  if(![2,3,4].includes(bytes[3])||bytes[4]===255||bytes.subarray(6,10).some(b=>(b&128)!==0))return null;
  const size=bytes[6]*2097152+bytes[7]*16384+bytes[8]*128+bytes[9],footer=bytes[3]===4&&(bytes[5]&16)!==0?10:0;
  offset=10+size+footer;tagged=true;
  if(offset>=totalSize)return null;
  // Large embedded artwork may extend beyond the first upload block.
  if(offset+4>bytes.length)return 'audio/mpeg';
 }
 if(text(offset,8)==='APETAGEX'&&offset+32<=bytes.length){
  const little=(i:number)=>bytes[i]+bytes[i+1]*256+bytes[i+2]*65536+bytes[i+3]*16777216;
  const version=little(offset+8),size=little(offset+12);
  if(![1000,2000].includes(version)||size<32||offset+32+size>=totalSize)return null;
  offset+=32+size;tagged=true;
  if(offset+4>bytes.length)return 'audio/mpeg';
 }
 const aac=(i:number)=>i+7<=bytes.length&&bytes[i]===255&&(bytes[i+1]&246)===240&&((bytes[i+2]>>2)&15)!==15&&(((bytes[i+3]&3)<<11)|(bytes[i+4]<<3)|(bytes[i+5]>>5))>=7;
 if(aac(offset))return 'audio/aac';
 let box=0;
 for(let count=0;count<32&&box+12<=bytes.length;count++){
  const size=bytes[box]*16777216+bytes[box+1]*65536+bytes[box+2]*256+bytes[box+3],kind=text(box+4,4);
  if(kind==='ftyp'&&size>=16&&size<=totalSize-box)return 'audio/mp4';
  if(!['free','skip','wide'].includes(kind)||size<8||box+size>bytes.length)break;
  box+=size;
 }
 // Two consecutive MPEG frames distinguish audio after leading metadata from
 // arbitrary bytes that merely contain FF FB. Bound the scan to64KiB.
 const end=Math.min(bytes.length-4,offset+65536);
 for(let i=offset;i<=end;i++){
  const frame=mpegFrame(bytes,i);if(!frame)continue;
  if(frame.length===0){if(i===offset)return 'audio/mpeg';continue;}
  const next=mpegFrame(bytes,i+frame.length);
  if(next&&next.version===frame.version&&next.layer===frame.layer&&next.rate===frame.rate)return 'audio/mpeg';
  if(i===offset&&i+frame.length===totalSize)return 'audio/mpeg';
 }
 // ID3 is allowed to contain encoder-specific padding before MPEG frames, but
 // never enough to turn a truncated tag or an unrelated format into audio.
 if(tagged&&bytes.length<totalSize&&offset+65536>=bytes.length)return 'audio/mpeg';
 return null;
}
export function audioSignature(bytes:Uint8Array,mime:string){return detectedAudioMime(bytes)===mime;}
export function musicFilename(filename:string,mime:string){
 if(audioType(filename)===mime)return filename;
 const extensions:Record<string,string>={'audio/mpeg':'mp3','audio/mp4':'m4a','audio/aac':'aac','audio/wav':'wav'};
 return filename.replace(/\.[^.]+$/,'')+'.'+extensions[mime];
}

export function musicRange(value:string|null,size:number):{offset:number;length:number}|null{if(!value)return null;const m=/^bytes=(\d*)-(\d*)$/.exec(value);if(!m||!m[1]&&!m[2])throw new MusicFailure('Rango no válido.',416);let start=m[1]?Number(m[1]):Math.max(0,size-Number(m[2])),end=m[1]?(m[2]?Number(m[2]):size-1):size-1;if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start<0||start>=size||end<start)throw new MusicFailure('Rango no válido.',416);end=Math.min(end,size-1);return {offset:start,length:end-start+1};}
