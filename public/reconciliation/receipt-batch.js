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
    // A/B/C/D are actual rendered alternatives, not a request to reason about
    // clockwise versus counterclockwise angles. Keep labels outside the photo.
    static orientationSheet(source){
      const canvas=document.createElement('canvas'),cell=1000,header=64,pad=24;canvas.width=cell*2;canvas.height=cell*2;
      const c=canvas.getContext('2d');c.fillStyle='#e8eef3';c.fillRect(0,0,canvas.width,canvas.height);
      for(const [index,rotation] of [0,90,180,270].entries()){
        const x=index%2*cell,y=Math.floor(index/2)*cell,turn=rotation===90||rotation===270,w=turn?source.height:source.width,h=turn?source.width:source.height;
        const scale=Math.min((cell-pad*2)/w,(cell-header-pad*2)/h);
        c.fillStyle='#fff';c.fillRect(x+4,y+4,cell-8,cell-8);c.fillStyle='#102c40';c.font='bold 48px sans-serif';c.fillText('ABCD'[index],x+pad,y+50);
        c.save();c.translate(x+cell/2,y+header+(cell-header)/2);c.rotate(rotation*Math.PI/180);c.drawImage(source,-source.width*scale/2,-source.height*scale/2,source.width*scale,source.height*scale);c.restore();
      }return canvas;
    }
    /** Locate whitespace between receipts, rather than trust estimated paper edges.
     * The outer image edges are retained: a model cannot truncate the final digits
     * of an amount by proposing a narrow right edge. No image leaves the browser.
     * Uncertain separators require visual review, even if the model said complete.
     */
    static partitionRegions(pixels,layout,proposals){
      const {width:w,height:h,data}=pixels,{rows,columns,count}=layout;
      const valid=Number.isInteger(rows)&&Number.isInteger(columns)&&rows>0&&columns>0&&rows*columns===count&&count===proposals.length&&count<=limit;
      if(!valid)return {regions:proposals,needsReview:true};
      const gray=new Uint8Array(w*h),tile=32,tw=Math.ceil(w/tile),bright=new Uint8Array(tw*Math.ceil(h/tile));
      for(let y=0;y<h;y++)for(let x=0;x<w;x++){
        const i=y*w+x,v=Math.round(.299*data[i*4]+.587*data[i*4+1]+.114*data[i*4+2]);gray[i]=v;
        const t=Math.floor(y/tile)*tw+Math.floor(x/tile);bright[t]=Math.max(bright[t],v);
      }
      const ink=new Uint8Array(w*h);
      // Local contrast ignores uneven lighting and blank grey paper. A small
      // analysis copy bounds CPU/memory; the saved crop still uses the full image.
      for(let y=0;y<h;y++)for(let x=0;x<w;x++)ink[y*w+x]=gray[y*w+x]<180&&gray[y*w+x]+40<bright[Math.floor(y/tile)*tw+Math.floor(x/tile)]?1:0;
      const ordered=[...proposals].sort((a,b)=>(a.y+a.height/2)-(b.y+b.height/2));
      const matrix=Array.from({length:rows},(_,r)=>ordered.slice(r*columns,(r+1)*columns).sort((a,b)=>(a.x+a.width/2)-(b.x+b.width/2)));
      let needsReview=false;
      const split=(hist,centers,orthogonal)=>{
        const n=hist.length,prefix=new Float64Array(n+1),cuts=[0],band=Math.max(3,Math.round(n*.006));
        for(let i=0;i<n;i++)prefix[i+1]=prefix[i]+hist[i];
        for(let k=1;k<centers.length;k++){
          const left=centers[k-1]*n/1000,right=centers[k]*n/1000,target=(left+right)/2;
          // Coarse centers constrain the search to the gap between two papers;
          // whitespace between lines inside a receipt is never a free candidate.
          const low=Math.max(cuts.at(-1)+band*2,Math.ceil(left+(right-left)*.28)),high=Math.min(n-band*2,Math.floor(right-(right-left)*.28));
          let chosen=Math.round(target),best=Infinity,activity=Infinity;
          for(let p=low;p<=high;p++){
            const a=Math.max(0,p-band),b=Math.min(n,p+band+1),density=(prefix[b]-prefix[a])/(b-a);
            const score=density+Math.abs(p-target)/n*.15;
            if(score<best){best=score;chosen=p;activity=density;}
          }
          // A dark separator can be a shadow or a character. Never silently
          // call it safe; retain a review gate before reading or assigning.
          if(high<low||activity>Math.max(1,orthogonal*.002))needsReview=true;
          cuts.push(clamp(chosen,cuts.at(-1)+1,n-(centers.length-k)));
        }
        cuts.push(n);return cuts;
      };
      const columnCenters=Array.from({length:columns},(_,c)=>matrix.reduce((sum,row)=>sum+row[c].x+row[c].width/2,0)/rows);
      const xHistogram=new Uint32Array(w);
      for(let y=0;y<h;y++)for(let x=0;x<w;x++)xHistogram[x]+=ink[y*w+x];
      const xs=split(xHistogram,columnCenters,h),cells=[];
      for(let c=0;c<columns;c++){
        const yHistogram=new Uint32Array(h);
        for(let y=0;y<h;y++)for(let x=xs[c];x<xs[c+1];x++)yHistogram[y]+=ink[y*w+x];
        const ys=split(yHistogram,matrix.map(row=>row[c].y+row[c].height/2),xs[c+1]-xs[c]);
        for(let r=0;r<rows;r++){
          // Keep a few extra pixels at internal boundaries for antialiasing and
          // small skew. Outer edges always reach the original image boundary.
          const pad=3,x=Math.max(0,xs[c]-pad),y=Math.max(0,ys[r]-pad),right=Math.min(w,xs[c+1]+pad),bottom=Math.min(h,ys[r+1]+pad);
          const b={x:Math.floor(x*1000/w),y:Math.floor(y*1000/h)};
          b.width=Math.ceil(right*1000/w)-b.x;b.height=Math.ceil(bottom*1000/h)-b.y;
          let marks=0;for(let p=ys[r];p<ys[r+1];p++)marks+=yHistogram[p];
          const anchor=matrix[r][c],cx=(anchor.x+anchor.width/2)*w/1000,cy=(anchor.y+anchor.height/2)*h/1000;
          if(marks<30||cx<xs[c]||cx>xs[c+1]||cy<ys[r]||cy>ys[r+1]||b.width<10||b.height<10)needsReview=true;
          cells[r*columns+c]=b;
        }
      }
      return {regions:cells,needsReview};
    }
    safeRegions(source,result){
      const canvas=document.createElement('canvas'),scale=Math.min(1,1600/Math.max(source.width,source.height));canvas.width=Math.round(source.width*scale);canvas.height=Math.round(source.height*scale);
      const c=canvas.getContext('2d',{willReadFrequently:true});c.drawImage(source,0,0,canvas.width,canvas.height);
      return this.constructor.partitionRegions(c.getImageData(0,0,canvas.width,canvas.height),this.layout,result.regions);
    }
    constructor(host){
      this.h=host;this.active=true;this.busy=false;this.parts=[];this.shared={showId:'',entrepreneur:'',name:'',date:'',city:''};this.error='';this.phase='preparing';this.operation=null;this.rotation=0;this.needsReview=false;this.geometryWarnings=[];this.detectionFailed=false;this.layout=host.layout?{...host.layout}:null;this.orientationVerified=false;this.orientationEditing=false;this.orientationUpdate=0;
      this.click=event=>{const button=event.target.closest('[data-action^="batch-"]');if(button&&!button.disabled)this.action(button.dataset.action,button.dataset.index);};
      this.change=event=>this.input(event.target,event.type);
      document.addEventListener('click',this.click);document.addEventListener('input',this.change);document.addEventListener('change',this.change);
    }
    dispose(){this.active=false;++this.orientationUpdate;if(this.orientationUrl)URL.revokeObjectURL(this.orientationUrl);this.controller?.abort();this.image?.close();if(this.url)URL.revokeObjectURL(this.url);for(const p of this.parts)if(p.url)URL.revokeObjectURL(p.url);this.parts=[];this.source=null;this.preview=null;this.shared={};document.removeEventListener('click',this.click);document.removeEventListener('input',this.change);document.removeEventListener('change',this.change);}
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
        // Older servers may still return a model-proposed angle. Restore the
        // original frame before any image is rendered for reading.
        this.setOrientation(0);
      }
      if(this.manualRotation!==undefined)this.setOrientation(this.manualRotation);
      if(!this.orientationVerified){
        if(this.h.reviewOrientation){this.h.reviewOrientation=false;this.orientationManual=true;const confirmed=this.layout.userConfirmedRotation;await this.beginOrientationReview([0,90,180,270].includes(confirmed)?confirmed:0);return;}
        this.phase='orienting';this.render();
        const sheet=await blobFromCanvas(this.constructor.orientationSheet(this.image));if(!this.active)return;
        if(sheet.size>5*1024*1024)throw Error('La comparación de orientación supera 5 MB. Usa una copia de menor tamaño.');
        const form=new FormData();form.set('file',new File([sheet],'orientaciones.jpg',{type:'image/jpeg'}));
        const checked=await this.h.api('/api/reconciliation/scan/orientation',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;
        // An AI choice can be wrong even when both readings agree. Any
        // non-zero angle is only a suggestion, including older API responses.
        this.suggestedRotation=[90,180,270].includes(checked.suggestedRotation)?checked.suggestedRotation:[90,180,270].includes(checked.rotation)?checked.rotation:null;
        this.setOrientation(0);
        if(checked.needsReview||checked.rotation!==0||this.suggestedRotation!==null){await this.beginOrientationReview(0);return;}
        this.orientationVerified=true;
      }
      // One upload entry point. Reuse this count for groups; a single receipt
      // goes to the full-original reader without region requests or cropping.
      if(this.layout.count===1&&this.h.single&&!this.h.forceGroup){
        const readingImage=this.layout.rotation?new File([await blobFromCanvas(this.constructor.rotatedCanvas(this.image,this.layout.rotation))],'comprobante-orientado.jpg',{type:'image/jpeg'}):this.preview;
        if(!this.active)return;if(readingImage.size>5*1024*1024)throw Error('La vista para lectura supera 5 MB. Usa una copia de menor tamaño.');
        return this.h.single(this.source,false,readingImage,{...this.layout});
      }
      this.rotation=this.layout.rotation;this.phase='detecting';this.render();
      const oriented=this.constructor.rotatedCanvas(this.image,this.rotation),imageBlob=await blobFromCanvas(oriented),grid=await this.coordinateGuide(oriented);if(!this.active)return;
      const form=new FormData();form.set('file',new File([imageBlob],'comprobantes.jpg',{type:'image/jpeg'}));form.set('grid',new File([grid],'guias.jpg',{type:'image/jpeg'}));form.set('expectedCount',String(this.layout.count));
      const result=await this.h.api('/api/reconciliation/scan/regions',{method:'POST',body:form,signal:this.controller.signal});if(!this.active)return;
      for(const part of this.parts)if(part.url)URL.revokeObjectURL(part.url);this.parts=[];this.operation=null;
      const safe=this.safeRegions(oriented,result);
      this.needsReview=!!result.needsReview||safe.needsReview||!!this.h.forceGroup;this.geometryWarnings=[...(result.warnings||[])];
      if(this.h.forceGroup)this.geometryWarnings.push('Las lecturas no coinciden en el número de recibos. Revisa la separación antes de continuar.');
      if(safe.needsReview)this.geometryWarnings.push('Revisa la separación: no se encontró espacio libre suficiente entre todos los recibos. Ajusta los cuadros para conservar la fecha y el valor completos.');
      for(const [index,viewBounds] of safe.regions.entries()){const bounds=this.constructor.originalBounds(viewBounds,this.rotation),part=this.newPart(index,bounds);this.parts.push(part);await this.crop(part);if(!this.active)return;}
      this.detectionFailed=false;if(!this.parts.length)this.error='No se delimitaron comprobantes automáticamente. Puedes agregar los recortes manualmente.';
      if(this.parts.length&&!this.needsReview)await this.readParts(this.parts);
    }
    setOrientation(rotation){
      if(this.layout){const difference=(rotation-this.layout.rotation+360)%360;if(difference===90||difference===270)[this.layout.rows,this.layout.columns]=[this.layout.columns,this.layout.rows];this.layout.rotation=rotation;}
      this.rotation=rotation;
    }
    async beginOrientationReview(rotation){
      this.orientationEditing=true;this.orientationDraft=rotation;this.error='';this.setBusy(true);this.render();try{await this.refreshOrientationPreview();}catch(error){if(this.active)this.error=error.message;}finally{if(this.active){this.setBusy(false);this.render();}}
    }
    async refreshOrientationPreview(){
      const update=++this.orientationUpdate,blob=await blobFromCanvas(this.constructor.rotatedCanvas(this.image,this.orientationDraft));
      if(!this.active||!this.orientationEditing||update!==this.orientationUpdate)return;
      if(this.orientationUrl)URL.revokeObjectURL(this.orientationUrl);this.orientationUrl=URL.createObjectURL(blob);this.orientationPreviewRotation=this.orientationDraft;this.render();
    }
    renderOrientation(){
      const esc=this.h.esc,previewReady=!this.busy&&!!this.orientationUrl&&this.orientationPreviewRotation===this.orientationDraft;
      this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">Revisar orientación</h2><p>Deja el texto derecho antes de leer la fecha y el valor.</p></div><button class="icon-close" data-action="batch-close" aria-label="Cerrar revisión">×</button></div><div class="modal-body"><div class="notice">${this.orientationManual&&[90,180,270].includes(this.layout?.userConfirmedRotation)?'Esta es la orientación que confirmaste. Puedes conservarla, ajustarla o volver a la imagen original.':'Conservamos la orientación original de la imagen. Si ya se lee bien, mantenla para continuar. Sólo aplicaremos un giro cuando lo confirmes.'}</div>${this.error?`<div class="error-banner" role="alert">${esc(this.error)}</div>`:''}<div style="text-align:center">${this.orientationUrl?`<img id="batch-orientation-preview" src="${esc(this.orientationUrl)}" alt="Comprobante para revisar la orientación del texto" style="display:block;max-width:100%;max-height:42vh;width:auto;height:auto;margin:auto">`:'<p role="status">Preparando vista previa…</p>'}</div><div class="batch-tools" style="justify-content:center;margin-top:20px">${[90,180,270].includes(this.suggestedRotation)?`<button class="btn" data-action="batch-orientation-suggested" ${this.busy?'disabled':''}>Ver giro sugerido</button>`:''}<button class="btn" data-action="batch-turn-left" ${this.busy?'disabled':''}>↶ Girar izquierda</button><button class="btn" data-action="batch-turn-right" ${this.busy?'disabled':''}>↷ Girar derecha</button></div></div><div class="modal-footer" style="flex-wrap:wrap">${this.orientationVerified?'<button class="btn" data-action="batch-orientation-cancel">Volver</button>':''}<button class="btn ${this.orientationDraft===0?'btn-primary':''}" data-action="batch-orientation-keep" ${previewReady?'':'disabled'}>Mantener original y leer</button>${this.orientationDraft!==0?`<button class="btn btn-primary" data-action="batch-orientation-confirm" ${previewReady?'':'disabled'}>Así se lee correctamente</button>`:''}</div></section></div>`);
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
      if(!this.active)return;if(this.orientationEditing){this.renderOrientation();return;}if(this.gridEditing){this.renderGrid();return;}if(this.editing!==undefined){this.renderCrop();return;}
      const {esc,money,date}=this.h,working=this.busy,locked=working||this.parts.some(p=>p.saved),top=$('.receipt-batch .modal-body')?.scrollTop||0;
      const show=this.h.shows().find(s=>s.id===this.shared.showId);
      this.h.open(`<div class="overlay modal-overlay"><section class="modal receipt-batch" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">${this.layout?.count>1?'Varios comprobantes de un show':'Analizando comprobantes'}</h2><p>${this.layout?.count>1?'Un movimiento por recibo, con el mismo show y empresario.':'Detectamos cuántos recibos hay y buscamos sus abonos.'}</p></div><button class="icon-close" data-action="batch-close" aria-label="Cerrar grupo" ${this.phase==='saving'?'disabled':''}>×</button></div><div class="modal-body">
        ${this.error?`<div class="error-banner" role="alert">${esc(this.error)}${this.h.single&&!(this.layout?.count>1)?'<p><button class="btn" data-action="batch-manual">Buscar abono manualmente</button></p>':''}${this.detectionFailed&&this.image&&!this.parts.some(p=>p.saved)?`<p><button class="btn" data-action="batch-detect" ${working?'disabled':''}>Reintentar separación</button></p>`:''}</div>`:''}
        ${this.url?`<details class="batch-original" ${this.needsReview?'open':''}><summary>Revisar separación · ${this.parts.length} recortes${this.layout?` · Conteo: ${this.layout.count}`:''}</summary><div class="batch-map" style="--image-ratio:${this.image.width/this.image.height}"><img src="${esc(this.url)}" alt="Foto completa con los límites de cada comprobante">${this.parts.map(p=>`<button class="batch-map-box" data-action="batch-crop" data-index="${p.index}" style="left:${p.bounds.x/10}%;top:${p.bounds.y/10}%;width:${p.bounds.width/10}%;height:${p.bounds.height/10}%" aria-label="Ajustar comprobante ${p.index+1}" ${working||p.saved?'disabled':''}><span>${p.index+1}</span></button>`).join('')}</div></details>`:''}
        ${['preparing','counting','orienting','detecting'].includes(this.phase)?`<div class="loading-state" role="status"><span class="spinner"></span>${this.phase==='preparing'?'Preparando imagen…':this.phase==='counting'?'Contando los recibos…':this.phase==='orienting'?'Comprobando la orientación del texto…':'Delimitando y verificando los recortes completos…'}</div>`:`
        ${this.needsReview?`<div class="notice warning" role="alert">${this.geometryWarnings.map(esc).join('<br>')||'Revisa la separación antes de leer. Cada cuadro debe incluir un recibo completo.'}<br><button class="btn" data-action="batch-confirm-crops" ${working||!this.parts.length?'disabled':''}>Ya revisé: un recibo completo por recorte</button></div>`:''}
        <div class="notice">Revisa que haya un recorte por comprobante y que todos estén incluidos. Puedes ajustar, quitar o agregar recortes antes de leerlos.</div>
        <div class="batch-tools"><button class="btn" data-action="batch-orientation" ${working||!this.image||this.parts.some(p=>p.saved)?'disabled':''}>Revisar orientación</button><button class="btn" data-action="batch-add" ${working||!this.image||this.parts.length>=limit?'disabled':''}>+ Agregar recorte</button><button class="btn" data-action="batch-grid" ${working||!this.image||this.parts.some(p=>p.saved)?'disabled':''}>Separar por filas y columnas</button><button class="btn btn-primary" data-action="batch-read" ${working||!this.orientationVerified||this.needsReview||!this.parts.some(p=>!p.saved&&!p.read)?'disabled':''}>${this.parts.length&&this.parts.every(p=>p.read||p.saved)?'Lectura completada':'Leer comprobantes pendientes'}</button>${this.phase==='reading'?'<button class="btn" data-action="batch-stop">Detener lectura</button>':''}</div>
        <section class="batch-shared"><h3>Datos comunes del grupo</h3><div class="form-grid"><div class="form-field full"><label for="batch-show">Show y fecha del show</label><select id="batch-show" data-common="showId" ${locked?'disabled':''}><option value="">Selecciona el show</option>${[...this.h.shows()].sort((a,b)=>b.date.localeCompare(a.date)).map(s=>`<option value="${esc(s.id)}" ${this.shared.showId===s.id?'selected':''}>${esc(date(s.date))} · ${esc(s.name)}</option>`).join('')}<option value="__new" ${this.shared.showId==='__new'?'selected':''}>+ Agregar show histórico</option></select></div><div class="form-field full"><label for="batch-entrepreneur">Empresario</label><input id="batch-entrepreneur" class="input" data-common="entrepreneur" value="${esc(this.shared.entrepreneur)}" maxlength="300" ${locked?'disabled':''}></div>${this.shared.showId==='__new'?`<div class="form-field full"><label for="batch-name">Nombre del show histórico</label><input id="batch-name" class="input" data-common="name" value="${esc(this.shared.name)}" maxlength="200" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-date">Fecha del show</label><input type="date" id="batch-date" data-common="date" value="${esc(this.shared.date)}" ${locked?'disabled':''}></div><div class="form-field"><label for="batch-city">Ciudad</label><input class="input" id="batch-city" data-common="city" value="${esc(this.shared.city)}" maxlength="100" ${locked?'disabled':''}></div>`:''}</div><p class="small-note">${show?`Fecha del show: ${esc(date(show.date))}. `:''}Cada recibo conserva su propia fecha bancaria. Los pagos siguen siendo movimientos separados.</p></section>
        <div class="batch-cards">${this.parts.map(p=>`<article class="batch-card" id="batch-part-${p.index}"><div class="batch-preview">${p.url?`<a href="${esc(p.url)}" target="_blank" rel="noopener"><img src="${esc(p.url)}" alt="Recorte del comprobante ${p.index+1}"></a>`:''}<strong>Comprobante ${p.index+1}</strong><div class="batch-tools"><button class="link-button" data-action="batch-crop" data-index="${p.index}" ${working||p.saved?'disabled':''}>Ajustar recorte</button><button class="link-button" data-action="batch-remove" data-index="${p.index}" ${working||p.saved?'disabled':''}>Quitar</button></div></div><div class="batch-fields">${p.saved?`<div class="notice"><strong>Guardado e identificado</strong>${p.supportUrl?`<p><a href="${esc(p.supportUrl)}" target="_blank" rel="noopener">Consultar soporte PDF</a></p>`:''}</div>`:`
          ${this.readingIndex===p.index?'<div class="loading-state" role="status"><span class="spinner"></span>Leyendo y comprobando este recibo…</div>':''}
          ${p.error?`<div class="error-banner" role="alert">${esc(p.error)}</div>`:''}${p.warnings.length?`<div class="notice warning">${p.warnings.map(esc).join('<br>')}</div>`:''}
          <div class="form-grid"><div class="form-field"><label for="batch-amount-${p.index}">Valor (COP)</label><input class="input" id="batch-amount-${p.index}" data-part="${p.index}" data-key="amount" inputmode="decimal" value="${esc(p.amount)}" ${working?'disabled':''}></div><div class="form-field"><label for="batch-bank-date-${p.index}">Fecha bancaria</label><input class="input" type="date" id="batch-bank-date-${p.index}" data-part="${p.index}" data-key="date" value="${esc(p.date)}" ${working?'disabled':''}>${p.date?`<small>${esc(date(p.date))}</small>`:''}</div></div>
          <div class="batch-tools"><button class="btn btn-small" data-action="batch-search" data-index="${p.index}" ${working?'disabled':''}>${p.read?'Actualizar coincidencias':'Buscar coincidencias'}</button><button class="link-button" data-action="batch-reread" data-index="${p.index}" ${working||this.needsReview?'disabled':''}>${p.read?'Volver a leer':'Leer este recibo'}</button></div>
          <label for="batch-payment-${p.index}">Movimiento pendiente</label><select id="batch-payment-${p.index}" data-part="${p.index}" data-key="paymentId" ${working?'disabled':''}>${this.options(p)}</select><p class="small-note" id="batch-match-note-${p.index}">${p.paymentId?'Abono seleccionado. Quedará identificado al guardar.':p.matches.length?`${p.matches.length} coincidencias; elige el abono correcto.`:p.read?'No hay coincidencias. Revisa el valor y la fecha.':'Las coincidencias aparecerán al terminar la lectura.'}</p>`}</div></article>`).join('')}</div>`}
        </div><div class="modal-footer batch-footer"><span id="batch-summary" role="status">${esc(this.phase==='saving'?'Guardando soportes e identificación…':this.summary())}</span><button class="btn btn-primary" data-action="batch-save" id="batch-save" ${working||!this.orientationVerified||this.needsReview||!this.selected().length?'disabled':''}>Guardar e identificar seleccionados</button></div></section></div>`);
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
      if(action==='batch-turn-left'||action==='batch-turn-right'||action==='batch-orientation-suggested'){
        if(!this.orientationEditing)return;if(action==='batch-orientation-suggested'){if(![90,180,270].includes(this.suggestedRotation))return;this.orientationDraft=this.suggestedRotation;}else this.orientationDraft=(this.orientationDraft+(action==='batch-turn-left'?270:90))%360;this.setBusy(true);this.render();try{await this.refreshOrientationPreview();}catch(error){if(this.active)this.error=error.message;}finally{if(this.active){this.setBusy(false);this.render();}}return;
      }
      if(action==='batch-orientation-cancel'&&this.orientationVerified){this.orientationEditing=false;++this.orientationUpdate;if(this.orientationUrl)URL.revokeObjectURL(this.orientationUrl);this.orientationUrl=null;this.render();return;}
      if(action==='batch-orientation'&&this.image&&!this.parts.some(p=>p.saved)){this.orientationManual=true;return this.beginOrientationReview(this.rotation);}
      if(action==='batch-orientation-keep'&&this.orientationEditing){
        this.orientationDraft=0;this.setBusy(true);this.render();
        try{await this.refreshOrientationPreview();}catch(error){if(this.active)this.error=error.message;}
        finally{if(this.active){this.setBusy(false);this.render();}}
        if(this.active&&this.orientationPreviewRotation===0)return this.action('batch-orientation-confirm');return;
      }
      if(action==='batch-orientation-confirm'&&this.orientationEditing){
        if(!this.orientationUrl||this.orientationPreviewRotation!==this.orientationDraft)return;
        if(this.parts.some(p=>p.read||p.paymentId)&&!confirm('Se volverán a separar y leer los comprobantes. Las selecciones sin guardar se retirarán. ¿Continuar?'))return;
        this.manualRotation=this.orientationDraft;this.setOrientation(this.manualRotation);if(this.layout)this.layout.userConfirmedRotation=this.manualRotation;this.orientationVerified=true;this.orientationEditing=false;++this.orientationUpdate;
        if(this.orientationUrl)URL.revokeObjectURL(this.orientationUrl);this.orientationUrl=null;
        for(const part of this.parts)if(part.url)URL.revokeObjectURL(part.url);this.parts=[];this.operation=null;this.needsReview=false;this.geometryWarnings=[];this.error='';this.setBusy(true);this.render();
        try{await this.detectRegions();}catch(error){if(this.active){this.error=error.message;this.needsReview=true;this.detectionFailed=true;}}
        finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}return;
      }
      if(action==='batch-manual'&&this.h.single&&!(this.layout?.count>1))return this.h.single(this.source,true);
      if(action==='batch-detect'&&this.image&&!this.parts.some(p=>p.saved)){
        if(this.parts.some(p=>p.read||p.paymentId)&&!confirm('Reintentar retirará las lecturas y selecciones sin guardar si consigue nuevos recortes. ¿Continuar?'))return;
        this.setBusy(true);this.error='';this.render();
        try{await this.detectRegions();}catch(error){if(this.active){this.error=error.message;this.needsReview=true;this.detectionFailed=true;}}
        finally{if(this.active){this.phase='review';this.setBusy(false);this.render();}}return;
      }
      if(action==='batch-confirm-crops'){
        const overlap=this.parts.some((p,i)=>this.parts.slice(i+1).some(q=>{const a=p.bounds,b=q.bounds,area=Math.max(0,Math.min(a.x+a.width,b.x+b.width)-Math.max(a.x,b.x))*Math.max(0,Math.min(a.y+a.height,b.y+b.height)-Math.max(a.y,b.y));return area>.8*Math.min(a.width*a.height,b.width*b.height);}));
        if(overlap){this.error='Hay recortes repetidos o superpuestos. Ajústalos antes de confirmar.';this.render();return;}
        this.needsReview=false;this.detectionFailed=false;this.geometryWarnings=[];this.error='';this.render();return this.readParts(this.parts.filter(p=>!p.saved&&!p.read));
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
      if(!parts.length||this.needsReview||!this.orientationVerified)return;this.setBusy(true);this.phase='reading';this.stopRequested=false;this.error='';
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
      const parts=this.selected();if(!parts.length||this.needsReview||!this.orientationVerified)return;
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
