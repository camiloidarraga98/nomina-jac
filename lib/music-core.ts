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
export function audioSignature(b:Uint8Array,mime:string){const text=(i:number,n:number)=>new TextDecoder().decode(b.slice(i,i+n));if(b.length<12)return false;return mime==='audio/mpeg'?(text(0,3)==='ID3'||b[0]===255&&(b[1]&224)===224&&(b[1]&6)!==0):mime==='audio/mp4'?text(4,4)==='ftyp':mime==='audio/wav'?text(0,4)==='RIFF'&&text(8,4)==='WAVE':mime==='audio/aac'?b[0]===255&&(b[1]&246)===240:false;}
export function musicRange(value:string|null,size:number):{offset:number;length:number}|null{if(!value)return null;const m=/^bytes=(\d*)-(\d*)$/.exec(value);if(!m||!m[1]&&!m[2])throw new MusicFailure('Rango no válido.',416);let start=m[1]?Number(m[1]):Math.max(0,size-Number(m[2])),end=m[1]?(m[2]?Number(m[2]):size-1):size-1;if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start<0||start>=size||end<start)throw new MusicFailure('Rango no válido.',416);end=Math.min(end,size-1);return {offset:start,length:end-start+1};}
