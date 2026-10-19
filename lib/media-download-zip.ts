// ZIP64 STORE: stream original media without recoding it or buffering a video
// or the whole archive. ZIP64 also covers videos/archives larger than 4 GiB.
const encoder=new TextEncoder();
const crcTable=Uint32Array.from({length:256},(_,n)=>{for(let i=0;i<8;i++)n=(n&1)?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
export type MediaZipFile={name:string;size:number;open:(signal?:AbortSignal)=>Promise<{body:ReadableStream<Uint8Array>;check:()=>Promise<void>}>};

export function mediaArchiveName(value:string){
 let name=value.normalize('NFC').replace(/[\x00-\x1f\x7f<>:"/\\|?*]/g,' ').replace(/\s+/g,' ').trim().replace(/[. ]+$/g,'').slice(0,160)||'Sin nombre';
 if(/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name))name='_'+name;
 return name;
}
export function uniqueMediaArchiveName(name:string,used:Set<string>){
 const key=(value:string)=>value.normalize('NFC').toLocaleLowerCase('es');
 const slash=name.lastIndexOf('/'),parent=name.slice(0,slash+1),leaf=name.slice(slash+1),dot=leaf.lastIndexOf('.'),stem=dot>0?leaf.slice(0,dot):leaf,ext=dot>0?leaf.slice(dot):'';let next=name,n=2;
 while(used.has(key(next)))next=`${parent}${stem} (${n++})${ext}`;
 used.add(key(next));return next;
}
function bytes(length:number){const data=new Uint8Array(length);return {data,view:new DataView(data.buffer)};}
export function mediaZipLength(files:MediaZipFile[]){return files.reduce((size,file)=>size+BigInt(file.size)+BigInt(148+2*encoder.encode(file.name).length),BigInt(98)).toString();}

export async function* mediaDownloadZip(files:MediaZipFile[],signal?:AbortSignal){
 const directory:Uint8Array[]=[];let offset=BigInt(0);
 for(const file of files){
  signal?.throwIfAborted();
  const name=encoder.encode(file.name),size=BigInt(file.size),opened=await file.open(signal),reader=opened.body.getReader();
  let complete=false;const cancel=()=>{void reader.cancel().catch(()=>{});};signal?.addEventListener('abort',cancel,{once:true});
  try{
   signal?.throwIfAborted();
   const header=bytes(50+name.length),h=header.view;
   h.setUint32(0,0x04034b50,true);h.setUint16(4,45,true);h.setUint16(6,0x808,true);h.setUint16(12,33,true);
   h.setUint32(18,0xffffffff,true);h.setUint32(22,0xffffffff,true);h.setUint16(26,name.length,true);h.setUint16(28,20,true);header.data.set(name,30);
   const extra=30+name.length;h.setUint16(extra,1,true);h.setUint16(extra+2,16,true);h.setBigUint64(extra+4,size,true);h.setBigUint64(extra+12,size,true);
   yield header.data;
   let crc=0xffffffff,received=0,checkedAt=0,checkedTime=0;
   while(true){
    signal?.throwIfAborted();const {done,value}=await reader.read();if(done)break;
    received+=value.byteLength;if(received>file.size)throw new Error('El tamaño del archivo cambió durante la descarga.');
    // Revalidate before the first bytes and at most every 8 MiB, including
    // after a slow source read. Already delivered bytes cannot be recalled.
    if(checkedAt===0||received-checkedAt>=8*1024*1024||Date.now()-checkedTime>=5000){await opened.check();checkedAt=received;checkedTime=Date.now();}
    signal?.throwIfAborted();
    for(let i=0;i<value.length;i++)crc=(crc>>>8)^crcTable[(crc^value[i])&255];
    yield value;
   }
   if(received!==file.size)throw new Error('La descarga del archivo quedó incompleta.');
   await opened.check();signal?.throwIfAborted();crc=(crc^0xffffffff)>>>0;
   const descriptor=bytes(24);descriptor.view.setUint32(0,0x08074b50,true);descriptor.view.setUint32(4,crc,true);descriptor.view.setBigUint64(8,size,true);descriptor.view.setBigUint64(16,size,true);yield descriptor.data;
   const central=bytes(74+name.length),c=central.view;
   c.setUint32(0,0x02014b50,true);c.setUint16(4,45,true);c.setUint16(6,45,true);c.setUint16(8,0x808,true);c.setUint16(14,33,true);c.setUint32(16,crc,true);c.setUint32(20,0xffffffff,true);c.setUint32(24,0xffffffff,true);c.setUint16(28,name.length,true);c.setUint16(30,28,true);c.setUint32(42,0xffffffff,true);central.data.set(name,46);
   const ce=46+name.length;c.setUint16(ce,1,true);c.setUint16(ce+2,24,true);c.setBigUint64(ce+4,size,true);c.setBigUint64(ce+12,size,true);c.setBigUint64(ce+20,offset,true);directory.push(central.data);
   offset+=BigInt(header.data.length)+size+BigInt(24);complete=true;
  }finally{signal?.removeEventListener('abort',cancel);if(!complete)await reader.cancel().catch(()=>{});reader.releaseLock();}
 }
 signal?.throwIfAborted();let directorySize=BigInt(0);
 for(const entry of directory){directorySize+=BigInt(entry.length);yield entry;}
 const end=bytes(56),e=end.view,count=BigInt(directory.length);
 e.setUint32(0,0x06064b50,true);e.setBigUint64(4,BigInt(44),true);e.setUint16(12,45,true);e.setUint16(14,45,true);e.setBigUint64(24,count,true);e.setBigUint64(32,count,true);e.setBigUint64(40,directorySize,true);e.setBigUint64(48,offset,true);yield end.data;
 const locator=bytes(20);locator.view.setUint32(0,0x07064b50,true);locator.view.setBigUint64(8,offset+directorySize,true);locator.view.setUint32(16,1,true);yield locator.data;
 const legacy=bytes(22);legacy.view.setUint32(0,0x06054b50,true);legacy.view.setUint16(8,0xffff,true);legacy.view.setUint16(10,0xffff,true);legacy.view.setUint32(12,0xffffffff,true);legacy.view.setUint32(16,0xffffffff,true);yield legacy.data;
}

export function mediaZipStream(files:MediaZipFile[],requestSignal?:AbortSignal){
 const controller=new AbortController(),abort=()=>controller.abort(requestSignal?.reason);
 requestSignal?.addEventListener('abort',abort,{once:true});if(requestSignal?.aborted)abort();
 const iterator=mediaDownloadZip(files,controller.signal),clean=()=>requestSignal?.removeEventListener('abort',abort);
 return new ReadableStream<Uint8Array>({
  async pull(stream){try{const next=await iterator.next();if(next.done){clean();stream.close();}else stream.enqueue(next.value);}catch(e){clean();stream.error(e);}},
  async cancel(){controller.abort();clean();await iterator.return(undefined);}
 },{highWaterMark:0});
}
