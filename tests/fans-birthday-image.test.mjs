import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

// Only synthetic upload/provider bytes and the versioned public campaign asset.
// Every outbound provider request is intercepted; no paid inference is executed.
const dir=await mkdtemp(resolve('work/fans-image-test-'));
globalThis.__fansImageEnv={};
const bundle=await build({stdin:{resolveDir:process.cwd(),contents:"export * from './lib/fans-birthday-image';export * from './lib/fans-png';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'fixture-env',setup(b){b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const env=globalThis.__fansImageEnv;',loader:'js'}));}}]});
await writeFile(dir+'/bundle.mjs',bundle.outputFiles[0].contents);const m=await import(pathToFileURL(dir+'/bundle.mjs'));test.after(async()=>{await rm(dir,{recursive:true,force:true});});
const render=JSON.parse(await readFile('design/fans/cumpleanos/render-v1.json','utf8'));
const master=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/master-v1.png'))),blend=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/blend-v1.png')));
const RGB=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP4z8DA8J+BgYHhv4aRDQAbDAOUjA/9bAAAAABJRU5ErkJggg==','base64'));
// This header-only JPEG stands in for an image service's decoded fixture.
const photo=new Uint8Array([255,216,255,192,0,17,8,0,2,0,3,3,1,17,0,2,17,0,3,17,0,255,217]);
let assetBad=false,assetReads=0,calls=0,mode='ready',lastForm=null;
globalThis.__fansImageEnv.ASSETS={async fetch(req){assetReads++;const name=new URL(req.url).pathname.split('/').at(-1);assert.ok(['master-v1.png','canvas-v1.png','mask-v1.png','blend-v1.png'].includes(name));return new Response(assetBad&&name==='master-v1.png'?new Uint8Array([0]):await readFile('design/fans/cumpleanos/'+name));}};
const generated={width:1024,height:1536,rgba:new Uint8Array(1024*1536*4)};
for(let y=0;y<1536;y++)for(let x=0;x<1024;x++){const at=(y*1024+x)*4;generated.rgba.set(y<128||y>=1408?[251,0,251,255]:[13,143,74,255],at);}
const generatedBytes=m.encodePng(generated);
globalThis.fetch=async(url,options)=>{
 calls++;assert.equal(String(url),'https://api.openai.com/v1/images/edits','No arbitrary provider URL is reachable.');assert.equal(options.method,'POST');assert.equal(options.redirect,'manual');assert.ok(options.signal);lastForm=options.body;
 if(mode==='network')throw new TypeError('fictitious lost response');
 if(mode==='redirect')return new Response(null,{status:307,headers:{location:'https://untrusted.example.invalid/secret'}});
 if(mode==='rejected')return Response.json({error:{message:'provider-private-details'}},{status:400});
 if(mode==='service')return Response.json({error:{message:'provider-private-details'}},{status:503});
 if(mode==='invalid')return Response.json({data:[{b64_json:'AAAA'}]});
 if(mode==='wrong-size')return Response.json({data:[{b64_json:Buffer.from(RGB).toString('base64')}]});
 return Response.json({data:[{b64_json:Buffer.from(generatedBytes).toString('base64')}]});
};
const pixel=(image,x,y)=>Array.from(image.rgba.subarray((y*image.width+x)*4,(y*image.width+x)*4+4));

