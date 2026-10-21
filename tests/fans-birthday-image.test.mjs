import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

// Only synthetic upload/provider bytes and the versioned public campaign asset.
// Every outbound provider request is intercepted; no paid inference is executed.
const dir=await mkdtemp(resolve('work/fans-image-test-'));
globalThis.__fansImageEnv={};
const bundle=await build({stdin:{resolveDir:process.cwd(),contents:"export * from './lib/fans-birthday-image';export * from './lib/fans-png';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'fixture-env',setup(b){b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const env=globalThis.__fansImageEnv;',loader:'js'}));}}]});
await writeFile(dir+'/bundle.mjs',bundle.outputFiles[0].contents);const m=await import(pathToFileURL(dir+'/bundle.mjs'));test.after(async()=>{await rm(dir,{recursive:true,force:true});});
const render=JSON.parse(await readFile('design/fans/cumpleanos/render-v4.json','utf8'));
const master=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/master-v1.png')));
const RGB=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP4z8DA8J+BgYHhv4aRDQAbDAOUjA/9bAAAAABJRU5ErkJggg==','base64'));
// This header-only JPEG stands in for an image service's decoded fixture.
const photo=new Uint8Array([255,216,255,192,0,17,8,0,2,0,3,3,1,17,0,2,17,0,3,17,0,255,217]);
// Synthetic BMFF headers, not encoded personal photos. Images.info and its
// transform are mocked below so no HEIC decoding or provider inference occurs.
function heicFixture(major='heic',compatible=['mif1','heic']){
 const size=16+compatible.length*4,bytes=new Uint8Array(size+12),view=new DataView(bytes.buffer),text=new TextEncoder();
 view.setUint32(0,size);bytes.set(text.encode('ftyp'),4);bytes.set(text.encode(major),8);for(let i=0;i<compatible.length;i++)bytes.set(text.encode(compatible[i]),16+i*4);view.setUint32(size,12);bytes.set(text.encode('mdat'),size+4);return bytes;
}
let assetBad=false,assetReads=0,calls=0,mode='ready',lastForm=null,oversizedCanceled=0;
globalThis.__fansImageEnv.ASSETS={async fetch(req){assetReads++;const name=new URL(req.url).pathname.split('/').at(-1);assert.ok(['master-v1.png','canvas-v4.png'].includes(name),'The maskless pipeline never loads a mask or a blending matte.');return new Response(assetBad&&name==='master-v1.png'?new Uint8Array([0]):await readFile('design/fans/cumpleanos/'+name));}};
// Coordinate-coded colors detect crop/padding/scale errors that a uniform
// generated image would hide. Within each tile R varies by x and G by y.
const generated={width:1024,height:1280,rgba:new Uint8Array(1024*1280*4)};
for(let y=0;y<generated.height;y++)for(let x=0;x<generated.width;x++){const at=(y*generated.width+x)*4;generated.rgba.set([32+x%128,48+y%128,20+Math.floor(x/128)*12+Math.floor(y/128)*7,255],at);}
const generatedBytes=m.encodePng(generated);
const transparent={...generated,rgba:generated.rgba.slice()};transparent.rgba[(600*generated.width+780)*4+3]=0;
const transparentBytes=m.encodePng(transparent);
globalThis.fetch=async(url,options)=>{
 calls++;assert.equal(String(url),'https://api.openai.com/v1/images/edits','No arbitrary provider URL is reachable.');assert.equal(options.method,'POST');assert.equal(options.redirect,'manual');assert.ok(options.signal);lastForm=new FormData();for(const [name,value] of options.body)lastForm.append(name,value);
 if(mode==='network')throw new TypeError('fictitious lost response');
 if(mode==='redirect')return new Response(null,{status:307,headers:{location:'https://untrusted.example.invalid/secret'}});
 if(mode==='rejected')return Response.json({error:{message:'provider-private-details'}},{status:400});
 if(mode==='service')return Response.json({error:{message:'provider-private-details'}},{status:503});
 if(mode==='invalid')return Response.json({data:[{b64_json:'AAAA'}]});
 if(mode==='oversized')return new Response(new ReadableStream({cancel(){oversizedCanceled++;}},{highWaterMark:0}),{headers:{'content-length':String(8*1024*1024+1)}});
 if(mode==='wrong-size')return Response.json({data:[{b64_json:Buffer.from(RGB).toString('base64')}]});
 if(mode==='transparent')return Response.json({data:[{b64_json:Buffer.from(transparentBytes).toString('base64')}]});
 return Response.json({data:[{b64_json:Buffer.from(generatedBytes).toString('base64')}]});
};
const pixel=(image,x,y)=>Array.from(image.rgba.subarray((y*image.width+x)*4,(y*image.width+x)*4+4));
function expectedGradient(x,y){
 const sx=Math.max(0,Math.min(1023,(x+.5)*1024/master.width-.5)),sy=Math.max(0,Math.min(1279,(y+.5)*1280/master.height-.5));
 assert.equal(Math.floor(sx/128),Math.floor(Math.ceil(sx)/128),'Fixture sample stays within an x color tile.');assert.equal(Math.floor(sy/128),Math.floor(Math.ceil(sy)/128),'Fixture sample stays within a y color tile.');
 const color=[32+sx%128,48+sy%128,20+Math.floor(sx/128)*12+Math.floor(sy/128)*7];
 return [...color.map(value=>Math.round(value)),255];
}

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
test('HEIC still-image variants are decoded for dimensions then transformed into a fresh bounded JPEG',async()=>{
 const before=calls,previous=globalThis.__fansImageEnv.IMAGES;let expected,events=[];
 globalThis.__fansImageEnv.IMAGES={async info(stream){events.push('info');assert.deepEqual(new Uint8Array(await new Response(stream).arrayBuffer()),expected);return {width:4032,height:3024};},input(stream){events.push('input');return {transform(options){assert.deepEqual(options,{width:1536,height:1536,fit:'scale-down'});return {async output(options){events.push('output');assert.deepEqual(options,{format:'image/jpeg',quality:90});assert.deepEqual(new Uint8Array(await new Response(stream).arrayBuffer()),expected,'The transform receives a fresh complete stream after inspecting dimensions.');return {response:()=>new Response(photo,{headers:{'content-type':'image/jpeg'}})};}};}};}};
 try{
  for(const [major,compatible,mime] of [['heic',['mif1','heic'],'image/heic'],['heix',['mif1','heix'],'image/heic'],['heim',['mif1','heim'],'image/heic'],['heis',['mif1','heis'],'image/heic'],['mif1',['mif1','heic'],'image/heif']]){
   expected=heicFixture(major,compatible);events=[];const normalized=await m.normalizeBirthdayUpload(expected,mime);assert.deepEqual(events,['info','input','output']);assert.equal(normalized.mimeType,'image/jpeg');assert.deepEqual(normalized.bytes,photo);assert.notDeepEqual(normalized.bytes,expected,'Raw HEIC is not kept or forwarded as the normalized source.');
  }
 }finally{globalThis.__fansImageEnv.IMAGES=previous;}
 assert.equal(calls,before,'Normalization never sends an OpenAI request.');
});
test('HEIC rejects movie/AVIF brands, malformed containers and unsafe decoded dimensions before transformation',async()=>{
 const before=calls,previous=globalThis.__fansImageEnv.IMAGES;let inspected=0,transforms=0,info={width:4032,height:3024},infoError=false;
 globalThis.__fansImageEnv.IMAGES={async info(){inspected++;if(infoError)throw Error('private HEIC decoder failure');return info;},input(){transforms++;throw Error('Unsafe HEIC must never reach the image transform.');}};
 try{
  const truncated=heicFixture().subarray(0,12),unaligned=heicFixture();new DataView(unaligned.buffer).setUint32(0,18);
  const incomplete=heicFixture();new DataView(incomplete.buffer).setUint32(0,incomplete.length+4);
  const misplaced=heicFixture();misplaced.set(new TextEncoder().encode('free'),4);
  const oversizedBox=new Uint8Array(4112);oversizedBox.set(heicFixture());new DataView(oversizedBox.buffer).setUint32(0,4100);
  const oversizedFile=new Uint8Array(8*1024*1024+1);oversizedFile.set(heicFixture());
  const invalid=[truncated,unaligned,incomplete,misplaced,oversizedBox,oversizedFile,heicFixture('avif',['mif1','avif','heic']),heicFixture('isom',['heic']),heicFixture('mif1',['mif1'])];
  for(const brand of ['avif','avis','msf1','hevc','hevx','hevm','hevs'])invalid.push(heicFixture('heic',['heic',brand]));
  for(const bytes of [...invalid,photo,RGB])await assert.rejects(m.normalizeBirthdayUpload(bytes,'image/heic'),e=>e.status===400&&e.paidAttempt===false);
  await assert.rejects(m.normalizeBirthdayUpload(heicFixture(),'image/jpeg'),e=>e.status===400&&e.paidAttempt===false);assert.equal(inspected,0,'Only genuine bounded still-image ftyp headers reach the decoder.');assert.equal(transforms,0);
  // A tiny forged ispe box must not override the decoded primary dimensions.
  const header=heicFixture(),forged=new Uint8Array(header.length+20),view=new DataView(forged.buffer);forged.set(header);view.setUint32(header.length,20);forged.set(new TextEncoder().encode('ispe'),header.length+4);view.setUint32(header.length+12,1);view.setUint32(header.length+16,1);
  for(const dimensions of [{width:12001,height:1},{width:8000,height:8001},{width:0,height:2},{width:NaN,height:2},{width:1.5,height:2}]){info=dimensions;await assert.rejects(m.normalizeBirthdayUpload(forged,'image/heif'),e=>e.status===400&&e.paidAttempt===false);}
  infoError=true;await assert.rejects(m.normalizeBirthdayUpload(header,'image/heic'),e=>e.status===400&&e.paidAttempt===false&&!e.message.includes('private'));assert.equal(transforms,0,'Unsafe or undecodable primary images stop before output generation.');
 }finally{globalThis.__fansImageEnv.IMAGES=previous;}
 assert.equal(calls,before,'Rejected HEIC inputs never incur an OpenAI request.');
});
test('missing key and modified master stop before any billable request',async()=>{
 const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===false&&e.status===503);globalThis.__fansImageEnv.OPENAI_API_KEY='independent-fictitious-openai-key';assetBad=true;
 try{await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===false&&e.status===503);}finally{assetBad=false;}
 assert.equal(calls,before);
});
test('maskless request supplies the complete master and fan reference without a provider mask',async()=>{
 const before=calls,result=m.decodePng(await m.generateBirthdayPhoto(photo,'image/jpeg'));assert.equal(calls,before+1);assert.equal(result.width,1122);assert.equal(result.height,1402);
 assert.equal(lastForm.get('model'),'gpt-image-2.5-sunburst-2026-09-08');assert.equal(lastForm.has('input_fidelity'),false);assert.equal(lastForm.get('quality'),'high');assert.equal(lastForm.get('size'),'1024x1280');assert.equal(lastForm.get('n'),'1');assert.equal(lastForm.get('output_format'),'png');assert.equal(lastForm.get('background'),'opaque');assert.equal(lastForm.getAll('image[]').length,2);
 assert.equal(lastForm.has('mask'),false,'No provider mask can hide part of the new glass, hand or clothing.');
 assert.deepEqual(new Uint8Array(await lastForm.getAll('image[]')[0].arrayBuffer()),new Uint8Array(await readFile('design/fans/cumpleanos/canvas-v4.png')));assert.deepEqual(new Uint8Array(await lastForm.getAll('image[]')[1].arrayBuffer()),photo);
 const instruction=lastForm.get('prompt');assert.match(instruction,/ONLY identity and wardrobe reference/);assert.match(instruction,/Preserve the actual visible outfit from image 2/);assert.match(instruction,/COMPLETE, fully visible small shot glass/);assert.match(instruction,/foreground overlap in full/);assert.match(instruction,/Do not reinterpret, beautify, age or replace him/);assert.match(instruction,/same words, spelling, lettering, colors and placement/);assert.ok(!instruction.includes('independent-fictitious-openai-key'));
 // These were protected or partially blended in v3. They must now come from
 // the coherent provider photograph instead of receiving any pasted master.
 for(const [x,y] of [[450,480],[500,285],[300,800],[515,705],[600,150],[450,1100],[200,1250],[500,1340],[570,650],[600,675],[600,720],[580,760],[675,400],[840,500],[1110,930],[870,1360],[1121,1401]])assert.deepEqual(pixel(result,x,y),expectedGradient(x,y),'Every region uses the same complete generated frame.');
});
test('full-frame rendering uses the native scene and rejects unexpected or transparent provider output',()=>{
 assert.throws(()=>m.renderBirthdayPhoto(m.decodePng(RGB)));assert.throws(()=>m.renderBirthdayPhoto({...generated,rgba:generated.rgba.subarray(0,-4)}));
 assert.deepEqual(render.sceneRect,{x:0,y:0,width:1024,height:1280});assert.equal(render.canvas.width,1024);assert.equal(render.canvas.height,1280);assert.equal(render.mode,'maskless_full_frame');assert.equal(render.providerMask,false);assert.equal('mask' in render,false);assert.equal('blend' in render,false);
 for(const alpha of [0,128,254]){const translucent={...generated,rgba:generated.rgba.slice()};translucent.rgba[(600*generated.width+780)*4+3]=alpha;assert.throws(()=>m.renderBirthdayPhoto(translucent),'An opaque full photograph is required.');}
 const solid={...generated,rgba:new Uint8Array(generated.rgba.length)};for(let at=0;at<solid.rgba.length;at+=4)solid.rgba.set([17,201,79,255],at);
 const result=m.renderBirthdayPhoto(solid);let mismatched=0;for(let at=0;at<result.rgba.length;at+=4)if(result.rgba[at]!==17||result.rgba[at+1]!==201||result.rgba[at+2]!==79||result.rgba[at+3]!==255)mismatched++;
 assert.equal(mismatched,0,'Every output pixel comes solely from the provider frame, including former master-protected areas.');
});
test('the complete new glass crosses the former velvet boundary without any mask-shaped cut',async()=>{
 // A synthetic foreground glass/hand rectangle intentionally crosses v3's
 // notch and feather. No personal photo or paid generation is used.
 const glass={...generated,rgba:generated.rgba.slice()};
 for(let y=545;y<=735;y++)for(let x=485;x<=625;x++){const at=(y*glass.width+x)*4;glass.rgba.set([231,191,42,255],at);}
 const result=m.renderBirthdayPhoto(glass),former=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/blend-v3.png')));let formerlyProtected=0,formerlyBlended=0,formerlyEditable=0;
 // This rectangle spans the old hidden-cup area on the artist's velvet and
 // extends into the companion's old hand. Its interior must remain continuous.
 for(let y=610;y<=790;y++)for(let x=540;x<=680;x++){
  assert.deepEqual(pixel(result,x,y),[231,191,42,255],'A new foreground object must not be cut by the former outline.');
  const alpha=pixel(former,x,y)[3];if(alpha===0)formerlyProtected++;else if(alpha===255)formerlyEditable++;else formerlyBlended++;
 }
 assert.ok(formerlyProtected>5000&&formerlyBlended>0&&formerlyEditable>5000,'The fixture genuinely crosses both sides and the old feather.');
});
test('complete opaque reference and immutable approved master match their manifests and public copies',async()=>{
 for(const spec of [render.master,render.canvas]){const design=new Uint8Array(await readFile('design/fans/cumpleanos/'+spec.file)),published=new Uint8Array(await readFile('public/cumpleanos/'+spec.file));assert.equal(design.length,spec.bytes);assert.equal(createHash('sha256').update(design).digest('hex'),spec.sha256);assert.deepEqual(published,design);const decoded=m.decodePng(design);assert.equal(decoded.width,spec.width);assert.equal(decoded.height,spec.height);for(let at=3;at<decoded.rgba.length;at+=4)assert.equal(decoded.rgba[at],255,'The full scene remains visible to the provider without erased regions.');}
 assert.equal(render.master.sha256,'155f37db37855cc4af04ca5a88260211526ed21c56477b4d9e5c0d4e4dcdbbc4','The original approved asset stays immutable, independently of generative output fidelity.');
 const canvas=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/canvas-v4.png')));
 for(const [x,y] of [[450,480],[600,150],[810,280],[650,865],[970,1200]]){const cx=Math.floor((x+.5)*1024/master.width),cy=Math.floor((y+.5)*1280/master.height);assert.ok(pixel(canvas,cx,cy).slice(0,3).some(value=>value>0),'Both people and the scene are supplied as the full reference.');}
});
test('network, redirects, server errors and malformed results are uncertain and never retried',async()=>{
 for(const state of ['network','redirect','service','invalid','oversized','wrong-size','transparent']){mode=state;const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===true&&!e.message.includes('provider-private-details'));assert.equal(calls,before+1,state+' executes exactly one request');}
 assert.equal(oversizedCanceled,1,'An oversized provider body is canceled without reading or retaining it, and the processing permit is released.');
 mode='rejected';const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===false&&!e.message.includes('provider-private-details'));assert.equal(calls,before+1);mode='ready';assert.ok(assetReads>=2);
});
test('ten provider calls start together while only one response body is materialized at a time',{timeout:30000},async()=>{
 const previous=globalThis.fetch,payload=new TextEncoder().encode(JSON.stringify({data:[{b64_json:Buffer.from(generatedBytes).toString('base64')}]}));
 let requested=0,reads=0,activeReads=0,maximumReads=0,notifyRequests,notifyFirstRead,releaseFirst;
 const allRequested=new Promise(resolve=>{notifyRequests=resolve;}),firstRead=new Promise(resolve=>{notifyFirstRead=resolve;}),allowFirst=new Promise(resolve=>{releaseFirst=resolve;});
 const forms=[];
 globalThis.fetch=async(url,options)=>{
  assert.equal(String(url),'https://api.openai.com/v1/images/edits');forms.push(options.body);requested++;if(requested===10)notifyRequests();
  // HWM0 prevents eager stream pulls before generateBirthdayPhoto acquires its
  // processing permit, so a pull measures an actual response-body read.
  return new Response(new ReadableStream({async pull(controller){
   reads++;activeReads++;maximumReads=Math.max(maximumReads,activeReads);
   if(reads===1){notifyFirstRead();await allowFirst;}
   await Promise.resolve();controller.enqueue(payload);controller.close();activeReads--;
  }},{highWaterMark:0}));
 };
 const jobs=Array.from({length:10},()=>m.generateBirthdayPhoto(photo,'image/jpeg'));
 try{
  await Promise.all([allRequested,firstRead]);assert.equal(requested,10,'The processing permit must not serialize paid provider requests.');assert.equal(reads,1,'Other complete JSON bodies stay unread while the first body is gated.');
  for(const form of forms)assert.equal(form.has('image[]'),false,'Multipart image references are released once response headers arrive.');
  releaseFirst();const results=await Promise.all(jobs);assert.equal(reads,10);assert.equal(maximumReads,1,'Only one provider body is held for decoding at a time.');for(const bytes of results)assert.deepEqual(Array.from(bytes.subarray(0,8)),[137,80,78,71,13,10,26,10]);
 }finally{releaseFirst();await Promise.allSettled(jobs);globalThis.fetch=previous;}
});
