import {z} from 'zod';
import {PDFDocument,StandardFonts,rgb,pushGraphicsState,popGraphicsState,rectangle,clip,endPath} from 'pdf-lib';
import {CrmFailure} from './crm-core';
import {documentBrand} from './document-brand';
import logo from './document-logo.json';

export const RECEIPT_BATCH_LIMIT=20;
export const receiptBoundsSchema=z.object({
 x:z.number().int().min(0).max(999),y:z.number().int().min(0).max(999),
 width:z.number().int().min(10).max(1000),height:z.number().int().min(10).max(1000),
}).strict().refine(r=>r.x+r.width<=1000&&r.y+r.height<=1000,'El recorte debe quedar dentro de la imagen.');
export type ReceiptBounds=z.infer<typeof receiptBoundsSchema>;
export const receiptRegionsOverlap=(a:ReceiptBounds,b:ReceiptBounds)=>{
 const intersection=Math.max(0,Math.min(a.x+a.width,b.x+b.width)-Math.max(a.x,b.x))*Math.max(0,Math.min(a.y+a.height,b.y+b.height)-Math.max(a.y,b.y));
 return intersection/Math.min(a.width*a.height,b.width*b.height)>.8;
};
export const receiptRegionsSchema=z.object({receipts:z.array(receiptBoundsSchema).max(RECEIPT_BATCH_LIMIT),moreReceipts:z.boolean()}).strict();
export const receiptLayoutSchema=z.object({
 count:z.number().int().min(0).max(RECEIPT_BATCH_LIMIT),moreReceipts:z.boolean(),
 rotation:z.union([z.literal(0),z.literal(90),z.literal(180),z.literal(270)]),
 rows:z.number().int().min(0).max(RECEIPT_BATCH_LIMIT),columns:z.number().int().min(0).max(RECEIPT_BATCH_LIMIT),
}).strict().refine(v=>(v.rows===0&&v.columns===0)||(v.rows*v.columns===v.count),'El conteo y la disposición deben coincidir.');
export const receiptEdgesSchema=z.object({
 receipts:z.array(z.object({left:z.number().int().min(0).max(999),top:z.number().int().min(0).max(999),right:z.number().int().min(1).max(1000),bottom:z.number().int().min(1).max(1000)}).strict().refine(v=>v.right-v.left>=10&&v.bottom-v.top>=10)).max(RECEIPT_BATCH_LIMIT),
 moreReceipts:z.boolean(),complete:z.boolean(),
}).strict();
export const receiptBatchPlanSchema=z.object({
 operationId:z.string().uuid(),showId:z.string().trim().min(1).max(200),entrepreneur:z.string().trim().min(1).max(300),
 parts:z.array(z.object({paymentId:z.string().min(1).max(200),version:z.number().int().positive(),index:z.number().int().min(0).max(RECEIPT_BATCH_LIMIT-1),bounds:receiptBoundsSchema}).strict()).min(1).max(RECEIPT_BATCH_LIMIT),
}).strict().superRefine((p,ctx)=>{
 if(new Set(p.parts.map(r=>r.paymentId)).size!==p.parts.length)ctx.addIssue({code:'custom',message:'No puedes usar un movimiento para dos comprobantes.'});
 if(new Set(p.parts.map(r=>r.index)).size!==p.parts.length)ctx.addIssue({code:'custom',message:'Un comprobante solo se puede asignar una vez.'});
 if(p.parts.some((part,i)=>p.parts.slice(i+1).some(other=>receiptRegionsOverlap(part.bounds,other.bounds))))ctx.addIssue({code:'custom',message:'Hay recortes repetidos. Revisa cada comprobante antes de guardar.'});
});
export type ReceiptBatchPlan=z.infer<typeof receiptBatchPlanSchema>;

/** A derived support includes its individual region, the complete image and the
 * exact original file as a PDF attachment. Never mutate the original receipt. */
