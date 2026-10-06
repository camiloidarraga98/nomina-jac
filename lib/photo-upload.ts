// Resize in the visitor's browser so phone photos fit the request envelope.
export async function preparePhoto(file: File): Promise<File> {
 const url=URL.createObjectURL(file);
 try {
  const image=new Image(); image.src=url;
  await image.decode();
  if(!image.naturalWidth||!image.naturalHeight)throw new Error('No pudimos leer la foto. Selecciona otra imagen.');
  const canvas=document.createElement('canvas');
  const scale=Math.min(1,1200/Math.max(image.naturalWidth,image.naturalHeight));
  canvas.width=Math.max(1,Math.round(image.naturalWidth*scale));canvas.height=Math.max(1,Math.round(image.naturalHeight*scale));
  const ctx=canvas.getContext('2d');if(!ctx)throw new Error('No pudimos preparar la foto. Prueba con otra imagen.');
  for(let attempt=0;attempt<6;attempt++){
   ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,0,0,canvas.width,canvas.height);
   const blob=await new Promise<Blob|null>(resolve=>canvas.toBlob(resolve,'image/jpeg',Math.max(.5,.85-attempt*.07)));
   if(blob&&blob.size<=350*1024)return new File([blob],'rostro.jpg',{type:'image/jpeg'});
   canvas.width=Math.max(1,Math.round(canvas.width*.8));canvas.height=Math.max(1,Math.round(canvas.height*.8));
  }
  throw new Error('No pudimos reducir esta foto. Prueba con otra imagen de tu rostro.');
 }catch(error){throw new Error(error instanceof Error&&!['EncodingError','InvalidStateError'].includes(error.name)?error.message:'No pudimos leer esta foto. Elige otra en formato JPG, PNG o WebP.')}finally{URL.revokeObjectURL(url)}
}
export async function readRegistrationResponse(response:Response):Promise<string>{
 if(response.status===413)throw new Error('La foto supera el tamaño permitido. Selecciona otra foto más pequeña e intenta de nuevo.');
 let data: {id?:unknown;error?:unknown};
 try{data=JSON.parse(await response.text())}catch{throw new Error('No pudimos confirmar el registro. Intenta de nuevo en un momento; tus datos siguen en el formulario.')}
 if(!response.ok)throw new Error(typeof data?.error==='string'?data.error:'No pudimos guardar tu registro. Intenta de nuevo.');
 if(typeof data?.id!=='string'||!data.id)throw new Error('No pudimos confirmar el registro. Intenta de nuevo en un momento.');
 return data.id;
}
