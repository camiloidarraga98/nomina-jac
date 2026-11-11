/* Full-image OCR stays independent of optional visual reference crops.
 * Approximate locators are labelled; only API-verified or user-marked borders
 * become saved crops. No local receipt detection or automatic image rotation. */
(() => {
 'use strict';
 const $=s=>document.querySelector(s);
 const jpeg=canvas=>new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(Error('No se pudo preparar la foto.')),'image/jpeg',.95));
 window.JacReceiptCollection=class extends window.JacReceiptBatch {
  constructor(host){super(host);this.collectionMode=true;this.orientationVerified=true;this.collectionWarnings=[];this.evidence='';}
  dispose(){super.dispose();this.evidence='';this.collectionWarnings=[];}
  static positionBounds(part,parts){
   const rows=Math.max(1,...parts.map(p=>p.row)),columns=Math.max(1,...parts.filter(p=>p.row===part.row).map(p=>p.column));
   const x=(part.column-1)*1000/columns,y=(part.row-1)*1000/rows;
   return this.expandBounds({x,y,width:1000/columns,height:1000/rows},.16,.08);
  }
  static expandBounds(b,dx=.18,dy=.1){
   const x=Math.max(0,Math.floor(b.x-b.width*dx)),y=Math.max(0,Math.floor(b.y-b.height*dy));
   return {x,y,width:Math.min(1000,Math.ceil(b.x+b.width*(1+dx)))-x,height:Math.min(1000,Math.ceil(b.y+b.height*(1+dy)))-y};
  }
  referenceFor(p){
   if(p.manualBounds)return {bounds:p.manualBounds,kind:'manual',label:'Recorte ajustado'};
   if(p.bounds)return {bounds:p.bounds,kind:'confirmed',label:'Recorte de referencia'};
   const b=p.suggestedBounds;
   const repeated=b&&this.parts.some(q=>{const a=q.suggestedBounds||q.bounds;if(q===p||!a)return false;const area=Math.max(0,Math.min(a.x+a.width,b.x+b.width)-Math.max(a.x,b.x))*Math.max(0,Math.min(a.y+a.height,b.y+b.height)-Math.max(a.y,b.y));return area/Math.min(a.width*a.height,b.width*b.height)>.8;});
   return b&&!repeated?{bounds:this.constructor.expandBounds(b),kind:'suggested',label:'Ubicación sugerida · revisa los bordes'}:{bounds:this.constructor.positionBounds(p,this.parts),kind:'approximate',label:'Vista por posición · confirma la ubicación'};
  }
  async buildReference(p){
   const ref=this.referenceFor(p),view={index:p.index,bounds:ref.bounds};
   p.visualBounds=ref.bounds;p.visualKind=ref.kind;p.visualLabel=ref.label;
   try{await this.crop(view);if(!this.active)return;if(p.url)URL.revokeObjectURL(p.url);p.url=view.url;p.file=view.file;}catch{if(p.url)URL.revokeObjectURL(p.url);p.url=null;}
  }
  boxStyle(b){return `left:${b.x/10}%;top:${b.y/10}%;width:${b.width/10}%;height:${b.height/10}%`;}
  referenceMarkup(p){
   const esc=this.h.esc,b=p.visualBounds||this.referenceFor(p).bounds,approx=['suggested','approximate'].includes(p.visualKind);
   return `<div class="batch-preview receipt-reference"><div class="receipt-reference-title"><span class="receipt-number">${p.index+1}</span><strong>Comprobante ${p.index+1}</strong></div><button class="receipt-reference-open" data-action="batch-reference-open" data-index="${p.index}" aria-label="Ampliar comprobante ${p.index+1}">${p.url?`<img src="${esc(p.url)}" alt="${esc(p.visualLabel)} del comprobante ${p.index+1}">`:'<span>Ubicar en la foto</span>'}<span>Ampliar${p.saved?'':' y ajustar'}</span></button><p class="receipt-reference-caption ${approx?'approximate':''}">${esc(p.visualLabel)}</p><button class="receipt-reference-context" data-action="batch-reference-open" data-index="${p.index}" aria-label="Ubicar comprobante ${p.index+1} en la imagen completa"><img src="${esc(this.url)}" alt="Ubicación del comprobante ${p.index+1} en la foto completa"><span class="receipt-reference-box ${approx?'approximate':''}" style="${this.boxStyle(b)}"><b>${p.index+1}</b></span></button><a class="link-button" href="${esc(this.url)}" target="_blank" rel="noopener">Ver original completo</a></div>`;
  }
  renderReferenceEditor(){
   const p=this.parts.find(p=>p.index===this.referenceIndex);if(!p)return;const esc=this.h.esc;
   this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch receipt-reference-editor" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">${p.saved?'Ver':'Ubicar'} comprobante ${p.index+1}</h2><p>${esc(p.reference?'Recibo '+p.reference:`Fila ${p.row} · Posición ${p.column}`)} · ${esc(p.amount||'Valor por revisar')} · ${esc(p.date?this.h.date(p.date):'Fecha por revisar')}</p></div><button class="icon-close" data-action="batch-reference-cancel" aria-label="Volver a los comprobantes" ${this.busy?'disabled':''}>×</button></div><div class="modal-body"><p>${p.saved?'Consulta la referencia visual del comprobante.': 'Marca en la foto el recibo completo, incluida la fecha y el valor. Puedes ampliar la imagen para ajustar los bordes.'}</p><div class="batch-tools"><button class="btn" data-action="batch-reference-minus" aria-label="Reducir imagen">−</button><output id="receipt-reference-zoom" aria-live="polite">${Math.round(this.referenceZoom*100)} %</output><button class="btn" data-action="batch-reference-plus" aria-label="Ampliar imagen">+</button><button class="btn" data-action="batch-reference-pan" aria-pressed="${this.referencePan}">${this.referencePan?'Volver a marcar':'Desplazar imagen'}</button></div><div class="receipt-reference-viewport" id="receipt-reference-viewport"><div class="batch-crop-stage" id="receipt-reference-stage" tabindex="0" aria-label="Foto para marcar el comprobante. Flechas mueven el recorte; Mayúsculas y flechas ajustan su tamaño."><img src="${esc(this.url)}" alt="Imagen original completa" draggable="false"><div class="batch-crop-box" style="${this.boxStyle(this.referenceDraft)}"><span>${p.index+1}</span></div></div></div><p class="small-note">${p.saved?'La imagen original se conserva en el soporte.':'Este ajuste conserva la lectura y el abono seleccionado. Usa Desplazar imagen para recorrer la foto ampliada.'}</p></div><div class="modal-footer"><button class="btn" data-action="batch-reference-cancel" ${this.busy?'disabled':''}>Volver</button>${p.saved?'':`<button class="btn btn-primary" data-action="batch-reference-use" ${this.busy?'disabled':''}>Usar este recorte</button>`}</div></section></div>`);
   this.sizeReference();this.bindReference(p.saved);
  }
  sizeReference(){
   const viewport=$('#receipt-reference-viewport'),stage=$('#receipt-reference-stage');if(!viewport||!stage)return;
   const previous=stage.getBoundingClientRect().width,base=Math.min(viewport.clientWidth,innerHeight*.52*this.image.width/this.image.height),width=base*this.referenceZoom;
   const x=previous?(viewport.scrollLeft+viewport.clientWidth/2)/previous:0,y=previous?(viewport.scrollTop+viewport.clientHeight/2)/previous:0;
   stage.style.width=width+'px';if(previous){viewport.scrollLeft=x*width-viewport.clientWidth/2;viewport.scrollTop=y*width-viewport.clientHeight/2;}
   $('#receipt-reference-zoom').textContent=Math.round(this.referenceZoom*100)+' %';
  }
  bindReference(saved=false){
   const stage=$('#receipt-reference-stage'),viewport=$('#receipt-reference-viewport');if(!stage)return;
   stage.onkeydown=null;
   const update=b=>{this.referenceDraft=b;const box=stage.querySelector('.batch-crop-box');box.style.cssText=this.boxStyle(b);};
   if(this.referencePan||saved){
    stage.style.touchAction='pan-x pan-y';stage.style.cursor='grab';let pan=null;
    stage.onpointerdown=e=>{if(e.pointerType!=='mouse'||e.button!==0)return;e.preventDefault();pan={x:e.clientX,y:e.clientY,left:viewport.scrollLeft,top:viewport.scrollTop};stage.setPointerCapture(e.pointerId);};
    stage.onpointermove=e=>{if(pan){viewport.scrollLeft=pan.left+pan.x-e.clientX;viewport.scrollTop=pan.top+pan.y-e.clientY;}};stage.onpointerup=stage.onpointercancel=()=>{pan=null;};
   }else{
    stage.style.touchAction='none';stage.style.cursor='crosshair';this.bindRectangle(stage,update);
    stage.onkeydown=e=>{if(!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key))return;e.preventDefault();e.stopPropagation();const b={...this.referenceDraft},horizontal=['ArrowLeft','ArrowRight'].includes(e.key),step=['ArrowLeft','ArrowUp'].includes(e.key)?-10:10;
     if(e.shiftKey){const size=horizontal?'width':'height',start=horizontal?'x':'y';b[size]=Math.max(10,Math.min(1000-b[start],b[size]+step));}else{const start=horizontal?'x':'y',size=horizontal?'width':'height';b[start]=Math.max(0,Math.min(1000-b[size],b[start]+step));}update(b);
    };
   }
  }
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
   if(this.h.singleReady&&(result.existingPaymentId||(result.complete&&result.receipts?.length===1))){
    const r=result.receipts?.[0];return this.h.singleReady(this.source,result.existingPaymentId?result:{reading:r.reading,matches:r.matches,total:r.total,autoMatchId:r.autoMatchId},this.preview);
   }
   for(const p of this.parts)if(p.url)URL.revokeObjectURL(p.url);this.parts=[];this.operation=null;this.evidence=result.evidence;this.collectionWarnings=result.warnings||[];
   for(const r of result.receipts){
    const p={...this.newPart(r.index,r.bounds),suggestedBounds:r.suggestedBounds||null,reference:r.reference,row:r.row,column:r.column,read:true,amount:r.reading?.amount==null?'':new Intl.NumberFormat('es-CO',{maximumFractionDigits:2}).format(r.reading.amount),date:r.reading?.date||'',warnings:r.reading?.warnings||[]};
    this.parts.push(p);this.applyMatches(p,r,true);
    // Optional thumbnail only. Amount/date/matches already came from the full photo.
   }
   for(const p of this.parts){await this.buildReference(p);if(!this.active)return;}
   // Two physical receipts competing for one bank movement are ambiguous.
   const automatic=result.receipts.map(r=>r.autoMatchId).filter(Boolean);
   for(const p of this.parts)if(p.paymentId&&automatic.filter(id=>id===p.paymentId).length>1){p.paymentId='';p.version=null;p.warnings.push('Otro recibo también coincide con este abono. Elige un movimiento diferente para cada uno.');}
   if(!this.parts.length)this.error='No se pudieron leer comprobantes. Puedes volver a analizar la imagen o buscar el abono manualmente.';
  }
  render(){
   if(!this.active)return;if(this.referenceIndex!==undefined){this.renderReferenceEditor();return;}
   const {esc,date}=this.h,working=this.busy,locked=working||this.parts.some(p=>p.saved),top=this.referenceReturnScroll??$('.receipt-batch .modal-body')?.scrollTop??0;this.referenceReturnScroll=undefined;
   this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">${this.parts.length===1?'Comprobante encontrado':this.parts.length?`${this.parts.length} comprobantes encontrados`:'Leer comprobantes con IA'}</h2><p>Leemos la imagen completa y buscamos cada abono por valor y fecha.</p></div><button class="icon-close" data-action="batch-close" aria-label="Cerrar lectura" ${this.phase==='saving'?'disabled':''}>×</button></div><div class="modal-body">
    ${this.url?`<details class="batch-original" ${!this.parts.length?'open':''}><summary>Ver imagen completa y ubicar comprobantes</summary><div class="batch-map" style="--image-ratio:${this.image.width/this.image.height}"><img src="${esc(this.url)}" alt="Foto original completa, sin giros automáticos">${this.parts.map(p=>`<button class="batch-map-box ${['suggested','approximate'].includes(p.visualKind)?'approximate':''}" data-action="batch-reference-open" data-index="${p.index}" aria-label="Ubicar comprobante ${p.index+1}" style="${this.boxStyle(p.visualBounds||this.referenceFor(p).bounds)}" ${working?'disabled':''}><span>${p.index+1}</span></button>`).join('')}</div></details>`:''}
    ${this.error?`<div class="error-banner" role="alert">${esc(this.error)}</div>`:''}
    ${this.phase==='reading-image'?'<div class="loading-state" role="status"><span class="spinner"></span>La IA está leyendo y comprobando cada recibo en la imagen completa…</div>':`
    ${this.collectionWarnings.length?`<div class="notice warning">${this.collectionWarnings.map(esc).join('<br>')}</div>`:''}
    <div class="batch-tools"><button class="btn" data-action="batch-analyze" ${locked||!this.preview?'disabled':''}>Volver a analizar la imagen</button>${!this.parts.length?`<button class="btn" data-action="batch-manual" ${working?'disabled':''}>Buscar abono manualmente</button>`:''}</div>
    ${this.parts.length?`<section class="batch-shared"><h3>${this.parts.length===1?'Datos del show':'Show y empresario para todos los recibos'}</h3><div class="form-grid"><div class="form-field full"><label for="batch-show">Show y fecha del show</label><select id="batch-show" data-common="showId" ${locked?'disabled':''}><option value="">Selecciona el show</option>${[...this.h.shows()].sort((a,b)=>b.date.localeCompare(a.date)).map(s=>`<option value="${esc(s.id)}" ${this.shared.showId===s.id?'selected':''}>${esc(date(s.date))} · ${esc(s.name)}</option>`).join('')}<option value="__new" ${this.shared.showId==='__new'?'selected':''}>+ Agregar show histórico</option></select></div><div class="form-field full"><label for="batch-entrepreneur">Empresario</label><input id="batch-entrepreneur" class="input" data-common="entrepreneur" value="${esc(this.shared.entrepreneur)}" maxlength="300" ${locked?'disabled':''}></div>${this.shared.showId==='__new'?`<div class="form-field full"><label for="batch-name">Nombre del show</label><input class="input" id="batch-name" data-common="name" value="${esc(this.shared.name)}" maxlength="200" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-date">Fecha del show</label><input id="batch-date" type="date" data-common="date" value="${esc(this.shared.date)}" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-city">Ciudad</label><input id="batch-city" class="input" data-common="city" value="${esc(this.shared.city)}" maxlength="100" ${locked?'disabled':''}></div>`:''}</div></section>
    <div class="notice">Cada ficha tiene su número y una vista del área correspondiente. Las vistas aproximadas se pueden ampliar y ajustar; sólo se guardan como recortes los límites confirmados. La foto original siempre se conserva.</div>
    <div class="batch-cards">${this.parts.map(p=>`<article class="batch-card" id="batch-part-${p.index}">${this.referenceMarkup(p)}<div class="batch-fields"><h3>${p.reference?`Recibo ${esc(p.reference)}`:`Comprobante ${p.index+1}`}</h3><p class="small-note">Fila ${p.row} · Posición ${p.column}</p>${p.saved?`<div class="notice"><strong>Guardado e identificado</strong><p><a href="${esc(p.supportUrl)}" target="_blank" rel="noopener">Consultar soporte PDF</a></p></div>`:`${p.error?`<div class="error-banner">${esc(p.error)}</div>`:''}${p.warnings.length?`<div class="notice warning">${p.warnings.map(esc).join('<br>')}</div>`:''}<div class="form-grid"><div class="form-field"><label for="batch-amount-${p.index}">Valor leído (COP)</label><input class="input" id="batch-amount-${p.index}" data-part="${p.index}" data-key="amount" inputmode="decimal" value="${esc(p.amount)}" ${working?'disabled':''}></div><div class="form-field"><label for="batch-bank-date-${p.index}">Fecha bancaria</label><input class="input" id="batch-bank-date-${p.index}" type="date" data-part="${p.index}" data-key="date" value="${esc(p.date)}" ${working?'disabled':''}></div></div><button class="btn btn-small" data-action="batch-search" data-index="${p.index}" ${working?'disabled':''}>Actualizar coincidencias</button><label for="batch-payment-${p.index}">Movimiento pendiente</label><select id="batch-payment-${p.index}" data-part="${p.index}" data-key="paymentId" ${working?'disabled':''}>${this.options(p)}</select><p id="batch-match-note-${p.index}" class="small-note">${p.paymentId?'Coincidencia seleccionada. Quedará identificado al guardar.':p.matches.length?'Elige el abono correcto entre las coincidencias.':'No se encontraron coincidencias. Puedes corregir valor o fecha.'}</p>`}</div></article>`).join('')}</div>`:''}`}
    </div><div class="modal-footer batch-footer"><span id="batch-summary" role="status">${esc(this.phase==='saving'?'Guardando soportes…':this.summary())}</span><button class="btn btn-primary" id="batch-save" data-action="batch-save" ${working||!this.selected().length?'disabled':''}>Guardar e identificar seleccionados</button></div></section></div>`);
   const body=$('.receipt-batch .modal-body');if(body)body.scrollTop=top;
  }
  async action(action,index){
   if(!this.active)return;
   if(action.startsWith('batch-reference-')){
    if(this.busy)return;
    if(action==='batch-reference-open'){
     const p=this.parts.find(p=>p.index===Number(index));if(!p)return;this.referenceReturnScroll=$('.receipt-batch .modal-body')?.scrollTop||0;
     this.referenceIndex=p.index;this.referenceDraft={...(p.visualBounds||this.referenceFor(p).bounds)};this.referenceZoom=1;this.referencePan=!!p.saved;this.render();return;
    }
    const p=this.parts.find(p=>p.index===this.referenceIndex);if(!p)return;
    if(action==='batch-reference-cancel'){this.referenceIndex=undefined;this.render();return;}
    if(action==='batch-reference-plus'||action==='batch-reference-minus'){this.referenceZoom=Math.max(1,Math.min(4,this.referenceZoom+(action==='batch-reference-plus' ? .5 : -.5)));this.sizeReference();return;}
    if(action==='batch-reference-pan'){this.referencePan=!this.referencePan;const button=$('[data-action="batch-reference-pan"]');button.textContent=this.referencePan?'Volver a marcar':'Desplazar imagen';button.setAttribute('aria-pressed',String(this.referencePan));this.bindReference(p.saved);return;}
    if(action==='batch-reference-use'&&!p.saved){
     p.manualBounds={...this.referenceDraft};this.operation=null;this.setBusy(true);this.render();
     try{await this.buildReference(p);if(this.active)this.h.dirty(true);}finally{if(this.active){this.setBusy(false);this.referenceIndex=undefined;this.render();}}return;
    }
    return;
   }
   if(action==='batch-analyze'){
    if(this.busy||!this.preview||this.parts.some(p=>p.saved))return;if(this.parts.length&&!confirm('Se reemplazarán las lecturas y selecciones sin guardar. ¿Continuar?'))return;
    this.setBusy(true);try{await this.readImage();}catch(e){if(this.active)this.error=e.message;}finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}return;
   }
   return super.action(action,index);
  }
 };
})();
