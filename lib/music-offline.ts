import type {MusicLibrary,MusicTrack} from './music-core';
export type MusicOffline={connect:(library:MusicLibrary)=>Promise<void>;clear:()=>Promise<void>;catalog:()=>Promise<MusicTrack[]>;saved:()=>Promise<{id:string;revision:string;scope:string}[]>;remove:(id:string)=>Promise<void>;download:(item:MusicTrack,progress?:(value:number)=>void,signal?:AbortSignal)=>Promise<void>;url:(scope:string,item:MusicTrack)=>string};
declare global{interface Window{JACMusicOffline:MusicOffline}}
let pending:Promise<MusicOffline>|undefined;
export function musicOffline(){return pending??=new Promise<MusicOffline>((resolve,reject)=>{if(window.JACMusicOffline){resolve(window.JACMusicOffline);return;}const s=document.createElement('script');s.src='/jac-music-offline.js';s.onload=()=>resolve(window.JACMusicOffline);s.onerror=()=>{pending=undefined;reject(new Error('No se pudo preparar Música sin conexión.'));};document.head.appendChild(s);});}
export async function clearMusicOffline(){if(typeof window==='undefined')return;window.dispatchEvent(new Event('jac-music-stop'));try{localStorage.setItem('jac.music.revoked',crypto.randomUUID());}catch{}await(await musicOffline()).clear();}
