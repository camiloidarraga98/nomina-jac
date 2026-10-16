import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const built=await build({entryPoints:['lib/media-image-client.ts'],bundle:true,platform:'browser',format:'esm',write:false});
const m=await import('data:text/javascript;base64,'+Buffer.from(built.outputFiles[0].contents).toString('base64'));
test('quality preference persists every supported level and defaults safely without storage',()=>{
 const data=new Map();globalThis.localStorage={getItem:key=>data.get(key)??null,setItem:(key,value)=>data.set(key,value)};
 assert.equal(m.savedMediaImageLimit(),2_000_000);
 for(const limit of [2_000_000,4_000_000,6_000_000,0]){m.saveMediaImageLimit(limit);assert.equal(m.savedMediaImageLimit(),limit);}
 globalThis.localStorage={getItem:()=>{throw new Error('storage unavailable')},setItem:()=>{throw new Error('storage unavailable')}};assert.equal(m.savedMediaImageLimit(),2_000_000);assert.throws(()=>m.saveMediaImageLimit(0),/guardar/);
});
test('original mode and videos bypass decoding and retain exactly their bytes at every setting',async()=>{
 globalThis.createImageBitmap=()=>{throw new Error('Must not decode originals or videos')};
 const bytes=Buffer.alloc(8_000_017,42),image=new File([bytes],'Cámara.JPG',{type:'image/jpeg'}),video=new File([bytes],'Cámara.mov',{type:'video/quicktime'});
 assert.equal(await m.prepareMediaImage(image,image.type,0),image);assert.deepEqual(Buffer.from(await image.arrayBuffer()),bytes);
 for(const limit of [2_000_000,4_000_000,6_000_000,0]){const result=await m.prepareMediaImage(video,video.type,limit);assert.equal(result,video);assert.deepEqual(Buffer.from(await result.arrayBuffer()),bytes);}
});
test('photos already below the selected maximum are preserved and an unsupported codec never silently exceeds the choice',async()=>{
 const image=new File([Buffer.alloc(3_000_000)],'Prueba.heic',{type:'image/heic'});assert.equal(await m.prepareMediaImage(image,image.type,4_000_000),image);
 globalThis.createImageBitmap=async()=>{throw new Error('Unsupported codec')};await assert.rejects(()=>m.prepareMediaImage(image,image.type,2_000_000),/Sin compresión/);
});
test('animated images are not flattened into a single JPEG frame',async()=>{
 const image=new File([Buffer.alloc(2_000_001)],'Animación.gif',{type:'image/gif'});await assert.rejects(()=>m.prepareMediaImage(image,image.type,2_000_000),/animada/);assert.equal(await m.prepareMediaImage(image,image.type,0),image);
});
