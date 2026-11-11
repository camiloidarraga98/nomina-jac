/* Full-image OCR: the API reads payments and supplies optional reference bounds.
 * The browser only renders returned pixels. No local segmentation/count/rotation. */
(() => {
 'use strict';
 const $=s=>document.querySelector(s);
 const jpeg=canvas=>new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(Error('No se pudo preparar la foto.')),'image/jpeg',.95));
 window.JacReceiptCollection=class extends window.JacReceiptBatch {
  constructor(host){super(host);this.collectionMode=true;this.orientationVerified=true;this.collectionWarnings=[];this.evidence='';}
  dispose(){super.dispose();this.evidence='';this.collectionWarnings=[];}
  async start(file){
   this.source=file;this.setBusy(true);this.h.dirty(true);this.phase='reading-image';this.render();
   try{
    const bitmap=await createImageBitmap(file);if(!this.active){bitmap.close();return;}
    const scale=Math.min(1,4096/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);
    const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();
    const blob=await jpeg(canvas);if(!this.active)return;if(blob.size>5*1024*1024)throw Error('La vista de lectura supera 5 MB. Elige una foto de menor tamaño.');
    this.preview=new File([blob],'vista-completa.jpg',{type:'image/jpeg'});this.image=await createImageBitmap(blob);if(!this.active){this.image.close();return;}this.url=URL.createObjectURL(blob);
    await this.readImage();
   }catch(e){if(this.active)this.error=e.message;}
   finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}
  }
  async readImage(){
   this.controller=new AbortController();this.phase='reading-image';this.error='';this.render();
   const form=new FormData();form.set('file',this.source);form.set('preview',this.preview);
   const result=await this.h.api('/api/reconciliation/scan/collection',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;
   for(const p of this.parts)if(p.url)URL.revokeObjectURL(p.url);this.parts=[];this.operation=null;this.evidence=result.evidence;this.collectionWarnings=result.warnings||[];
   for(const r of result.receipts){
    const p={...this.newPart(r.index,r.bounds),reference:r.reference,row:r.row,column:r.column,read:true,amount:r.reading?.amount==null?'':new Intl.NumberFormat('es-CO',{maximumFractionDigits:2}).format(r.reading.amount),date:r.reading?.date||'',warnings:r.reading?.warnings||[]};
    this.parts.push(p);this.applyMatches(p,r,true);
    // Optional thumbnail only. Amount/date/matches already came from the full photo.
    if(p.bounds){try{await this.crop(p);}catch{p.url=null;}if(!this.active)return;}
   }
   // Two physical receipts competing for one bank movement are ambiguous.
   const automatic=result.receipts.map(r=>r.autoMatchId).filter(Boolean);
   for(const p of this.parts)if(p.paymentId&&automatic.filter(id=>id===p.paymentId).length>1){p.paymentId='';p.version=null;p.warnings.push('Otro recibo también coincide con este abono. Elige un movimiento diferente para cada uno.');}
   if(!this.parts.length)this.error='No se pudieron leer comprobantes. Puedes volver a analizar la imagen o buscar el abono manualmente.';
  }
  render(){
   if(!this.active)return;const {esc,date}=this.h,working=this.busy,locked=working||this.parts.some(p=>p.saved),top=$('.receipt-batch .modal-body')?.scrollTop||0;
   this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">${this.parts.length===1?'Comprobante encontrado':this.parts.length?`${this.parts.length} comprobantes encontrados`:'Leer comprobantes con IA'}</h2><p>Leemos la imagen completa y buscamos cada abono por valor y fecha.</p></div><button class="icon-close" data-action="batch-close" aria-label="Cerrar lectura" ${this.phase==='saving'?'disabled':''}>×</button></div><div class="modal-body">
    ${this.url?`<details class="batch-original" ${!this.parts.length?'open':''}><summary>Ver imagen original completa</summary><a href="${esc(this.url)}" target="_blank" rel="noopener"><img src="${esc(this.url)}" alt="Foto original completa, sin giros automáticos" style="display:block;max-width:100%;max-height:52vh;width:auto;margin:16px auto"></a></details>`:''}
    ${this.error?`<div class="error-banner" role="alert">${esc(this.error)}</div>`:''}
    ${this.phase==='reading-image'?'<div class="loading-state" role="status"><span class="spinner"></span>La IA está leyendo y comprobando cada recibo en la imagen completa…</div>':`
    ${this.collectionWarnings.length?`<div class="notice warning">${this.collectionWarnings.map(esc).join('<br>')}</div>`:''}
    <div class="batch-tools"><button class="btn" data-action="batch-analyze" ${locked||!this.preview?'disabled':''}>Volver a analizar la imagen</button>${!this.parts.length?`<button class="btn" data-action="batch-manual" ${working?'disabled':''}>Buscar abono manualmente</button>`:''}</div>
    ${this.parts.length?`<section class="batch-shared"><h3>${this.parts.length===1?'Datos del show':'Show y empresario para todos los recibos'}</h3><div class="form-grid"><div class="form-field full"><label for="batch-show">Show y fecha del show</label><select id="batch-show" data-common="showId" ${locked?'disabled':''}><option value="">Selecciona el show</option>${[...this.h.shows()].sort((a,b)=>b.date.localeCompare(a.date)).map(s=>`<option value="${esc(s.id)}" ${this.shared.showId===s.id?'selected':''}>${esc(date(s.date))} · ${esc(s.name)}</option>`).join('')}<option value="__new" ${this.shared.showId==='__new'?'selected':''}>+ Agregar show histórico</option></select></div><div class="form-field full"><label for="batch-entrepreneur">Empresario</label><input id="batch-entrepreneur" class="input" data-common="entrepreneur" value="${esc(this.shared.entrepreneur)}" maxlength="300" ${locked?'disabled':''}></div>${this.shared.showId==='__new'?`<div class="form-field full"><label for="batch-name">Nombre del show</label><input class="input" id="batch-name" data-common="name" value="${esc(this.shared.name)}" maxlength="200" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-date">Fecha del show</label><input id="batch-date" type="date" data-common="date" value="${esc(this.shared.date)}" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-city">Ciudad</label><input id="batch-city" class="input" data-common="city" value="${esc(this.shared.city)}" maxlength="100" ${locked?'disabled':''}></div>`:''}</div></section>
    <div class="notice">Los recortes son referencias visuales propuestas por la IA. La fecha y el valor se leen de la foto completa, que siempre se conserva en el soporte.</div>
    <div class="batch-cards">${this.parts.map(p=>`<article class="batch-card" id="batch-part-${p.index}"><div class="batch-preview"><a href="${esc(p.url||this.url)}" target="_blank" rel="noopener"><img src="${esc(p.url||this.url)}" alt="${p.url?'Recorte de referencia':'Imagen completa'} del comprobante ${p.index+1}"></a><strong>Comprobante ${p.index+1}</strong><span class="small-note">${p.url?'Recorte de referencia':'Se conserva la foto completa'}</span><a class="link-button" href="${esc(this.url)}" target="_blank" rel="noopener">Ver original</a></div><div class="batch-fields"><h3>${p.reference?`Recibo ${esc(p.reference)}`:`Fila ${p.row} · Posición ${p.column}`}</h3><p class="small-note">Fila ${p.row} · Posición ${p.column}</p>${p.saved?`<div class="notice"><strong>Guardado e identificado</strong><p><a href="${esc(p.supportUrl)}" target="_blank" rel="noopener">Consultar soporte PDF</a></p></div>`:`${p.error?`<div class="error-banner">${esc(p.error)}</div>`:''}${p.warnings.length?`<div class="notice warning">${p.warnings.map(esc).join('<br>')}</div>`:''}<div class="form-grid"><div class="form-field"><label for="batch-amount-${p.index}">Valor leído (COP)</label><input class="input" id="batch-amount-${p.index}" data-part="${p.index}" data-key="amount" inputmode="decimal" value="${esc(p.amount)}" ${working?'disabled':''}></div><div class="form-field"><label for="batch-bank-date-${p.index}">Fecha bancaria</label><input class="input" id="batch-bank-date-${p.index}" type="date" data-part="${p.index}" data-key="date" value="${esc(p.date)}" ${working?'disabled':''}></div></div><button class="btn btn-small" data-action="batch-search" data-index="${p.index}" ${working?'disabled':''}>Actualizar coincidencias</button><label for="batch-payment-${p.index}">Movimiento pendiente</label><select id="batch-payment-${p.index}" data-part="${p.index}" data-key="paymentId" ${working?'disabled':''}>${this.options(p)}</select><p id="batch-match-note-${p.index}" class="small-note">${p.paymentId?'Coincidencia seleccionada. Quedará identificado al guardar.':p.matches.length?'Elige el abono correcto entre las coincidencias.':'No se encontraron coincidencias. Puedes corregir valor o fecha.'}</p>`}</div></article>`).join('')}</div>`:''}`}
    </div><div class="modal-footer batch-footer"><span id="batch-summary" role="status">${esc(this.phase==='saving'?'Guardando soportes…':this.summary())}</span><button class="btn btn-primary" id="batch-save" data-action="batch-save" ${working||!this.selected().length?'disabled':''}>Guardar e identificar seleccionados</button></div></section></div>`);
   const body=$('.receipt-batch .modal-body');if(body)body.scrollTop=top;
  }
  async action(action,index){
   if(!this.active)return;
   if(action==='batch-analyze'){
    if(this.busy||!this.preview||this.parts.some(p=>p.saved))return;if(this.parts.length&&!confirm('Se reemplazarán las lecturas y selecciones sin guardar. ¿Continuar?'))return;
    this.setBusy(true);try{await this.readImage();}catch(e){if(this.active)this.error=e.message;}finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}return;
   }
   return super.action(action,index);
  }
 };
})();
