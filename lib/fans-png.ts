import {unzlibSync,zlibSync} from 'fflate';

export type PngImage={width:number;height:number;rgba:Uint8Array};
const signature=new Uint8Array([137,80,78,71,13,10,26,10]);
const crcTable=Uint32Array.from({length:256},(_,value)=>{for(let n=0;n<8;n++)value=value&1?0xedb88320^(value>>>1):value>>>1;return value>>>0;});
function crc(bytes:Uint8Array,start:number,end:number){let value=0xffffffff;for(let i=start;i<end;i++)value=crcTable[(value^bytes[i])&255]^(value>>>8);return (value^0xffffffff)>>>0;}
function u32(bytes:Uint8Array,at:number){return new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength).getUint32(at);}
function fail():never{throw new Error('La imagen PNG no es válida o supera los límites.');}
function join(arrays:Uint8Array[]){const out=new Uint8Array(arrays.reduce((n,a)=>n+a.length,0));let offset=0;for(const a of arrays){out.set(a,offset);offset+=a.length;}return out;}
function adler(bytes:Uint8Array){let a=1,b=0;for(let start=0;start<bytes.length;start+=5552){for(let i=start;i<Math.min(start+5552,bytes.length);i++){a+=bytes[i];b+=a;}a%=65521;b%=65521;}return ((b<<16)|a)>>>0;}
function paeth(a:number,b:number,c:number){const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);return pa<=pb&&pa<=pc?a:pb<=pc?b:c;}

// Small bounded PNG reader for the fixed template and provider PNG output.
// No metadata or profiles are copied into the final file. Pixel values outside
// the editable area are copied directly from the approved master RGBA buffer.
export function decodePng(bytes:Uint8Array,maxPixels=2_000_000):PngImage{
 if(bytes.length<45||bytes.length>16*1024*1024||!signature.every((v,i)=>v===bytes[i]))fail();
 let width=0,height=0,type=-1,channels=0,offset=8,ended=false,sawData=false,dataEnded=false,palette:Uint8Array|null=null,transparency:Uint8Array|null=null;
 const data:Uint8Array[]=[];
 while(offset+12<=bytes.length){
  const length=u32(bytes,offset),end=offset+12+length;if(end>bytes.length)fail();
  const tag=String.fromCharCode(...bytes.subarray(offset+4,offset+8)),body=bytes.subarray(offset+8,end-4);
  if(crc(bytes,offset+4,end-4)!==u32(bytes,end-4))fail();
  if(!width&&tag!=='IHDR')fail();
  if(tag==='IHDR'){
   if(width||length!==13)fail();width=u32(body,0);height=u32(body,4);type=body[9];channels=({0:1,2:3,3:1,4:2,6:4} as Record<number,number>)[type]??0;
   if(!width||!height||width>4096||height>4096||width*height>maxPixels||body[8]!==8||!channels||body[10]!==0||body[11]!==0||body[12]!==0)fail();
  }else if(tag==='IDAT'){
   if(dataEnded)fail();sawData=true;data.push(body);
  }else if(tag==='IEND'){
   if(length||!sawData||end!==bytes.length)fail();ended=true;offset=end;break;
  }else{
   if(sawData)dataEnded=true;
   if(tag==='PLTE'){if(sawData||!length||length%3||length>768||palette)fail();palette=body;}
   else if(tag==='tRNS'){if(sawData||transparency)fail();transparency=body;}
   else if(tag==='acTL'||tag==='fcTL'||tag==='fdAT'||(bytes[offset+4]&32)===0)fail();
  }
  offset=end;
 }
 if(!ended||offset!==bytes.length||!data.length||type===3&&!palette)fail();
 const stride=width*channels,expected=(stride+1)*height,compressed=join(data);if(compressed.length<6)fail();
 // An extra byte detects over-inflation without allowing fflate to grow buffers.
 let filtered:Uint8Array;try{filtered=unzlibSync(compressed,{out:new Uint8Array(expected+1)});}catch{fail();}
 if(filtered.length!==expected||adler(filtered)!==u32(compressed,compressed.length-4))fail();
 const rgba=new Uint8Array(width*height*4),previous=new Uint8Array(stride),row=new Uint8Array(stride);
 for(let y=0;y<height;y++){
  const source=y*(stride+1),filter=filtered[source];if(filter>4)fail();
  for(let x=0;x<stride;x++){
   const a=x>=channels?row[x-channels]:0,b=previous[x],c=x>=channels?previous[x-channels]:0;
   row[x]=(filtered[source+1+x]+(filter===0?0:filter===1?a:filter===2?b:filter===3?(a+b)>>>1:paeth(a,b,c)))&255;
  }
  for(let x=0;x<width;x++){
   const src=x*channels,dst=(y*width+x)*4;
   if(type===2||type===6){rgba[dst]=row[src];rgba[dst+1]=row[src+1];rgba[dst+2]=row[src+2];rgba[dst+3]=type===6?row[src+3]:transparency?.length===6&&row[src]===transparency[1]&&row[src+1]===transparency[3]&&row[src+2]===transparency[5]?0:255;}
   else if(type===0||type===4){rgba[dst]=rgba[dst+1]=rgba[dst+2]=row[src];rgba[dst+3]=type===4?row[src+1]:transparency?.length===2&&row[src]===transparency[1]?0:255;}
   else {const index=row[src];if(index*3+2>=palette!.length)fail();rgba[dst]=palette![index*3];rgba[dst+1]=palette![index*3+1];rgba[dst+2]=palette![index*3+2];rgba[dst+3]=transparency&&index<transparency.length?transparency[index]:255;}
  }
  previous.set(row);
 }
 return {width,height,rgba};
}
function chunk(tag:string,body:Uint8Array){const out=new Uint8Array(body.length+12),view=new DataView(out.buffer);view.setUint32(0,body.length);for(let i=0;i<4;i++)out[i+4]=tag.charCodeAt(i);out.set(body,8);view.setUint32(out.length-4,crc(out,4,out.length-4));return out;}
export function encodePng(image:PngImage){
 const {width,height,rgba}=image;if(!width||!height||width>4096||height>4096||width*height>2_000_000||rgba.length!==width*height*4)fail();
 const header=new Uint8Array(13),view=new DataView(header.buffer);view.setUint32(0,width);view.setUint32(4,height);header[8]=8;header[9]=6;
 // PNG Sub filter is cheap and substantially reduces photo file size.
 const stride=width*4,rows=new Uint8Array((stride+1)*height);
 for(let y=0;y<height;y++){const at=y*(stride+1),src=y*stride;rows[at]=1;for(let x=0;x<stride;x++)rows[at+x+1]=(rgba[src+x]-(x>=4?rgba[src+x-4]:0))&255;}
 return join([signature,chunk('IHDR',header),chunk('IDAT',zlibSync(rows,{level:6})),chunk('IEND',new Uint8Array())]);
}
