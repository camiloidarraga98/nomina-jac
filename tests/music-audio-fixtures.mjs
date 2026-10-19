// Generated tones only; these fixtures never contain user media.
import {execFileSync} from 'node:child_process';
import {mkdir,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
export async function audioFixtures(){
 const root=resolve('work/local/music-format-fixtures-v1');await mkdir(root,{recursive:true});
 let existing=true;for(const name of ['pcm.wav','rf64.wav','frames.mp3','song.m4a','song.aac']){try{await readFile(root+'/'+name);}catch{existing=false;break;}}
 if(!existing)execFileSync('ffmpeg',['-y','-loglevel','error','-f','lavfi','-i','sine=frequency=440:duration=0.3','-ac','1','-ar','44100','-c:a','pcm_s16le',root+'/pcm.wav','-c:a','pcm_s16le','-rf64','always',root+'/rf64.wav','-c:a','libmp3lame','-id3v2_version','0','-write_xing','0',root+'/frames.mp3','-c:a','aac',root+'/song.m4a','-c:a','aac','-f','adts',root+'/song.aac'],{stdio:'pipe'});
 const values=await Promise.all(['pcm.wav','rf64.wav','frames.mp3','song.m4a','song.aac'].map(n=>readFile(root+'/'+n)));
 return Object.fromEntries(['wav','rf64','mp3','m4a','aac'].map((n,i)=>[n,values[i]]));
}
