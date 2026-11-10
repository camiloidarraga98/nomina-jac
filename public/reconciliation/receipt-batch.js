/* Private receipt groups: all requests use the host's existing CRM session. */
(() => {
  'use strict';
  const limit=20;
  const $=selector=>document.querySelector(selector);
  const clamp=(n,min,max)=>Math.max(min,Math.min(max,n));
  const blobFromCanvas=canvas=>new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(Error('No se pudo preparar la imagen.')),'image/jpeg',.94));
  window.JacReceiptBatch=class {
    static originalBounds(b,rotation){
      if(rotation===90)return {x:b.y,y:1000-b.x-b.width,width:b.height,height:b.width};
      if(rotation===180)return {x:1000-b.x-b.width,y:1000-b.y-b.height,width:b.width,height:b.height};
      if(rotation===270)return {x:1000-b.y-b.height,y:b.x,width:b.height,height:b.width};
      return {...b};
    }
    static rotatedCanvas(source,rotation){
      const canvas=document.createElement('canvas'),turn=rotation===90||rotation===270;
      canvas.width=turn?source.height:source.width;canvas.height=turn?source.width:source.height;
      const c=canvas.getContext('2d');c.fillStyle='#fff';c.fillRect(0,0,canvas.width,canvas.height);c.translate(canvas.width/2,canvas.height/2);c.rotate(rotation*Math.PI/180);c.drawImage(source,-source.width/2,-source.height/2);return canvas;
    }
    constructor(host){
      this.h=host;this.active=true;this.busy=false;this.parts=[];this.shared={showId:'',entrepreneur:'',name:'',date:'',city:''};this.error='';this.phase='preparing';this.operation=null;this.rotation=0;this.needsReview=false;this.geometryWarnings=[];this.detectionFailed=false;
      this.click=event=>{const button=event.target.closest('[data-action^="batch-"]');if(button&&!button.disabled)this.action(button.dataset.action,button.dataset.index);};
      this.change=event=>this.input(event.target,event.type);
      document.addEventListener('click',this.click);document.addEventListener('input',this.change);document.addEventListener('change',this.change);
    }
    dispose(){this.active=false;this.controller?.abort();this.image?.close();if(this.url)URL.revokeObjectURL(this.url);for(const p of this.parts)if(p.url)URL.revokeObjectURL(p.url);this.parts=[];this.source=null;this.preview=null;this.shared={};document.removeEventListener('click',this.click);document.removeEventListener('input',this.change);document.removeEventListener('change',this.change);}
    setBusy(value){this.busy=value;if(this.active)this.h.busy(value);}
    async start(file){
      this.source=file;this.setBusy(true);this.h.dirty(true);this.render();
      try{
        const bitmap=await createImageBitmap(file);if(!this.active){bitmap.close();return;}
        const scale=Math.min(1,4096/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);
        const context=canvas.getContext('2d');context.fillStyle='#fff';context.fillRect(0,0,canvas.width,canvas.height);context.drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();
        const blob=await blobFromCanvas(canvas);if(!this.active)return;if(blob.size>5*1024*1024)throw Error('La imagen es demasiado grande. Usa una copia de menor tamaño.');
        this.preview=new File([blob],'vista-comprobantes.jpg',{type:'image/jpeg'});this.image=await createImageBitmap(blob);if(!this.active){this.image.close();return;}this.url=URL.createObjectURL(blob);
        await this.detectRegions();
      }catch(error){if(this.active){this.error=error.message;this.needsReview=true;this.detectionFailed=true;}}
      finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}
    }
    async detectRegions(){
      this.controller=new AbortController();
      if(!this.layout){
        this.phase='counting';this.render();const form=new FormData();form.set('file',this.preview);
        this.layout=await this.h.api('/api/reconciliation/scan/layout',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;
      }
      this.rotation=this.layout.rotation;this.phase='detecting';this.render();
      const oriented=this.constructor.rotatedCanvas(this.image,this.rotation),imageBlob=await blobFromCanvas(oriented),grid=await this.coordinateGuide(oriented);if(!this.active)return;
      const form=new FormData();form.set('file',new File([imageBlob],'comprobantes.jpg',{type:'image/jpeg'}));form.set('grid',new File([grid],'guias.jpg',{type:'image/jpeg'}));form.set('expectedCount',String(this.layout.count));
      const result=await this.h.api('/api/reconciliation/scan/regions',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;
      for(const part of this.parts)if(part.url)URL.revokeObjectURL(part.url);this.parts=[];this.operation=null;
      this.needsReview=!!result.needsReview;this.geometryWarnings=result.warnings||[];
      for(const [index,viewBounds] of result.regions.entries()){const bounds=this.constructor.originalBounds(viewBounds,this.rotation),part=this.newPart(index,bounds);this.parts.push(part);await this.crop(part);if(!this.active)return;}
      this.detectionFailed=false;if(!this.parts.length)this.error='No se delimitaron comprobantes automáticamente. Puedes agregar los recortes manualmente.';
    }
    newPart(index,bounds){return {index,bounds,amount:'',date:'',matches:[],paymentId:'',version:null,read:false,saved:false,error:'',warnings:[]};}
    async coordinateGuide(source){
      const canvas=document.createElement('canvas'),scale=Math.min(1,1600/Math.max(source.width,source.height));canvas.width=Math.round(source.width*scale);canvas.height=Math.round(source.height*scale);const c=canvas.getContext('2d');c.drawImage(source,0,0,canvas.width,canvas.height);
      c.lineWidth=1;c.font='bold 13px sans-serif';
      for(let n=0;n<=1000;n+=100){const x=n*canvas.width/1000,y=n*canvas.height/1000;c.strokeStyle='#1675cf88';c.beginPath();c.moveTo(x,0);c.lineTo(x,canvas.height);c.moveTo(0,y);c.lineTo(canvas.width,y);c.stroke();
        const label=(text,x,y)=>{const w=c.measureText(text).width+6;c.fillStyle='#fff';c.fillRect(clamp(x,0,canvas.width-w),clamp(y,0,canvas.height-18),w,18);c.fillStyle='#00488c';c.fillText(text,clamp(x,0,canvas.width-w)+3,clamp(y,0,canvas.height-18)+14);};
        label('x '+n,x,0);label('x '+n,x,canvas.height-18);if(n>0&&n<1000){label('y '+n,0,y);label('y '+n,canvas.width-55,y);}
      }return blobFromCanvas(canvas);
    }
    async crop(part){
      const b=part.bounds,w=this.image.width,h=this.image.height,canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(w*b.width/1000));canvas.height=Math.max(1,Math.round(h*b.height/1000));
      canvas.getContext('2d').drawImage(this.image,w*b.x/1000,h*b.y/1000,w*b.width/1000,h*b.height/1000,0,0,canvas.width,canvas.height);
      const blob=await blobFromCanvas(this.rotation?this.constructor.rotatedCanvas(canvas,this.rotation):canvas);if(!this.active)return;
      if(part.url)URL.revokeObjectURL(part.url);part.file=new File([blob],`comprobante-${part.index+1}.jpg`,{type:'image/jpeg'});part.url=URL.createObjectURL(blob);
    }
    options(part){
      const used=new Set(this.parts.filter(p=>p!==part&&p.paymentId).map(p=>p.paymentId));
      return '<option value="">Elige un movimiento pendiente</option>'+part.matches.filter(p=>p.status!=='identified').map(p=>`<option value="${this.h.esc(p.id)}" ${part.paymentId===p.id?'selected':''} ${used.has(p.id)?'disabled':''}>${this.h.esc(this.h.money(p.amount))} · ${this.h.esc(this.h.date(p.date))}${used.has(p.id)?' · Ya elegido':p.kind==='exact'?' · Valor y fecha':' · Revisa la fecha'}${p.entrepreneur?' · '+this.h.esc(p.entrepreneur):''}</option>`).join('');
    }
    selected(){return this.parts.filter(p=>!p.saved&&p.paymentId&&p.version);}
    summary(){const selected=this.selected();return `${selected.length} por guardar · ${this.parts.filter(p=>p.saved).length} guardados · ${this.parts.filter(p=>!p.saved&&!p.paymentId).length} sin asignar`;}
    render(){
      if(!this.active)return;if(this.gridEditing){this.renderGrid();return;}if(this.editing!==undefined){this.renderCrop();return;}
      const {esc,money,date}=this.h,working=this.busy,locked=working||this.parts.some(p=>p.saved),top=$('.receipt-batch .modal-body')?.scrollTop||0;
      const show=this.h.shows().find(s=>s.id===this.shared.showId);
      this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">Varios comprobantes de un show</h2><p>Un movimiento por recibo, con el mismo show y empresario.</p></div><button class="icon-close" data-action="batch-close" aria-label="Cerrar grupo" ${this.phase==='saving'?'disabled':''}>×</button></div><div class="modal-body">
        ${this.error?`<div class="error-banner" role="alert">${esc(this.error)}${this.detectionFailed&&this.image&&!this.parts.some(p=>p.saved)?`<p><button class="btn" data-action="batch-detect" ${working?'disabled':''}>Reintentar separación</button></p>`:''}</div>`:''}
        ${this.url?`<details class="batch-original" ${this.needsReview?'open':''}><summary>Revisar separación · ${this.parts.length} recortes${this.layout?` · Conteo: ${this.layout.count}`:''}</summary><div class="batch-map" style="--image-ratio:${this.image.width/this.image.height}"><img src="${esc(this.url)}" alt="Foto completa con los límites de cada comprobante">${this.parts.map(p=>`<button class="batch-map-box" data-action="batch-crop" data-index="${p.index}" style="left:${p.bounds.x/10}%;top:${p.bounds.y/10}%;width:${p.bounds.width/10}%;height:${p.bounds.height/10}%" aria-label="Ajustar comprobante ${p.index+1}" ${working||p.saved?'disabled':''}><span>${p.index+1}</span></button>`).join('')}</div></details>`:''}
        ${['preparing','counting','detecting'].includes(this.phase)?`<div class="loading-state" role="status"><span class="spinner"></span>${this.phase==='preparing'?'Preparando imagen…':this.phase==='counting'?'Contando los recibos y revisando su orientación…':'Delimitando y verificando los recortes completos…'}</div>`:`
        ${this.needsReview?`<div class="notice warning" role="alert">${this.geometryWarnings.map(esc).join('<br>')||'Revisa la separación antes de leer. Cada cuadro debe incluir un recibo completo.'}<br><button class="btn" data-action="batch-confirm-crops" ${working||!this.parts.length?'disabled':''}>Ya revisé: un recibo completo por recorte</button></div>`:''}
        <div class="notice">Revisa que haya un recorte por comprobante y que todos estén incluidos. Puedes ajustar, quitar o agregar recortes antes de leerlos.</div>
        <div class="batch-tools"><button class="btn" data-action="batch-add" ${working||!this.image||this.parts.length>=limit?'disabled':''}>+ Agregar recorte</button><button class="btn" data-action="batch-grid" ${working||!this.image||this.parts.some(p=>p.saved)?'disabled':''}>Separar por filas y columnas</button><button class="btn btn-primary" data-action="batch-read" ${working||this.needsReview||!this.parts.some(p=>!p.saved&&!p.read)?'disabled':''}>Leer comprobantes pendientes</button>${this.phase==='reading'?'<button class="btn" data-action="batch-stop">Detener lectura</button>':''}</div>
        <section class="batch-shared"><h3>Datos comunes del grupo</h3><div class="form-grid"><div class="form-field full"><label for="batch-show">Show y fecha del show</label><select id="batch-show" data-common="showId" ${locked?'disabled':''}><option value="">Selecciona el show</option>${[...this.h.shows()].sort((a,b)=>b.date.localeCompare(a.date)).map(s=>`<option value="${esc(s.id)}" ${this.shared.showId===s.id?'selected':''}>${esc(date(s.date))} · ${esc(s.name)}</option>`).join('')}<option value="__new" ${this.shared.showId==='__new'?'selected':''}>+ Agregar show histórico</option></select></div><div class="form-field full"><label for="batch-entrepreneur">Empresario</label><input id="batch-entrepreneur" class="input" data-common="entrepreneur" value="${esc(this.shared.entrepreneur)}" maxlength="300" ${locked?'disabled':''}></div>${this.shared.showId==='__new'?`<div class="form-field full"><label for="batch-name">Nombre del show histórico</label><input id="batch-name" class="input" data-common="name" value="${esc(this.shared.name)}" maxlength="200" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-date">Fecha del show</label><input type="date" id="batch-date" data-common="date" value="${esc(this.shared.date)}" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-city">Ciudad</label><input class="input" id="batch-city" data-common="city" value="${esc(this.shared.city)}" maxlength="100" ${locked?'disabled':''}></div>`:''}</div><p class="small-note">${show?`Fecha del show: ${esc(date(show.date))}. `:''}Cada recibo conserva su propia fecha bancaria. Los pagos siguen siendo movimientos separados.</p></section>
        <div class="batch-cards">${this.parts.map(p=>`<article class="batch-card" id="batch-part-${p.index}"><div class="batch-preview">${p.url?`<a href="${esc(p.url)}" target="_blank" rel="noopener"><img src="${esc(p.url)}" alt="Recorte del comprobante ${p.index+1}"></a>`:''}<strong>Comprobante ${p.index+1}</strong><div class="batch-tools"><button class="link-button" data-action="batch-crop" data-index="${p.index}" ${working||p.saved?'disabled':''}>Ajustar recorte</button><button class="link-button" data-action="batch-remove" data-index="${p.index}" ${working||p.saved?'disabled':''}>Quitar</button></div></div><div class="batch-fields">${p.saved?`<div class="notice"><strong>Guardado e identificado</strong>${p.supportUrl?`<p><a href="${esc(p.supportUrl)}" target="_blank" rel="noopener">Consultar soporte PDF</a></p>`:''}</div>`:`
          ${this.readingIndex===p.index?'<div class="loading-state" role="status"><span class="spinner"></span>Leyendo y comprobando este recibo…</div>':''}
          ${p.error?`<div class="error-banner" role="alert">${esc(p.error)}</div>`:''}${p.warnings.length?`<div class="notice warning">${p.warnings.map(esc).join('<br>')}</div>`:''}
          <div class="form-grid"><div class="form-field"><label for="batch-amount-${p.index}">Valor (COP)</label><input class="input" id="batch-amount-${p.index}" data-part="${p.index}" data-key="amount" inputmode="decimal" value="${esc(p.amount)}" ${working?'disabled':''}></div><div class="form-field"><label for="batch-bank-date-${p.index}">Fecha bancaria</label><input class="input" type="date" id="batch-bank-date-${p.index}" data-part="${p.index}" data-key="date" value="${esc(p.date)}" ${working?'disabled':''}></div></div>
          <div class="batch-tools"><button class="btn btn-small" data-action="batch-search" data-index="${p.index}" ${working?'disabled':''}>Buscar coincidencias</button><button class="link-button" data-action="batch-reread" data-index="${p.index}" ${working||this.needsReview?'disabled':''}>${p.read?'Volver a leer':'Leer este recibo'}</button></div>
          <label for="batch-payment-${p.index}">Movimiento pendiente</label><select id="batch-payment-${p.index}" data-part="${p.index}" data-key="paymentId" ${working?'disabled':''}>${this.options(p)}</select><p class="small-note" id="batch-match-note-${p.index}">${p.matches.length?`${p.matches.length} coincidencias; confirma el valor y la fecha.`:'Busca por valor y/o fecha para elegir el registro.'}</p>`}</div></article>`).join('')}</div>`}
        </div><div class="modal-footer batch-footer"><span id="batch-summary" role="status">${esc(this.phase==='saving'?'Guardando soportes e identificación…':this.summary())}</span><button class="btn btn-primary" data-action="batch-save" id="batch-save" ${working||this.needsReview||!this.selected().length?'disabled':''}>Guardar e identificar seleccionados</button></div></section></div>`);
      const body=$('.receipt-batch .modal-body');if(body)body.scrollTop=top;
    }
    input(el,eventType){
      if(!this.active||this.busy)return;
      if(el.dataset.grid&&eventType==='change'){this.gridDraft[el.dataset.grid]=Number(el.value);this.renderGrid();return;}
      if(el.dataset.common){this.shared[el.dataset.common]=el.value;if(el.dataset.common==='showId'&&eventType==='change'){const show=this.h.shows().find(s=>s.id===el.value);if(show?.entrepreneur)this.shared.entrepreneur=show.entrepreneur;this.render();}this.h.dirty(true);return;}
      if(el.dataset.part===undefined)return;const p=this.parts.find(p=>p.index===Number(el.dataset.part));if(!p||p.saved)return;
      if(el.dataset.key==='paymentId'){
        if(eventType!=='change')return;
        const candidate=p.matches.find(c=>c.id===el.value&&c.status!=='identified');
        if(candidate&&!this.parts.some(other=>other!==p&&other.paymentId===candidate.id)){p.paymentId=candidate.id;p.version=candidate.version;}else{p.paymentId='';p.version=null;}this.render();
      }else{p[el.dataset.key]=el.value;p.paymentId='';p.version=null;p.matches=[];const select=$(`#batch-payment-${p.index}`);if(select)select.innerHTML=this.options(p);const note=$(`#batch-match-note-${p.index}`);if(note)note.textContent='Pulsa Buscar coincidencias para aplicar estos datos.';if($('#batch-summary'))$('#batch-summary').textContent=this.summary();if($('#batch-save'))$('#batch-save').disabled=this.needsReview||!this.selected().length;}
      this.h.dirty(true);
    }
    async action(action,index){
      if(!this.active)return;const p=this.parts.find(p=>p.index===Number(index));
      if(action==='batch-close'){if(this.phase==='saving')return;if(this.h.isDirty()&&!confirm('Hay comprobantes o cambios sin guardar. ¿Quieres cerrar el grupo?'))return;this.h.close();return;}
      if(action==='batch-stop'){this.stopRequested=true;this.controller?.abort();return;}
      if(this.busy)return;
      if(action==='batch-detect'&&this.image&&!this.parts.some(p=>p.saved)){
        if(this.parts.some(p=>p.read||p.paymentId)&&!confirm('Reintentar retirará las lecturas y selecciones sin guardar si consigue nuevos recortes. ¿Continuar?'))return;
        this.setBusy(true);this.error='';this.render();
        try{await this.detectRegions();}catch(error){if(this.active){this.error=error.message;this.needsReview=true;this.detectionFailed=true;}}
        finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}return;
      }
      if(action==='batch-confirm-crops'){
        const overlap=this.parts.some((p,i)=>this.parts.slice(i+1).some(q=>{const a=p.bounds,b=q.bounds,area=Math.max(0,Math.min(a.x+a.width,b.x+b.width)-Math.max(a.x,b.x))*Math.max(0,Math.min(a.y+a.height,b.y+b.height)-Math.max(a.y,b.y));return area>.8*Math.min(a.width*a.height,b.width*b.height);}));
        if(overlap){this.error='Hay recortes repetidos o superpuestos. Ajústalos antes de confirmar.';this.render();return;}
        this.needsReview=false;this.detectionFailed=false;this.geometryWarnings=[];this.error='';this.render();return;
      }
      if(action==='batch-grid'&&!this.parts.some(p=>p.saved)){
        if(this.parts.some(p=>p.read||p.paymentId)&&!confirm('Separar de nuevo retirará las lecturas y selecciones sin guardar. ¿Continuar?'))return;
        const turn=this.rotation===90||this.rotation===270;this.gridDraft={rows:(turn?this.layout?.columns:this.layout?.rows)||1,columns:(turn?this.layout?.rows:this.layout?.columns)||1,bounds:{x:0,y:0,width:1000,height:1000}};this.gridEditing=true;this.render();return;
      }
      if(action==='batch-grid-cancel'){this.gridEditing=false;this.render();return;}
      if(action==='batch-grid-apply')return this.applyGrid();
      if(action==='batch-read')return this.readParts(this.parts.filter(p=>!p.saved&&!p.read));
      if(action==='batch-reread'&&p&&!p.saved)return this.readParts([p]);
      if(action==='batch-search'&&p&&!p.saved)return this.search(p);
      if(action==='batch-save')return this.save();
      if(action==='batch-remove'&&p&&!p.saved){if(p.url)URL.revokeObjectURL(p.url);this.parts=this.parts.filter(part=>part!==p);this.needsReview=true;this.render();}
      if(action==='batch-add'&&this.parts.length<limit&&this.image){const used=new Set(this.parts.map(p=>p.index)),index=Array.from({length:limit},(_,i)=>i).find(i=>!used.has(i));const part=this.newPart(index,{x:0,y:0,width:1000,height:1000});this.parts.push(part);this.adding=index;this.editing=index;this.draftBounds={...part.bounds};this.render();}
      if(action==='batch-crop'&&p&&!p.saved){this.editing=p.index;this.draftBounds={...p.bounds};this.render();}
      if(action==='batch-crop-cancel'){if(this.adding!==undefined)this.parts=this.parts.filter(p=>p.index!==this.adding);this.adding=undefined;this.editing=undefined;this.render();}
      if(action==='batch-crop-apply'){
        const part=this.parts.find(p=>p.index===this.editing);if(!part)return;
        Object.assign(part,{bounds:this.draftBounds,read:false,paymentId:'',version:null,matches:[],warnings:[],amount:'',date:'',error:''});this.needsReview=true;this.adding=undefined;this.editing=undefined;this.setBusy(true);this.render();
        try{await this.crop(part);}catch(error){part.error=error.message;}finally{if(this.active){this.setBusy(false);this.render();}}
      }
    }
    gridBounds(){
      const {rows,columns,bounds:b}=this.gridDraft;if(!Number.isInteger(rows)||!Number.isInteger(columns)||rows<1||columns<1||rows*columns>limit)return [];
      return Array.from({length:rows*columns},(_,i)=>{const col=i%columns,row=Math.floor(i/columns),x=Math.round(b.x+b.width*col/columns),y=Math.round(b.y+b.height*row/rows);return {x,y,width:Math.round(b.x+b.width*(col+1)/columns)-x,height:Math.round(b.y+b.height*(row+1)/rows)-y};});
    }
    renderGrid(){
      if(!this.active)return;const {esc}=this.h,boxes=this.gridBounds();
      this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">Separar por filas y columnas</h2><p>Cuenta las filas y columnas tal como aparecen en esta foto.</p></div></div><div class="modal-body"><div class="form-grid"><div class="form-field"><label for="batch-grid-rows">Filas</label><input class="input" type="number" min="1" max="20" id="batch-grid-rows" data-grid="rows" value="${this.gridDraft.rows}"></div><div class="form-field"><label for="batch-grid-columns">Columnas</label><input class="input" type="number" min="1" max="20" id="batch-grid-columns" data-grid="columns" value="${this.gridDraft.columns}"></div></div><p class="small-note">Arrastra para marcar el área que ocupan todos los recibos. Se dividirá en ${boxes.length} recortes. Después puedes ajustar cada borde si los papeles están inclinados.</p><div class="batch-crop-stage" id="batch-grid-stage" style="--image-ratio:${this.image.width/this.image.height}"><img src="${esc(this.url)}" alt="Foto completa con separación por filas y columnas" draggable="false"><div id="batch-grid-boxes">${this.gridBoxMarkup(boxes)}</div></div>${!boxes.length?'<div class="error-banner">Elige entre 1 y 20 recortes en total.</div>':''}</div><div class="modal-footer"><button class="btn" data-action="batch-grid-cancel">Volver</button><button class="btn btn-primary" data-action="batch-grid-apply" ${!boxes.length?'disabled':''}>Crear estos recortes</button></div></section></div>`);
      this.bindRectangle($('#batch-grid-stage'),b=>{this.gridDraft.bounds=b;$('#batch-grid-boxes').innerHTML=this.gridBoxMarkup(this.gridBounds());});
    }
    gridBoxMarkup(boxes){return boxes.map((b,i)=>`<div class="batch-grid-box" style="left:${b.x/10}%;top:${b.y/10}%;width:${b.width/10}%;height:${b.height/10}%"><span>${i+1}</span></div>`).join('');}
    bindRectangle(stage,change){
      let start=null;const point=e=>{const r=stage.getBoundingClientRect();return {x:clamp(Math.round((e.clientX-r.left)*1000/r.width),0,1000),y:clamp(Math.round((e.clientY-r.top)*1000/r.height),0,1000)};};
      stage.onpointerdown=e=>{if(e.button!==0&&e.pointerType==='mouse')return;e.preventDefault();start=point(e);stage.setPointerCapture(e.pointerId);};
      stage.onpointermove=e=>{if(!start)return;e.preventDefault();const end=point(e),x=Math.min(start.x,end.x),y=Math.min(start.y,end.y),width=Math.abs(start.x-end.x),height=Math.abs(start.y-end.y);if(width<10||height<10)return;change({x,y,width,height});};
      stage.onpointerup=stage.onpointercancel=()=>{start=null;};
    }
    async applyGrid(){
      const boxes=this.gridBounds();if(!boxes.length||boxes.some(b=>b.width<10||b.height<10))return;
      for(const p of this.parts)if(p.url)URL.revokeObjectURL(p.url);this.parts=boxes.map((b,i)=>this.newPart(i,b));this.gridEditing=false;this.needsReview=true;this.geometryWarnings=['Revisa que cada cuadro incluya un solo recibo, con su fecha y valor completos.'];this.error='';this.operation=null;this.setBusy(true);this.h.dirty(true);this.render();
      try{for(const p of this.parts){await this.crop(p);if(!this.active)return;}}catch(e){if(this.active)this.error=e.message;}finally{if(this.active){this.setBusy(false);this.render();}}
    }
    renderCrop(){
      const b=this.draftBounds,esc=this.h.esc;
      this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">Recorte del comprobante ${this.editing+1}</h2><p>Arrastra sobre la imagen para incluir un solo recibo completo.</p></div></div><div class="modal-body"><div class="batch-crop-stage" id="batch-crop-stage" style="--image-ratio:${this.image.width/this.image.height}"><img src="${esc(this.url)}" alt="Imagen completa para delimitar un recibo" draggable="false"><div class="batch-crop-box" id="batch-crop-box" style="left:${b.x/10}%;top:${b.y/10}%;width:${b.width/10}%;height:${b.height/10}%"></div></div><p class="small-note">Incluye la fecha y el valor, y deja fuera los demás comprobantes.</p></div><div class="modal-footer"><button class="btn" data-action="batch-crop-cancel">Volver</button><button class="btn btn-primary" data-action="batch-crop-apply">Usar este recorte</button></div></section></div>`);
      this.bindRectangle($('#batch-crop-stage'),b=>{this.draftBounds=b;Object.assign($('#batch-crop-box').style,{left:b.x/10+'%',top:b.y/10+'%',width:b.width/10+'%',height:b.height/10+'%'});});
    }
    applyMatches(p,result,auto=false){
      p.matches=(result.matches||[]).filter(c=>c.status!=='identified');p.paymentId='';p.version=null;
      const candidate=auto?p.matches.find(c=>c.id===result.autoMatchId):null;
      if(candidate&&!this.parts.some(other=>other!==p&&other.paymentId===candidate.id)){p.paymentId=candidate.id;p.version=candidate.version;}
    }
    async readParts(parts){
      if(!parts.length||this.needsReview)return;this.setBusy(true);this.phase='reading';this.stopRequested=false;this.error='';
      try{for(const p of parts){
        if(!this.active||this.stopRequested)break;this.readingIndex=p.index;p.error='';p.read=false;p.paymentId='';p.version=null;p.matches=[];p.warnings=[];this.render();this.controller=new AbortController();
        try{
          if(!p.file)await this.crop(p);if(!this.active||this.stopRequested)break;
          const form=new FormData();form.set('file',p.file);const result=await this.h.api('/api/reconciliation/scan',{method:'POST',body:form,signal:this.controller.signal});if(!this.active||this.stopRequested)break;
          p.read=true;p.amount=result.reading?.amount==null?'':new Intl.NumberFormat('es-CO',{maximumFractionDigits:2}).format(result.reading.amount);p.date=result.reading?.date||'';p.warnings=result.reading?.warnings||[];this.applyMatches(p,result,true);
          if(result.existingPaymentId)p.error='Este comprobante ya está guardado en otro abono. Revisa ese registro antes de repetirlo.';
        }catch(error){if(this.active&&!this.stopRequested)p.error=error.message;}
      }}finally{if(this.active){this.readingIndex=undefined;this.phase='review';this.setBusy(false);this.render();}}
    }
    async search(p){
      const amount=p.amount.trim()?this.h.amount(p.amount):null;
      if((p.amount.trim()&&(!Number.isFinite(amount)||amount<=0))||(!amount&&!p.date)){p.error='Escribe un valor positivo y/o una fecha.';this.render();return;}
      this.setBusy(true);p.error='';this.render();this.controller=new AbortController();
      try{const result=await this.h.api('/api/reconciliation/scan/matches',{method:'POST',body:JSON.stringify({amount,date:p.date||null}),signal:this.controller.signal});if(this.active)this.applyMatches(p,result);}
      catch(error){if(this.active)p.error=error.message;}
      finally{if(this.active){this.setBusy(false);this.render();}}
    }
    async save(){
      const parts=this.selected();if(!parts.length||this.needsReview)return;
      if(!this.shared.showId||!this.shared.entrepreneur.trim()){this.error='Selecciona el show y escribe el empresario para todo el grupo.';this.render();return;}
      if(new Set(parts.map(p=>p.paymentId)).size!==parts.length){this.error='Elige un movimiento diferente para cada recibo.';this.render();return;}
      this.setBusy(true);this.phase='saving';this.error='';this.render();this.controller=new AbortController();
      try{
        if(this.shared.showId==='__new'){
          if(!this.shared.name.trim()||!this.shared.date)throw Error('Escribe el nombre y la fecha del show histórico.');
          const show=await this.h.api('/api/reconciliation/shows',{method:'POST',body:JSON.stringify({name:this.shared.name,date:this.shared.date,city:this.shared.city,entrepreneur:this.shared.entrepreneur})});if(!this.active)return;this.shared.showId=show.id;await this.h.reload();if(!this.active)return;
        }
        const selection={showId:this.shared.showId,entrepreneur:this.shared.entrepreneur.trim(),parts:parts.map(p=>({paymentId:p.paymentId,version:p.version,index:p.index,bounds:p.bounds}))},signature=JSON.stringify(selection);
        if(this.operation?.signature!==signature)this.operation={id:crypto.randomUUID(),signature};
        const form=new FormData();form.set('file',this.source);form.set('preview',this.preview);form.set('plan',JSON.stringify({...selection,operationId:this.operation.id}));
        const result=await this.h.api('/api/reconciliation/batch',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;
        for(const p of parts)if(result.paymentIds.includes(p.paymentId)){p.saved=true;p.supportUrl=result.files.find(f=>f.paymentId===p.paymentId)?.url||'';}
        this.operation=null;await this.h.reload();if(!this.active)return;
        this.h.dirty(this.parts.some(p=>!p.saved));
      }catch(error){if(this.active)this.error=error.message;}
      finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}
    }
  };
})();
