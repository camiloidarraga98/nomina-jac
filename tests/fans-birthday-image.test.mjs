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
const render=JSON.parse(await readFile('design/fans/cumpleanos/render-v3.json','utf8'));
const master=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/master-v1.png'))),blend=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/blend-v3.png')));
const RGB=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP4z8DA8J+BgYHhv4aRDQAbDAOUjA/9bAAAAABJRU5ErkJggg==','base64'));
// This header-only JPEG stands in for an image service's decoded fixture.
const photo=new Uint8Array([255,216,255,192,0,17,8,0,2,0,3,3,1,17,0,2,17,0,3,17,0,255,217]);
// Synthetic BMFF headers, not encoded personal photos. Images.info and its
// transform are mocked below so no HEIC decoding or provider inference occurs.
function heicFixture(major='heic',compatible=['mif1','heic']){
 const size=16+compatible.length*4,bytes=new Uint8Array(size+12),view=new DataView(bytes.buffer),text=new TextEncoder();
 view.setUint32(0,size);bytes.set(text.encode('ftyp'),4);bytes.set(text.encode(major),8);for(let i=0;i<compatible.length;i++)bytes.set(text.encode(compatible[i]),16+i*4);view.setUint32(size,12);bytes.set(text.encode('mdat'),size+4);return bytes;
}
let assetBad=false,assetReads=0,calls=0,mode='ready',lastForm=null;
globalThis.__fansImageEnv.ASSETS={async fetch(req){assetReads++;const name=new URL(req.url).pathname.split('/').at(-1);assert.ok(['master-v1.png','canvas-v3.png','mask-v3.png','blend-v3.png'].includes(name));return new Response(assetBad&&name==='master-v1.png'?new Uint8Array([0]):await readFile('design/fans/cumpleanos/'+name));}};
// Coordinate-coded colors detect crop/padding/scale errors that a uniform
// generated image would hide. Within each tile R varies by x and G by y.
const generated={width:1024,height:1280,rgba:new Uint8Array(1024*1280*4)};
for(let y=0;y<generated.height;y++)for(let x=0;x<generated.width;x++){const at=(y*generated.width+x)*4;generated.rgba.set([32+x%128,48+y%128,20+Math.floor(x/128)*12+Math.floor(y/128)*7,255],at);}
const generatedBytes=m.encodePng(generated);
const transparent={...generated,rgba:generated.rgba.slice()};transparent.rgba[(600*generated.width+780)*4+3]=0;
const transparentBytes=m.encodePng(transparent);
globalThis.fetch=async(url,options)=>{
 calls++;assert.equal(String(url),'https://api.openai.com/v1/images/edits','No arbitrary provider URL is reachable.');assert.equal(options.method,'POST');assert.equal(options.redirect,'manual');assert.ok(options.signal);lastForm=options.body;
 if(mode==='network')throw new TypeError('fictitious lost response');
 if(mode==='redirect')return new Response(null,{status:307,headers:{location:'https://untrusted.example.invalid/secret'}});
 if(mode==='rejected')return Response.json({error:{message:'provider-private-details'}},{status:400});
 if(mode==='service')return Response.json({error:{message:'provider-private-details'}},{status:503});
 if(mode==='invalid')return Response.json({data:[{b64_json:'AAAA'}]});
 if(mode==='wrong-size')return Response.json({data:[{b64_json:Buffer.from(RGB).toString('base64')}]});
 if(mode==='transparent')return Response.json({data:[{b64_json:Buffer.from(transparentBytes).toString('base64')}]});
 return Response.json({data:[{b64_json:Buffer.from(generatedBytes).toString('base64')}]});
};
const pixel=(image,x,y)=>Array.from(image.rgba.subarray((y*image.width+x)*4,(y*image.width+x)*4+4));
function expectedGradient(x,y,weight=255){
 const sx=Math.max(0,Math.min(1023,(x+.5)*1024/master.width-.5)),sy=Math.max(0,Math.min(1279,(y+.5)*1280/master.height-.5));
 assert.equal(Math.floor(sx/128),Math.floor(Math.ceil(sx)/128),'Fixture sample stays within an x color tile.');assert.equal(Math.floor(sy/128),Math.floor(Math.ceil(sy)/128),'Fixture sample stays within a y color tile.');
 const color=[32+sx%128,48+sy%128,20+Math.floor(sx/128)*12+Math.floor(sy/128)*7],fixed=pixel(master,x,y);
 return [...color.map((value,c)=>Math.round(fixed[c]*(1-weight/255)+value*weight/255)),255];
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
test('masked provider output preserves every protected master pixel and all fixed objects exactly',async()=>{
 const before=calls,result=m.decodePng(await m.generateBirthdayPhoto(photo,'image/jpeg'));assert.equal(calls,before+1);assert.equal(result.width,1122);assert.equal(result.height,1402);
 let protectedCount=0,editableCount=0;
 for(let at=0;at<master.rgba.length;at+=4){if(blend.rgba[at+3]===0){protectedCount++;for(let c=0;c<4;c++)assert.equal(result.rgba[at+c],master.rgba[at+c]);}else editableCount++;}
 assert.ok(protectedCount>650000);assert.ok(editableCount>300000);
 for(const [x,y,label] of [[450,480,'artist face'],[500,280,'artist hat'],[300,800,'artist suit'],[515,700,'artist glass'],[600,150,'caption'],[450,1100,'bottle'],[200,1250,'cake'],[500,1340,'table']]){
  assert.equal(pixel(blend,x,y)[3],0,label+' is outside the editable region');assert.deepEqual(pixel(result,x,y),pixel(master,x,y),label+' must stay exact');
 }
 for(const [x,y] of [[840,500],[1110,930],[870,1360],[1121,1401]])assert.deepEqual(pixel(result,x,y),expectedGradient(x,y),'Generated coordinates map across the complete native scene.');
 assert.equal(lastForm.get('model'),'gpt-image-2.5-sunburst-2026-09-08');assert.equal(lastForm.has('input_fidelity'),false);assert.equal(lastForm.get('quality'),'high');assert.equal(lastForm.get('size'),'1024x1280');assert.equal(lastForm.get('n'),'1');assert.equal(lastForm.get('output_format'),'png');assert.equal(lastForm.getAll('image[]').length,2);
 assert.deepEqual(new Uint8Array(await lastForm.getAll('image[]')[0].arrayBuffer()),new Uint8Array(await readFile('design/fans/cumpleanos/canvas-v3.png')));assert.deepEqual(new Uint8Array(await lastForm.getAll('image[]')[1].arrayBuffer()),photo);
 assert.deepEqual(new Uint8Array(await lastForm.get('mask').arrayBuffer()),new Uint8Array(await readFile('design/fans/cumpleanos/mask-v3.png')));
 const instruction=lastForm.get('prompt');assert.match(instruction,/ONLY identity and wardrobe reference/);assert.match(instruction,/Preserve the actual visible outfit from image 2/);assert.ok(!instruction.includes('independent-fictitious-openai-key'));
});
test('composition uses the native full-frame scene and rejects geometry or transparent provider output',()=>{
 assert.throws(()=>m.compositeBirthdayPhoto(master,m.decodePng(RGB),blend));assert.throws(()=>m.compositeBirthdayPhoto(m.decodePng(RGB),generated,blend));
 assert.deepEqual(render.sceneRect,{x:0,y:0,width:1024,height:1280});assert.equal(render.canvas.width,1024);assert.equal(render.canvas.height,1280);assert.equal(render.maskConvention,'alpha_zero_is_editable');assert.equal(render.blendConvention,'alpha_zero_preserves_master');
 for(const alpha of [0,128,254]){const translucent={...generated,rgba:generated.rgba.slice()};translucent.rgba[(600*generated.width+780)*4+3]=alpha;assert.throws(()=>m.compositeBirthdayPhoto(master,translucent,blend),'Transparent output cannot expose the previous companion through the patch.');}
 const result=m.compositeBirthdayPhoto(master,generated,blend);let transition=null;
 for(let y=0;y<master.height&&!transition;y++)for(let x=0;x<master.width;x++){const weight=pixel(blend,x,y)[3],sx=(x+.5)*1024/master.width-.5,sy=(y+.5)*1280/master.height-.5;if(weight>0&&weight<255&&sx>1&&sy>1&&sx<1022&&sy<1278&&sx%128<126&&sy%128<126){transition={x,y,weight};break;}}
 assert.ok(transition,'The expanded region still has a controlled soft boundary.');assert.deepEqual(pixel(result,transition.x,transition.y),expectedGradient(transition.x,transition.y,transition.weight),'Only the declared feather weight mixes with the master.');
});
test('expanded mask replaces the whole old companion and no longer freezes chair gaps or silhouette edges',async()=>{
 const fullyEditable=[
  [810,280,'old red hat'],[840,500,'old face'],[850,640,'old black shirt'],[610,755,'old raised hand'],[650,865,'old forearm'],[1000,1080,'old resting hand'],[860,1280,'old trouser leg'],
  [750,900,'old arm-to-body chair gap'],[750,980,'old torso-to-leg chair gap'],[970,1200,'formerly frozen cushion'],[980,1280,'formerly frozen chair base'],
  [1020,450,'space for wider hair'],[1010,600,'space for long hair'],[1080,760,'space for wider clothing'],[1020,1300,'space beyond the old trouser outline'],
 ];
 for(const [x,y,label] of fullyEditable)assert.equal(pixel(blend,x,y)[3],255,label+' must be fully replaced, not partially retain the old man.');
 const former=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/blend-v1.png')));
 // V1 accidentally included a few green artist pixels beside the toast. V2
 // correctly protects those; all remaining old editable pixels must be new.
 for(let at=3;at<former.rgba.length;at+=4)if(former.rgba[at]>0&&blend.rgba[at]>0)assert.equal(blend.rgba[at],255,'The entire previous editable silhouette must be replaced, including its hand and clothing edges.');
 for(const y of [610,750,950,1100,1250,1401])assert.equal(pixel(blend,1121,y)[3],255,'Right frame edge must not clip the newly generated body.');
 for(const x of [850,950,1050,1121])assert.equal(pixel(blend,x,1401)[3],255,'Bottom of the guest area must not retain old legs or chair.');
});
test('provider template contains no visible or hidden RGB identity in the erased guest area',async()=>{
 const canvas=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/canvas-v3.png'))),mask=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/mask-v3.png')));
 assert.equal(canvas.width,1024);assert.equal(canvas.height,1280);assert.equal(mask.width,canvas.width);assert.equal(mask.height,canvas.height);let erased=0,preserved=0;
 for(let at=0;at<canvas.rgba.length;at+=4){const opacity=mask.rgba[at+3];assert.ok(opacity===0||opacity===255,'The edit mask has an unambiguous binary convention.');if(opacity===0){erased++;assert.equal(canvas.rgba[at]|canvas.rgba[at+1]|canvas.rgba[at+2]|canvas.rgba[at+3],0,'Erased placeholder pixels cannot bias the fan identity.');}else{preserved++;assert.equal(canvas.rgba[at+3],255,'Protected parts of the reference remain opaque.');}}
 assert.ok(erased>250000);assert.ok(preserved>450000);
 for(const [x,y] of [[810,280],[650,865],[970,1200],[1121,1401]]){const cx=Math.min(1023,Math.floor((x+.5)*1024/master.width)),cy=Math.min(1279,Math.floor((y+.5)*1280/master.height));assert.equal(pixel(mask,cx,cy)[3],0);assert.deepEqual(pixel(canvas,cx,cy),[0,0,0,0]);}
});
test('upper-left hair and head stay completely opaque without leaking the old curtain or changing the toast',async()=>{
 const canvas=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/canvas-v3.png'))),mask=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/mask-v3.png'))),previous=m.decodePng(new Uint8Array(await readFile('design/fans/cumpleanos/blend-v2.png')));
 // This was the visible 20-pixel fade through the fan's hair/head in v2.
 // Verify the whole region rather than just one fortunate hairstyle sample.
 for(let y=300;y<=580;y++)for(let x=670;x<=700;x++){
  assert.equal(pixel(blend,x,y)[3],255,'Every hair/head pixel in the former fading band must come entirely from the generated person.');
  const cx=Math.floor((x+.5)*1024/master.width),cy=Math.floor((y+.5)*1280/master.height);
  assert.equal(pixel(mask,cx,cy)[3],0,'The model receives the entire former fading band as editable.');assert.deepEqual(pixel(canvas,cx,cy),[0,0,0,0],'No old curtain or companion can remain as an input image patch behind the new hair.');
 }
 const result=m.compositeBirthdayPhoto(master,generated,blend);
 for(const [x,y] of [[675,400],[680,500],[690,570],[700,300]])assert.deepEqual(pixel(result,x,y),expectedGradient(x,y),'The opaque hair/head interior gets the exact generated colors, with no curtain blending or extra color filter.');
 const lowerStart=650*master.width*4;
 assert.ok(Buffer.from(blend.rgba).subarray(lowerStart).equals(Buffer.from(previous.rgba).subarray(lowerStart)),'The lower blend and all toast/artist boundaries remain identical to the accepted v2 region.');
 for(const [x,y] of [[450,480],[500,280],[515,700],[450,1100],[200,1250],[500,1340]])assert.deepEqual(pixel(result,x,y),pixel(master,x,y),'The artist and protected foreground remain exact.');
});
test('versioned master, erased canvas and masks match their manifests and public copies',async()=>{
 for(const spec of [render.master,render.canvas,render.mask,render.blend]){const design=new Uint8Array(await readFile('design/fans/cumpleanos/'+spec.file)),published=new Uint8Array(await readFile('public/cumpleanos/'+spec.file));assert.equal(design.length,spec.bytes);assert.equal(createHash('sha256').update(design).digest('hex'),spec.sha256);assert.deepEqual(published,design);const decoded=m.decodePng(design);assert.equal(decoded.width,spec.width);assert.equal(decoded.height,spec.height);}
 assert.equal(render.master.sha256,'155f37db37855cc4af04ca5a88260211526ed21c56477b4d9e5c0d4e4dcdbbc4','The approved artist/photo master stays immutable.');
});
test('network, redirects, server errors and malformed results are uncertain and never retried',async()=>{
 for(const state of ['network','redirect','service','invalid','wrong-size','transparent']){mode=state;const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===true&&!e.message.includes('provider-private-details'));assert.equal(calls,before+1,state+' executes exactly one request');}
 mode='rejected';const before=calls;await assert.rejects(m.generateBirthdayPhoto(photo,'image/jpeg'),e=>e.paidAttempt===false&&!e.message.includes('provider-private-details'));assert.equal(calls,before+1);mode='ready';assert.ok(assetReads>=4);
});
