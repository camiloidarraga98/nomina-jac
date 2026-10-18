'use client';
import {useState} from 'react';
import {zipSync,strToU8,type Zippable} from 'fflate';

export default function HostingTransfer({enabled}:{enabled:boolean}){
 const [busy,setBusy]=useState(false),[status,setStatus]=useState(''),[error,setError]=useState('');
 async function run(){
  if(busy||!enabled)return;setBusy(true);setError('');let url:string|undefined;
  try{
   const files:Zippable={};let size=0;
   const request=async(payload:unknown)=>{const r=await fetch('/api/hosting-transfer',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload),cache:'no-store'});if(!r.ok)throw Error('La autorización venció o un archivo cambió. Conservamos los originales; vuelve a preparar la copia.');const bytes=new Uint8Array(await r.arrayBuffer());size+=bytes.length;if(size>256*1024*1024)throw Error('La copia supera el límite de esta sesión. Necesitamos dividirla antes de continuar.');return bytes;};
   setStatus('Cifrando la base de datos…');files['database.json']=await request({action:'database'});
   setStatus('Protegiendo las conexiones…');files['secrets.json']=await request({action:'secrets'});
   // The browser never decrypts the export. Object identifiers are returned by
   // an authenticated inventory action while every downloaded byte is sealed.
   const inventoryResponse=await fetch('/api/hosting-transfer-inventory',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}',cache:'no-store'});
   if(!inventoryResponse.ok)throw Error('No pudimos revisar los documentos.');
   const inventory=await inventoryResponse.json() as {objects:{key:string;size:number;etag:string}[]};
   files['manifest.json']=strToU8(JSON.stringify({format:'jac-transfer-archive-v1',createdAt:new Date().toISOString(),files:inventory.objects.length}));
   for(let i=0;i<inventory.objects.length;i++){
    const object=inventory.objects[i];if(object.size>100*1024*1024)throw Error('Un documento necesita un traslado dividido.');
    setStatus('Cifrando documentos: '+(i+1)+' de '+inventory.objects.length+'…');
    for(let offset=0;offset<Math.max(object.size,1);offset+=1024*1024)files['objects/'+i+'/'+offset+'.json']=await request({action:'object',key:object.key,etag:object.etag,offset});
   }
   setStatus('Preparando el archivo cifrado…');const zip=zipSync(files,{level:0});
   url=URL.createObjectURL(new Blob([new Uint8Array(zip).buffer],{type:'application/zip'}));
   const a=document.createElement('a');a.href=url;a.download='JAC-traslado-cifrado.zip';a.click();
   setStatus('Copia cifrada preparada. No se modificaron los originales.');
  }catch(e){setError((e as Error).message);}finally{setBusy(false);if(url)setTimeout(()=>URL.revokeObjectURL(url!),60000);}
 }
 return <section><button className="btn primary" disabled={!enabled||busy} onClick={run}>{busy?'Preparando…':'Crear copia cifrada para Cloudflare'}</button>{!enabled&&<p>El traslado todavía no está habilitado o su autorización venció.</p>}{status&&<p role="status">{status}</p>}{error&&<p role="alert">{error}</p>}</section>;
}
