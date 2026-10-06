const encoder = new TextEncoder();
const crcTable = Uint32Array.from({length:256}, (_, n) => {
  for (let i=0;i<8;i++) n = (n & 1) ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n >>> 0;
});

export function photoFilename(name:string, type:string, used:Set<string>) {
  let base = name.normalize('NFC').replace(/[\x00-\x1f\x7f<>:"/\\|?*]/g,' ').replace(/\s+/g,' ').trim().replace(/[. ]+$/g,'').slice(0,120) || 'Sin nombre';
  if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(base)) base = '_' + base;
  const ext = ({'image/jpeg':'jpg','image/png':'png','image/webp':'webp'} as Record<string,string>)[type];
  if (!ext) throw new Error('Formato de foto desconocido');
  let filename = `${base}.${ext}`, suffix = 2;
  while (used.has(filename.toLocaleLowerCase('es'))) filename = `${base} (${suffix++}).${ext}`;
  used.add(filename.toLocaleLowerCase('es'));
  return filename;
}

// ZIP STORE preserves original image bytes; only one photo is held in memory.
export async function* photoZip(files:AsyncIterable<{name:string;bytes:Uint8Array}>) {
  const directory:Uint8Array[]=[];
  let offset=0, count=0;
  for await (const file of files) {
    const name=encoder.encode(file.name), size=file.bytes.length;
    if (++count>65535 || offset+size+name.length+30>0xffffffff) throw new Error('ZIP demasiado grande');
    let crc=0xffffffff;
    for (const byte of file.bytes) crc=(crc>>>8)^crcTable[(crc^byte)&255];
    crc=(crc^0xffffffff)>>>0;
    const header=new Uint8Array(30+name.length), view=new DataView(header.buffer);
    view.setUint32(0,0x04034b50,true); view.setUint16(4,20,true); view.setUint16(6,0x800,true);
    view.setUint16(12,33,true); view.setUint32(14,crc,true); view.setUint32(18,size,true); view.setUint32(22,size,true); view.setUint16(26,name.length,true); header.set(name,30);
    const central=new Uint8Array(46+name.length), cv=new DataView(central.buffer);
    cv.setUint32(0,0x02014b50,true); cv.setUint16(4,20,true); cv.setUint16(6,20,true); cv.setUint16(8,0x800,true); cv.setUint16(14,33,true);
    cv.setUint32(16,crc,true); cv.setUint32(20,size,true); cv.setUint32(24,size,true); cv.setUint16(28,name.length,true); cv.setUint32(42,offset,true); central.set(name,46); directory.push(central);
    offset+=header.length+size;
    yield header; yield file.bytes;
  }
  let directorySize=0;
  for (const entry of directory) {directorySize+=entry.length; yield entry;}
  if(offset+directorySize>0xffffffff) throw new Error('ZIP demasiado grande');
  const end=new Uint8Array(22), ev=new DataView(end.buffer);
  ev.setUint32(0,0x06054b50,true); ev.setUint16(8,count,true); ev.setUint16(10,count,true); ev.setUint32(12,directorySize,true); ev.setUint32(16,offset,true);
  yield end;
}
