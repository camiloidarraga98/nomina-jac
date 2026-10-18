import {fileMime} from '@/lib/notice-files';
import {CRM_RECEIPT_LIMIT,CRM_RECEIPT_BYTES} from '@/lib/crm-receipts';
export type CrmFile={filename:string;data:string;size:number;mimeType:string};
export async function encodeCrmFile(file:File):Promise<CrmFile>{
 if(!file.size||file.size>CRM_RECEIPT_BYTES)throw Error('Los comprobantes deben sumar como máximo 10 MB.');
 const mimeType=fileMime(new Uint8Array(await file.slice(0,12).arrayBuffer()));
 return new Promise((resolve,reject)=>{const reader=new FileReader();reader.onerror=()=>reject(Error('No pudimos leer '+file.name));reader.onload=()=>resolve({filename:Array.from(file.name).slice(0,70).join(''),data:String(reader.result).split(',')[1]||'',size:file.size,mimeType});reader.readAsDataURL(file);});
}
export async function prepareCrmFiles(current:CrmFile[],incoming:File[]){
 if(incoming.length+current.length>CRM_RECEIPT_LIMIT)throw Error('Puedes adjuntar hasta cinco comprobantes por abono.');
 if(incoming.reduce((n,f)=>n+f.size,0)+current.reduce((n,f)=>n+f.size,0)>CRM_RECEIPT_BYTES)throw Error('Los comprobantes deben sumar como máximo 10 MB.');
 const prepared=await Promise.all(incoming.map(encodeCrmFile)),files=[...current];
 for(const file of prepared)if(!files.some(f=>f.data===file.data))files.push(file);
 return files;
}
export const crmFilePayload=(files:CrmFile[])=>files.map(({filename,data})=>({filename,data}));
