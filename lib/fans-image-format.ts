// HEIC is an ISO BMFF container. Inspect the actual ftyp box, not its filename,
// MIME declaration or a matching string inside media payloads. Images still
// decodes the complete file before any bytes are stored or sent to OpenAI.
export function isBirthdayHEIC(bytes:Uint8Array){
 if(bytes.length<16)return false;
 const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
 const fourcc=(at:number)=>String.fromCharCode(...bytes.subarray(at,at+4));
 const size=view.getUint32(0);
 if(fourcc(4)!=='ftyp'||size<16||size>4096||size>bytes.length||size%4!==0)return false;
 const major=fourcc(8),brands=[major];
 for(let at=16;at<size;at+=4)brands.push(fourcc(at));
 const still=['heic','heix','heim','heis'];
 if(![...still,'mif1'].includes(major))return false;
 if(brands.some(brand=>['avif','avis','msf1','hevc','hevx','hevm','hevs'].includes(brand)))return false;
 return brands.some(brand=>still.includes(brand));
}
