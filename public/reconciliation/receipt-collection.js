/* Full-image OCR stays independent of optional visual reference crops.
 * No approximate grid fallback; only API-verified or user-marked borders
 * become saved crops. No local receipt detection or automatic image rotation. */
(() => {
 'use strict';
 const $=s=>document.querySelector(s);
 const jpeg=canvas=>new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(Error('No se pudo preparar la foto.')),'image/jpeg',.95));
 window.JacReceiptCollection=class extends window.JacReceiptBatch {
  constructor(host){super(host);this.collectionMode=true;this.orientationVerified=true;this.collectionWarnings=[];this.evidence='';}
  dispose(){if(this.viewUrl)URL.revokeObjectURL(this.viewUrl);this.viewUrl=null;super.dispose();this.evidence='';this.collectionWarnings=[];}
  displayBounds(b){return this.constructor.originalBounds(b,(360-this.rotation)%360);}
  displaySize(){return this.rotation===90||this.rotation===270?{width:this.image.height,height:this.image.width}:this.image;}
  rotationControls(){return `<button class="btn" data-action="batch-view-left" ${this.busy||!this.image?'disabled':''}>↶ Girar izquierda</button><button class="btn" data-action="batch-view-right" ${this.busy||!this.image?'disabled':''}>↷ Girar derecha</button>`;}
  async rotateView(delta){
   if(this.busy||!this.image)return;const rotation=(this.rotation+delta+360)%360;this.setBusy(true);this.render();
   try{
    const blob=rotation?await jpeg(this.constructor.rotatedCanvas(this.image,rotation)):null;if(!this.active)return;
    if(this.viewUrl)URL.revokeObjectURL(this.viewUrl);this.viewUrl=blob?URL.createObjectURL(blob):null;this.rotation=rotation;
    // Only display pixels turn. Signed reading, original preview and all bounds
    // stay in the original coordinate frame, including pending manual edits.
    for(const p of this.parts){await this.buildReference(p);if(!this.active)return;}
    this.showFullImage=true;
   }catch(e){if(this.active)this.error=e.message;}
   finally{if(this.active){this.setBusy(false);this.render();}}
  }
  referenceFor(p){
   if(p.manualBounds)return {bounds:p.manualBounds,kind:'manual',label:'Recorte ajustado'};
   if(p.bounds)return {bounds:p.bounds,kind:'confirmed',label:'Recorte verificado con IA'};
   return {bounds:null,kind:'unlocated',label:'Recorte pendiente de verificar'};
  }
  async boundedJPEG(source,maxBytes,maxSide){
   const canvas=document.createElement('canvas'),scale=Math.min(1,maxSide/Math.max(source.width,source.height));canvas.width=Math.round(source.width*scale);canvas.height=Math.round(source.height*scale);
   for(let attempt=0;attempt<5;attempt++){
    const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(source,0,0,canvas.width,canvas.height);
    const blob=await jpeg(canvas);if(blob.size<=maxBytes)return blob;canvas.width=Math.max(20,Math.floor(canvas.width*.8));canvas.height=Math.max(20,Math.floor(canvas.height*.8));
   }throw Error('No se pudo preparar la vista ampliada dentro del tamaño permitido.');
  }
  async detailImages(){
   const files=[];
   for(const [x,y]of [[0,0],[.35,0],[0,.35],[.35,.35]]){
    const canvas=document.createElement('canvas');canvas.width=Math.round(this.image.width*.65);canvas.height=Math.round(this.image.height*.65);canvas.getContext('2d').drawImage(this.image,this.image.width*x,this.image.height*y,canvas.width,canvas.height,0,0,canvas.width,canvas.height);
    files.push(new File([await this.boundedJPEG(canvas,512*1024,1800)],`detalle-${files.length}.jpg`,{type:'image/jpeg'}));if(!this.active)return [];
   }return files;
  }
  async verifyReferences(result,attempt=1){
   const proposals=result.receipts.filter(r=>r.cropProposal);if(!proposals.length)return;
   this.phase='checking-references';this.render();const form=new FormData();form.set('file',this.preview);
   const parts=[];
   for(const r of proposals){
    const b=r.cropProposal,canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(this.image.width*b.width/1000));canvas.height=Math.max(1,Math.round(this.image.height*b.height/1000));canvas.getContext('2d').drawImage(this.image,this.image.width*b.x/1000,this.image.height*b.y/1000,canvas.width,canvas.height,0,0,canvas.width,canvas.height);
    form.set('crop-'+r.index,new File([await this.boundedJPEG(canvas,300*1024,1400)],`recorte-${r.index}.jpg`,{type:'image/jpeg'}));parts.push({index:r.index,bounds:b});if(!this.active)return;
   }
   form.set('plan',JSON.stringify({evidence:result.evidence,sourceHash:result.sourceHash,attempt,parts}));
   const verified=await this.h.api('/api/reconciliation/scan/collection/crops',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;this.evidence=verified.evidence;
   for(const r of verified.receipts){const p=this.parts.find(p=>p.index===r.index);if(!p)continue;p.bounds=r.approved?r.bounds:null;if(r.approved){p.reference=r.reference;if(r.autoMatchId){this.applyMatches(p,r,true);p.autoProposal=r.autoMatchId;p.warnings=p.warnings.filter(w=>!w.startsWith('Este recibo apareció en una sola lectura.'));}}}
   const retry=verified.receipts.filter(r=>!r.approved&&r.cropProposal);if(attempt===1&&retry.length)await this.verifyReferences({receipts:retry,evidence:verified.evidence,sourceHash:result.sourceHash},2);
  }
  async buildReference(p){
   const ref=this.referenceFor(p),view={index:p.index,bounds:ref.bounds};
   p.visualBounds=ref.bounds;p.visualKind=ref.kind;p.visualLabel=ref.label;
   if(!ref.bounds){if(p.url)URL.revokeObjectURL(p.url);p.url=null;return;}
   try{await this.crop(view);if(!this.active)return;if(p.url)URL.revokeObjectURL(p.url);p.url=view.url;p.file=view.file;}catch{if(p.url)URL.revokeObjectURL(p.url);p.url=null;}
  }
  boxStyle(bounds){const b=this.displayBounds(bounds);return `left:${b.x/10}%;top:${b.y/10}%;width:${b.width/10}%;height:${b.height/10}%`;}
  referenceMarkup(p){
   const esc=this.h.esc,b=p.visualBounds;
   return `<div class="batch-preview receipt-reference"><div class="receipt-reference-title"><span class="receipt-number">${p.index+1}</span><strong>Comprobante ${p.index+1}</strong></div><button class="receipt-reference-open" data-action="batch-reference-open" data-index="${p.index}" aria-label="Ampliar comprobante ${p.index+1}">${p.url?`<img src="${esc(p.url)}" alt="${esc(p.visualLabel)} del comprobante ${p.index+1}">`:`<span class="receipt-reference-unlocated"><strong>${p.reference||p.candidateReference?'Recibo '+esc(p.reference||p.candidateReference):'Referencia por confirmar'}</strong><b>${esc(p.amount||'Valor por revisar')}</b><span>${esc(p.date?this.h.date(p.date):'Fecha por revisar')}</span></span>`}<span>${b?'Ampliar'+(p.saved?'':' y ajustar'):'Ubicar en la foto completa'}</span></button><p class="receipt-reference-caption">${esc(p.visualLabel)}</p>${b?`<button class="receipt-reference-context" data-action="batch-reference-open" data-index="${p.index}" aria-label="Ubicar comprobante ${p.index+1} en la imagen completa"><img src="${esc(this.viewUrl||this.url)}" alt="Ubicación del comprobante ${p.index+1} en la foto completa"><span class="receipt-reference-box" style="${this.boxStyle(b)}"><b>${p.index+1}</b></span></button>`:''}<a class="link-button" href="${esc(this.url)}" target="_blank" rel="noopener">Ver original completo</a></div>`;
  }
  renderReferenceEditor(){
   const p=this.parts.find(p=>p.index===this.referenceIndex);if(!p)return;const esc=this.h.esc;
   this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch receipt-reference-editor" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">${p.saved?'Ver':'Ubicar'} comprobante ${p.index+1}</h2><p>${esc(p.reference?'Recibo '+p.reference:`Fila ${p.row} · Posición ${p.column}`)} · ${esc(p.amount||'Valor por revisar')} · ${esc(p.date?this.h.date(p.date):'Fecha por revisar')}</p></div><button class="icon-close" data-action="batch-reference-cancel" aria-label="Volver a los comprobantes" ${this.busy?'disabled':''}>×</button></div><div class="modal-body"><p>${p.saved?'Consulta la referencia visual del comprobante.': 'Marca en la foto el recibo completo, incluida la fecha y el valor. Puedes ampliar la imagen para ajustar los bordes.'}</p><div class="batch-tools">${this.rotationControls()}<button class="btn" data-action="batch-reference-minus" aria-label="Reducir imagen">−</button><output id="receipt-reference-zoom" aria-live="polite">${Math.round(this.referenceZoom*100)} %</output><button class="btn" data-action="batch-reference-plus" aria-label="Ampliar imagen">+</button><button class="btn" data-action="batch-reference-pan" aria-pressed="${this.referencePan}">${this.referencePan?'Volver a marcar':'Desplazar imagen'}</button></div><div class="receipt-reference-viewport" id="receipt-reference-viewport"><div class="batch-crop-stage" id="receipt-reference-stage" tabindex="0" aria-label="Foto para marcar el comprobante. Flechas mueven el recorte; Mayúsculas y flechas ajustan su tamaño."><img src="${esc(this.viewUrl||this.url)}" alt="Imagen original completa" draggable="false"><div class="batch-crop-box" style="${this.boxStyle(this.referenceDraft)}"><span>${p.index+1}</span></div></div></div><p class="small-note">${p.saved?'La imagen original se conserva en el soporte.':'El giro sólo cambia la vista. Este ajuste conserva la lectura y el abono seleccionado. Usa Desplazar imagen para recorrer la foto ampliada.'}</p></div><div class="modal-footer"><button class="btn" data-action="batch-reference-cancel" ${this.busy?'disabled':''}>Volver</button>${p.saved?'':`<button class="btn btn-primary" data-action="batch-reference-use" ${this.busy?'disabled':''}>Usar este recorte</button>`}</div></section></div>`);
   this.sizeReference();this.bindReference(p.saved);
  }
  sizeReference(){
   const viewport=$('#receipt-reference-viewport'),stage=$('#receipt-reference-stage');if(!viewport||!stage)return;
   const size=this.displaySize(),previous=stage.getBoundingClientRect().width,base=Math.min(viewport.clientWidth,innerHeight*.52*size.width/size.height),width=base*this.referenceZoom;
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
    stage.style.touchAction='none';stage.style.cursor='crosshair';this.bindRectangle(stage,b=>update(this.constructor.originalBounds(b,this.rotation)));
    stage.onkeydown=e=>{if(!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key))return;e.preventDefault();e.stopPropagation();const b=this.displayBounds(this.referenceDraft),horizontal=['ArrowLeft','ArrowRight'].includes(e.key),step=['ArrowLeft','ArrowUp'].includes(e.key)?-10:10;
     if(e.shiftKey){const size=horizontal?'width':'height',start=horizontal?'x':'y';b[size]=Math.max(10,Math.min(1000-b[start],b[size]+step));}else{const start=horizontal?'x':'y',size=horizontal?'width':'height';b[start]=Math.max(0,Math.min(1000-b[size],b[start]+step));}update(this.constructor.originalBounds(b,this.rotation));
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
   const form=new FormData();form.set('file',this.source);form.set('preview',this.preview);form.set('locateMissing','true');
   const details=await this.detailImages();if(!this.active)return;details.forEach((file,i)=>form.set('detail-'+i,file));
   const result=await this.h.api('/api/reconciliation/scan/collection',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;
   if(this.h.singleReady&&(result.existingPaymentId||result.receipts?.length===1)){
    const r=result.receipts?.[0],reading=r?.reading?{...r.reading,warnings:[...new Set([...(r.reading.warnings||[]),...(result.warnings||[])])]}:null;
    return this.h.singleReady(this.source,result.existingPaymentId?result:{reading,matches:r.matches,total:r.total,autoMatchId:result.complete?r.autoMatchId:null},this.preview);
   }
   for(const p of this.parts)if(p.url)URL.revokeObjectURL(p.url);this.parts=[];this.operation=null;this.evidence=result.evidence;this.collectionWarnings=result.warnings||[];
   for(const r of result.receipts){
    const p={...this.newPart(r.index,r.bounds),suggestedBounds:null,candidateReference:r.candidateReference||null,autoProposal:r.autoMatchId,reference:r.reference,row:r.row,column:r.column,read:true,amount:r.reading?.amount==null?'':new Intl.NumberFormat('es-CO',{maximumFractionDigits:2}).format(r.reading.amount),date:r.reading?.date||'',warnings:r.reading?.warnings||[]};
    this.parts.push(p);this.applyMatches(p,r,true);
    // Optional thumbnail only. Amount/date/matches already came from the full photo.
   }
   try{await this.verifyReferences(result);}catch(e){if(!this.active)return;this.collectionWarnings.push('No se confirmaron todos los recortes. Conservamos las lecturas y la foto completa. '+e.message);}
   for(const p of this.parts){await this.buildReference(p);if(!this.active)return;}
   // Two physical receipts competing for one bank movement are ambiguous.
   const automatic=this.parts.map(p=>p.autoProposal).filter(Boolean);
   for(const p of this.parts)if(p.paymentId&&automatic.filter(id=>id===p.paymentId).length>1){p.paymentId='';p.version=null;p.warnings.push('Otro recibo también coincide con este abono. Elige un movimiento diferente para cada uno.');}
   if(!this.parts.length)this.error='No se pudieron leer comprobantes. Puedes volver a analizar la imagen o buscar el abono manualmente.';
  }
  render(){
   if(!this.active)return;if(this.referenceIndex!==undefined){this.renderReferenceEditor();return;}
   const {esc,date}=this.h,working=this.busy,locked=working||this.parts.some(p=>p.saved),top=this.referenceReturnScroll??$('.receipt-batch .modal-body')?.scrollTop??0;this.referenceReturnScroll=undefined;
   this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">${this.parts.length===1?'Comprobante encontrado':this.parts.length?`${this.parts.length} comprobantes encontrados`:'Leer comprobantes con IA'}</h2><p>Leemos la imagen completa y buscamos cada abono por valor y fecha.</p></div><button class="icon-close" data-action="batch-close" aria-label="Cerrar lectura" ${this.phase==='saving'?'disabled':''}>×</button></div><div class="modal-body">
    ${this.url?`<details class="batch-original" ${!this.parts.length||this.showFullImage?'open':''}><summary>Ver imagen completa y ubicar comprobantes</summary><div class="batch-map" style="--image-ratio:${this.displaySize().width/this.displaySize().height}"><img src="${esc(this.viewUrl||this.url)}" alt="Foto completa con el giro elegido">${this.parts.filter(p=>p.visualBounds).map(p=>`<button class="batch-map-box ${['suggested','approximate'].includes(p.visualKind)?'approximate':''}" data-action="batch-reference-open" data-index="${p.index}" aria-label="Ubicar comprobante ${p.index+1}" style="${this.boxStyle(p.visualBounds||this.referenceFor(p).bounds)}" ${working?'disabled':''}><span>${p.index+1}</span></button>`).join('')}</div></details>`:''}
    ${this.error?`<div class="error-banner" role="alert">${esc(this.error)}</div>`:''}
    ${['reading-image','checking-references'].includes(this.phase)?`<div class="loading-state" role="status"><span class="spinner"></span>${this.phase==='checking-references'?'La IA está verificando que cada recorte conserve la fecha, el valor completo y su número de recibo…':'La IA está leyendo y comprobando cada recibo en la imagen completa…'}</div>`:`
    ${this.collectionWarnings.length?`<div class="notice warning">${this.collectionWarnings.map(esc).join('<br>')}</div>`:''}
    <div class="batch-tools">${this.rotationControls()}<button class="btn" data-action="batch-analyze" ${locked||!this.preview?'disabled':''}>Volver a analizar la imagen</button>${this.h.singleWhole?`<button class="btn" data-action="batch-single-whole" ${locked||!this.preview?'disabled':''}>Es un solo comprobante</button>`:''}${!this.parts.length?`<button class="btn" data-action="batch-manual" ${working?'disabled':''}>Buscar abono manualmente</button>`:''}</div>
    ${this.parts.length?`<section class="batch-shared"><h3>${this.parts.length===1?'Datos del show':'Show y empresario para todos los recibos'}</h3><div class="form-grid"><div class="form-field full"><label for="batch-show">Show y fecha del show</label><select id="batch-show" data-common="showId" ${locked?'disabled':''}><option value="">Selecciona el show</option>${[...this.h.shows()].sort((a,b)=>b.date.localeCompare(a.date)).map(s=>`<option value="${esc(s.id)}" ${this.shared.showId===s.id?'selected':''}>${esc(date(s.date))} · ${esc(s.name)}</option>`).join('')}<option value="__new" ${this.shared.showId==='__new'?'selected':''}>+ Agregar show histórico</option></select></div><div class="form-field full"><label for="batch-entrepreneur">Empresario</label><input id="batch-entrepreneur" class="input" data-common="entrepreneur" value="${esc(this.shared.entrepreneur)}" maxlength="300" ${locked?'disabled':''}></div>${this.shared.showId==='__new'?`<div class="form-field full"><label for="batch-name">Nombre del show</label><input class="input" id="batch-name" data-common="name" value="${esc(this.shared.name)}" maxlength="200" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-date">Fecha del show</label><input id="batch-date" type="date" data-common="date" value="${esc(this.shared.date)}" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-city">Ciudad</label><input id="batch-city" class="input" data-common="city" value="${esc(this.shared.city)}" maxlength="100" ${locked?'disabled':''}></div>`:''}</div></section>
    <div class="notice">Cada recibo conserva su lectura y sus coincidencias. Los recortes se verifican leyendo sus píxeles con IA; si una vista no se confirma, se muestra su referencia y se conserva la foto completa. </div>
    <div class="batch-cards">${this.parts.map(p=>`<article class="batch-card" id="batch-part-${p.index}">${this.referenceMarkup(p)}<div class="batch-fields"><h3>${p.reference||p.candidateReference?`Recibo ${esc(p.reference||p.candidateReference)}`:`Comprobante ${p.index+1}`}</h3><p class="small-note">Fila ${p.row} · Posición ${p.column}</p>${p.saved?`<div class="notice"><strong>Guardado e identificado</strong><p><a href="${esc(p.supportUrl)}" target="_blank" rel="noopener">Consultar soporte PDF</a></p></div>`:`${p.error?`<div class="error-banner">${esc(p.error)}</div>`:''}${p.warnings.length?`<div class="notice warning">${p.warnings.map(esc).join('<br>')}</div>`:''}<div class="form-grid"><div class="form-field"><label for="batch-amount-${p.index}">Valor leído (COP)</label><input class="input" id="batch-amount-${p.index}" data-part="${p.index}" data-key="amount" inputmode="decimal" value="${esc(p.amount)}" ${working?'disabled':''}></div><div class="form-field"><label for="batch-bank-date-${p.index}">Fecha bancaria</label><input class="input" id="batch-bank-date-${p.index}" type="date" data-part="${p.index}" data-key="date" value="${esc(p.date)}" ${working?'disabled':''}></div></div><button class="btn btn-small" data-action="batch-search" data-index="${p.index}" ${working?'disabled':''}>Actualizar coincidencias</button><label for="batch-payment-${p.index}">Movimiento pendiente</label><select id="batch-payment-${p.index}" data-part="${p.index}" data-key="paymentId" ${working?'disabled':''}>${this.options(p)}</select><p id="batch-match-note-${p.index}" class="small-note">${p.paymentId?'Coincidencia seleccionada. Quedará identificado al guardar.':p.matches.length?'Elige el abono correcto entre las coincidencias.':'No se encontraron coincidencias. Puedes corregir valor o fecha.'}</p>`}</div></article>`).join('')}</div>`:''}`}
    </div><div class="modal-footer batch-footer"><span id="batch-summary" role="status">${esc(this.phase==='saving'?'Guardando soportes…':this.summary())}</span><button class="btn btn-primary" id="batch-save" data-action="batch-save" ${working||!this.selected().length?'disabled':''}>Guardar e identificar seleccionados</button></div></section></div>`);
   const body=$('.receipt-batch .modal-body');if(body)body.scrollTop=top;
  }
  async action(action,index){
   if(!this.active)return;
   if(action==='batch-view-left'||action==='batch-view-right')return this.rotateView(action==='batch-view-left'?-90:90);
   if(action==='batch-single-whole'){
    if(this.busy||!this.preview||this.parts.some(p=>p.saved)||!this.h.singleWhole)return;
    return this.h.singleWhole(this.source,this.preview,{showId:this.shared.showId==='__new'?'':this.shared.showId,entrepreneur:this.shared.entrepreneur});
   }
   if(action.startsWith('batch-reference-')){
    if(this.busy)return;
    if(action==='batch-reference-open'){
     const p=this.parts.find(p=>p.index===Number(index));if(!p)return;this.referenceReturnScroll=$('.receipt-batch .modal-body')?.scrollTop||0;
     this.referenceIndex=p.index;this.referenceDraft={...(p.visualBounds||{x:0,y:0,width:1000,height:1000})};this.referenceZoom=1;this.referencePan=!!p.saved;this.render();return;
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
