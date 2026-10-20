import test from 'node:test';import assert from 'node:assert/strict';import {build} from 'esbuild';
const bundled=await build({entryPoints:['lib/media-download-zip.ts'],bundle:true,platform:'node',format:'esm',write:false});const m=await import('data:text/javascript;base64,'+Buffer.from(bundled.outputFiles[0].contents).toString('base64'));
test('cancelling the ZIP source stops before opening the next original and closes the active reader',async()=>{
 let opened=0,cancelled=0;const files=[0,1,2].map(id=>({name:id+'.jpg',size:4,open:async()=>{opened++;return {body:new ReadableStream({start(c){c.enqueue(new Uint8Array(4));},cancel(){cancelled++;}}),check:async()=>{}};}}));
 const reader=m.mediaZipStream(files).getReader();await reader.read();assert.equal(opened,1);await reader.cancel();await new Promise(resolve=>setImmediate(resolve));assert.equal(opened,1);assert.equal(cancelled,1);
});
