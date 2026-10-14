export const CRM_RECEIPT_LIMIT=5;
export const CRM_RECEIPT_BYTES=10*1024*1024;
export function crmReceiptBase(title:string){
 const base=title.normalize('NFC').replace(/[^\p{L}\p{N}._-]+/gu,'-').replace(/^[.\-]+|[.\-]+$/g,'');
 return Array.from(base||'Show').slice(0,100).join('');
}
export const crmReceiptExtension=(mimeType:string)=>mimeType==='application/pdf'?'.pdf':mimeType==='image/png'?'.png':'.jpg';
export const crmReceiptName=(title:string,sequence:number,mimeType:string)=>crmReceiptBase(title)+'-'+sequence+crmReceiptExtension(mimeType);