test('PNG decodes an independent RGB fixture and losslessly writes RGBA values',()=>{
 const rgb=m.decodePng(RGB);assert.equal(rgb.width,2);assert.equal(rgb.height,2);assert.deepEqual(Array.from(rgb.rgba),[255,0,0,255,0,255,0,255,0,0,255,255,40,50,60,255]);
 assert.deepEqual(m.decodePng(m.encodePng(rgb)),rgb);
 const rgba={width:2,height:1,rgba:new Uint8Array([0,255,40,0,16,89,201,128])};assert.deepEqual(m.decodePng(m.encodePng(rgba)),rgba);
});
test('PNG rejects corrupt CRC, truncation, trailing payloads and unsafe dimensions',()=>{
 const corrupt=new Uint8Array(RGB);corrupt[40]^=1;assert.throws(()=>m.decodePng(corrupt));assert.throws(()=>m.decodePng(RGB.slice(0,-3)));assert.throws(()=>m.decodePng(new Uint8Array([...RGB,0])));assert.throws(()=>m.decodePng(RGB,3));
 assert.throws(()=>m.encodePng({width:5000,height:1,rgba:new Uint8Array(20000)}));
});
test('upload validation rejects false codecs, huge dimensions and over-limit files before Images',async()=>{
 const huge=new Uint8Array(photo);huge[7]=255;huge[8]=255;const files=[[new Uint8Array([0,1]),'image/jpeg'],[RGB,'image/jpeg'],[huge,'image/jpeg'],[new Uint8Array(8*1024*1024+1),'image/png'],[photo,'text/plain']];
 for(const [bytes,mime] of files)await assert.rejects(m.normalizeBirthdayUpload(bytes,mime),e=>e.status===400&&e.paidAttempt===false);
});
test('upload normalization uses actual image decoding and stores only a bounded new JPEG',async()=>{
 let options,format,source;
 globalThis.__fansImageEnv.IMAGES={input(stream){source=stream;return {transform(value){options=value;return {async output(value){format=value;return {response:()=>new Response(photo,{headers:{'content-type':'image/jpeg'}})};}};}};}};
 const result=await m.normalizeBirthdayUpload(RGB,'image/png');assert.ok(source);assert.deepEqual(options,{width:1536,height:1536,fit:'scale-down'});assert.deepEqual(format,{format:'image/jpeg',quality:90});assert.equal(result.mimeType,'image/jpeg');assert.deepEqual(result.bytes,photo);assert.notDeepEqual(result.bytes,RGB);
 globalThis.__fansImageEnv.IMAGES={input(){return {transform(){return {async output(){throw new Error('private decode error');}};}};}};
 await assert.rejects(m.normalizeBirthdayUpload(RGB,'image/png'),e=>e.status===400&&!e.message.includes('private'));
});
test('missing key and modified master stop before any billable request',async()=>{
 const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===false&&e.status===503);globalThis.__fansImageEnv.OPENAI_API_KEY='independent-fictitious-openai-key';assetBad=true;
 try{await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===false&&e.status===503);}finally{assetBad=false;}
 assert.equal(calls,before);
});
test('masked provider output preserves every protected master pixel and all fixed objects exactly',async()=>{
 const before=calls,result=m.decodePng(await m.generateBirthdayPhoto(photo,'image/jpeg'));assert.equal(calls,before+1);assert.equal(result.width,1122);assert.equal(result.height,1402);
 let protectedCount=0,editableCount=0;
 for(let at=0;at<master.rgba.length;at+=4){if(blend.rgba[at+3]===0){protectedCount++;for(let c=0;c<4;c++)assert.equal(result.rgba[at+c],master.rgba[at+c]);}else editableCount++;}
 assert.ok(protectedCount>900000);assert.ok(editableCount>150000);
 for(const [x,y,label] of [[450,480,'artist face'],[500,280,'artist hat'],[300,800,'artist suit'],[515,700,'artist glass'],[600,150,'caption'],[450,1100,'bottle'],[200,1250,'cake'],[500,1340,'table'],[680,1030,'gold carving'],[970,1200,'ivory seat'],[980,1280,'gold chair base']]){
  assert.equal(pixel(blend,x,y)[3],0,label+' is outside the editable region');assert.deepEqual(pixel(result,x,y),pixel(master,x,y),label+' must stay exact');
 }
 assert.deepEqual(pixel(result,840,500),[13,143,74,255],'Right guest changes, mapped from the scene rather than canvas padding.');
 assert.equal(lastForm.get('model'),'gpt-image-1.5');assert.equal(lastForm.get('input_fidelity'),'high');assert.equal(lastForm.get('size'),'1024x1536');assert.equal(lastForm.get('n'),'1');assert.equal(lastForm.get('output_format'),'png');assert.equal(lastForm.getAll('image[]').length,2);
 assert.deepEqual(new Uint8Array(await lastForm.getAll('image[]')[0].arrayBuffer()),new Uint8Array(await readFile('design/fans/cumpleanos/canvas-v1.png')));assert.deepEqual(new Uint8Array(await lastForm.getAll('image[]')[1].arrayBuffer()),photo);
 assert.deepEqual(new Uint8Array(await lastForm.get('mask').arrayBuffer()),new Uint8Array(await readFile('design/fans/cumpleanos/mask-v1.png')));
 assert.ok(m.BIRTHDAY_PROMPT.includes('ONLY identity reference'));assert.ok(!m.BIRTHDAY_PROMPT.includes('independent-fictitious-openai-key'));
});
test('composition rejects wrong geometry and keeps scene origin separate from model padding',()=>{
 assert.throws(()=>m.compositeBirthdayPhoto(master,m.decodePng(RGB),blend));assert.throws(()=>m.compositeBirthdayPhoto(m.decodePng(RGB),generated,blend));
 assert.equal(render.sceneRect.y,128);assert.equal(render.sceneRect.height,1280);assert.equal(render.maskConvention,'alpha_zero_is_editable');assert.equal(render.blendConvention,'alpha_zero_preserves_master');
});
test('network, redirects, server errors and malformed results are uncertain and never retried',async()=>{
 for(const state of ['network','redirect','service','invalid','wrong-size']){mode=state;const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===true&&!e.message.includes('provider-private-details'));assert.equal(calls,before+1,state+' executes exactly one request');}
 mode='rejected';const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===false&&!e.message.includes('provider-private-details'));assert.equal(calls,before+1);mode='ready';assert.ok(assetReads>=4);
});