export async function receiptPartPDF(source:Uint8Array,sourceType:string,sourceName:string,preview:Uint8Array,index:number,bounds:ReceiptBounds|null,receipt?:{reference:string|null;row:number;column:number;amount:number|null;date:string|null}){
 const pdf=await PDFDocument.create(),fixed=new Date('2000-01-01T00:00:00Z');
 pdf.setCreationDate(fixed);pdf.setModificationDate(fixed);pdf.setProducer('JAC Music');pdf.setCreator('JAC Music');
 pdf.setTitle(`Comprobante individual ${index+1}`);
 let image;
 try{image=await pdf.embedJpg(preview);}catch{throw new CrmFailure('No se pudo preparar la imagen de los comprobantes.',400);}
 if(image.width>4096||image.height>4096||image.width<20||image.height<20)throw new CrmFailure('La vista de los comprobantes debe medir entre 20 y 4096 píxeles por lado.',400);
 const font=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold),mark=await pdf.embedPng(logo.base64);
 const color=(hex:string)=>rgb(...[0,2,4].map(i=>parseInt(hex.slice(i,i+2),16)/255) as [number,number,number]);
 const ink=color(documentBrand.ink),blue=color(documentBrand.cyan);
 const page=pdf.addPage([612,792]);
 page.drawImage(mark,{x:36,y:744,width:105,height:105*mark.height/mark.width});
 page.drawText(`Comprobante ${index+1} de imagen conjunta`,{x:36,y:725,font,size:12,color:ink});
 page.drawLine({start:{x:36,y:710},end:{x:576,y:710},thickness:2,color:blue});
 if(receipt){
  page.drawText(`Fila ${receipt.row} - Posicion ${receipt.column} | Ref. ${receipt.reference||'Sin indicar'}`,{x:36,y:693,font,size:9,color:ink});
  page.drawText(`Lectura del original: ${receipt.date||'Fecha por revisar'} | COP ${receipt.amount===null?'Valor por revisar':new Intl.NumberFormat('es-CO',{maximumFractionDigits:2}).format(receipt.amount)}`,{x:36,y:678,font,size:9,color:ink});
 }
 const hasCrop=!!bounds;bounds=bounds||{x:0,y:0,width:1000,height:1000};
 const available=receipt?580:620,w=image.width*bounds.width/1000,h=image.height*bounds.height/1000,scale=Math.min(540/w,available/h),dw=w*scale,dh=h*scale;
 const x=36+(540-dw)/2,y=76+(available-dh)/2;
 page.pushOperators(pushGraphicsState(),rectangle(x,y,dw,dh),clip(),endPath());
 page.drawImage(image,{x:x-image.width*scale*bounds.x/1000,y:y+dh-image.height*scale*(1-bounds.y/1000),width:image.width*scale,height:image.height*scale});
 page.pushOperators(popGraphicsState());
 page.drawText(hasCrop?'Recorte de referencia. Imagen completa en la pagina siguiente.':'Imagen conjunta conservada. Recibo indicado por su referencia y posicion.',{x:36,y:45,font,size:9,color:ink});
 const full=pdf.addPage([612,792]),fit=Math.min(540/image.width,660/image.height);
 full.drawImage(mark,{x:36,y:744,width:105,height:105*mark.height/mark.width});
 full.drawText('IMAGEN COMPLETA',{x:165,y:750,font:bold,size:12,color:ink});
 full.drawImage(image,{x:(612-image.width*fit)/2,y:66+(660-image.height*fit)/2,width:image.width*fit,height:image.height*fit});
 full.drawText('El archivo original también se conserva adjunto dentro de este PDF.',{x:36,y:40,font,size:9,color:ink});
 await pdf.attach(source,sourceName,{mimeType:sourceType,description:'Archivo original de la imagen conjunta',creationDate:fixed,modificationDate:fixed});
 return pdf.save({useObjectStreams:false,addDefaultPage:false});
}
