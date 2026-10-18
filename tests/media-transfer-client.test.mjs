import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const bundle=await build({entryPoints:['lib/media-upload-client.ts'],bundle:true,format:'esm',platform:'node',write:false});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
test('browser direct upload sends only bounded file bytes to its one-file Google capability',async()=>{
 const saved=globalThis.fetch,calls=[];globalThis.fetch=async(url,options)=>{calls.push({url,options});return new Response(null,{status:308});};
 try{const bytes=new Blob([new Uint8Array(1024)]),signal=new AbortController().signal;await m.sendMediaDirectChunk('https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture-one-file','image/png',bytes,0,2048,signal);
 const {url,options}=calls[0];assert.equal(url.origin,'https://www.googleapis.com');assert.equal(options.credentials,'omit');assert.equal(options.referrerPolicy,'no-referrer');assert.equal(options.redirect,'error');assert.equal(options.cache,'no-store');assert.equal(options.headers['Content-Range'],'bytes 0-1023/2048');assert.equal(options.headers.Cookie,undefined);assert.equal(options.headers.Authorization,undefined);assert.equal(options.signal,signal);
 for(const url of ['http://www.googleapis.com/upload/drive/v3/files?upload_id=x','https://attacker.invalid/upload/drive/v3/files?upload_id=x','https://user@www.googleapis.com/upload/drive/v3/files?upload_id=x','https://www.googleapis.com/drive/v3/files?upload_id=x','https://www.googleapis.com/upload/drive/v3/files?upload_id=x&upload_id=y','https://www.googleapis.com/upload/drive/v3/files'])assert.throws(()=>m.directMediaUploadURL(url));
 await assert.rejects(()=>m.sendMediaDirectChunk(String(url),'image/png',new Blob([new Uint8Array(8*1024*1024+1)]),0,9*1024*1024,signal));assert.equal(calls.length,1);
 }finally{globalThis.fetch=saved;}
});
test('progress transport is isolated to the exact R2 account and cannot send cookies or follow foreign redirects',()=>{
 const origin='https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',nonce='00000000-0000-0000-0000-000000000000';
 const html=m.mediaUploadDocument(origin,nonce);assert.ok(html.includes("default-src 'none'"));assert.ok(html.includes('connect-src '+origin+';'));assert.ok(html.includes("script-src 'nonce-"+nonce+"'"));assert.match(html,/name="referrer" content="no-referrer"/);assert.match(html,/withCredentials\s*=\s*false/);assert.match(html,/responseURL\s*===\s*url/);assert.ok(!html.includes('uploadId='));
 for(const value of ['https://attacker.invalid',origin+'; connect-src *',origin+'/other','http://'+origin.slice(8)])assert.throws(()=>m.mediaUploadDocument(value,nonce));
 assert.throws(()=>m.mediaUploadDocument(origin,'<script>'));
});
test('live speed sums both uploads, ignores duplicate progress and expires when idle',async()=>{
 const result=await build({entryPoints:['lib/media-upload-meter.ts'],bundle:true,format:'esm',platform:'node',write:false}),{MediaUploadMeter}=await import('data:text/javascript;base64,'+Buffer.from(result.outputFiles[0].contents).toString('base64'));
 const meter=new MediaUploadMeter();meter.record('one',1000,0);meter.record('two',1000,0);meter.record('one',1000,500);assert.equal(meter.rate(500),2000);meter.record('one',2000,500);assert.equal(meter.rate(500),3000);meter.record('one',50,600);assert.equal(meter.rate(500),3000);meter.finish('one');meter.record('one',1000,1000);assert.equal(meter.rate(1000),4000/1.5);assert.equal(meter.rate(6000),0);meter.reset();assert.equal(meter.rate(6000),0);
});
