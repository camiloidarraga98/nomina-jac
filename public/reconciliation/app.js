/* JAC Music: payment reconciliation workspace. Source fields remain read-only. */
(() => {
  'use strict';
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => [...root.querySelectorAll(s)];
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = n => new Intl.NumberFormat('es-CO', {style:'currency',currency:'COP',maximumFractionDigits:Number(n)%1 ? 2 : 0}).format(Number(n)||0);
  const date = s => { if(!s) return 'Sin fecha'; const d=String(s).slice(0,10).split('-'); return d.length===3 ? `${d[2]} ${['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'][Number(d[1])-1]} ${d[0]}` : s; };
  const norm = s => String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const ndate = value => window.FileTools?.normalizeDate(value) || '';
  const namount = value => window.FileTools?.normalizeAmount(value) ?? null;
  const state = {payments:[],shows:[],imports:[],view:'payments',filter:'all',dateOrder:'asc',query:'',amount:'',from:'',to:'',showId:'',page:1,loaded:false,error:'',selected:null,overlay:null,busy:false,dirty:false};
  let importData = null;
  let receiptScan = null;
  let receiptBatch = null;
  let clipboardRead = 0, clipboardBusy = false;
  let stateRead = 0, accessEpoch = 0;
  const attachmentList = p => p.attachments || [];
  const identified = p => p.accountingIdentified===true||p.status==='identified';
  const ready = p => p.accountingIdentified===true||(p.status==='identified' && attachmentList(p).length>0);
  const showOf = p => state.shows.find(s=>s.id===p.showId);
  const originalShow = p => Object.entries(p.original||{}).find(([key])=>norm(key).startsWith('lugar del show'))?.[1] || '';
  const originalValueKnown = value => {const v=norm(value);return !!v&&!/^(tercero )?sin identificar$|^sin (datos|factura|recibo|tercero)$|^por (identificar|confirmar|facturar)$|^pendiente$|^n\/?a$|^-+$/.test(v);};
  const statusLabel = p => p.accountingIdentified===true?'Identificado y facturado':ready(p) ? 'Listo para contabilidad' : p.status==='identified' ? 'Identificado' : p.status==='review' ? 'En revisión' : 'Pendiente';
  const statusClass = p => ready(p)?'ready':p.status==='identified'?'identified':p.status==='review'?'review':'pending';
  const badge = p => `<span class="badge badge-${statusClass(p)}">${statusLabel(p)}</span>`;
  function clearPrivateState(status){++accessEpoch;++stateRead;state.payments=[];state.shows=[];state.imports=[];state.loaded=false;state.error=status===401?'Tu sesión ha vencido. Ingresa de nuevo en JAC.':'Tu cuenta ya no tiene acceso a la conciliación del CRM.';state.dirty=false;state.busy=false;closeOverlay(true);render();}
  window.addEventListener('jac-reconciliation-access-denied',event=>clearPrivateState(event.detail?.status||403));
  function notifyParent(){if(window.parent!==window)window.parent.postMessage({type:'jac-reconciliation-state',dirty:state.dirty,busy:state.busy},location.origin);}
  for(const key of ['dirty','busy']){let value=state[key];Object.defineProperty(state,key,{get:()=>value,set:next=>{value=next;notifyParent();},enumerable:true});}
  function toast(message, error=false) { const el=document.createElement('div');el.className=`toast${error?' error':''}`;el.textContent=message;$('#toast-root').replaceChildren(el);setTimeout(()=>el.remove(),error?10000:5000); }
  async function api(url, options={}) {
    const epoch=accessEpoch;
    const headers = {...(options.body instanceof FormData ? {} : {'Content-Type':'application/json'}),...(options.headers||{})};
    let response;try {response=await fetch(url,{...options,headers,credentials:'same-origin'});} catch {throw new Error('No se pudo conectar. Revisa tu conexión y vuelve a intentar. No se confirmó el guardado. Conserva el formulario y vuelve a intentar.');}
    let data;try {data=await response.json();} catch {data={};}
    if(epoch!==accessEpoch)throw new Error(state.error||'Tu acceso cambió. Vuelve a ingresar.');
    if(!response.ok) {if([401,403].includes(response.status)){clearPrivateState(response.status);throw new Error(state.error);}if(response.status===409)throw new Error(data.error||'Este abono cambió en otra pestaña. Cierra el detalle, actualiza y revisa los datos antes de guardar.');const error=new Error(data.error||data.message||(response.status===413?'La imagen y sus datos superan el tamaño permitido para esta solicitud. Conservamos la foto para que puedas reintentar la separación o ajustar los recortes.':`No se pudo completar la operación (${response.status}).`));error.status=response.status;throw error;}
    return data;
  }
  async function reload({keepDraft=false}={}) {
    const read = ++stateRead;
    let timeout;
    try {
      if(!window.FileTools || !window.JSZip || !window.JacReceiptBatch)throw new Error('No se cargaron todos los componentes de la herramienta. Vuelve a abrir la versión corregida.');
      const data=await Promise.race([
        api('/api/reconciliation/state'),
        new Promise((_,reject)=>{timeout=setTimeout(()=>reject(new Error('La carga está tardando demasiado. Vuelve a intentar; tus datos guardados se conservan.')),20000);})
      ]);
      if(!data || !Array.isArray(data.payments) || !Array.isArray(data.shows) || !Array.isArray(data.imports))throw new Error('No se recibió la relación de abonos completa. Vuelve a intentar.');
      if(read!==stateRead)return;
      state.payments=data.payments;state.shows=data.shows;state.imports=data.imports;
      state.loaded=true;state.error='';$('#connection').textContent='Guardado en JAC';render();
      if(state.selected && state.overlay==='editor') {
        const p=state.payments.find(p=>p.id===state.selected);if(p){if(keepDraft){renderAttachments(p);const status=$('#editor-status');if(status)status.innerHTML=editorStatus(p);}else renderEditor(p);}
      }
    } catch(error) {if(read!==stateRead)return;state.error=error.message;$('#connection').textContent='Carga pendiente';render();throw error;}
    finally {clearTimeout(timeout);}
  }
  function ordered(rows) {
    const direction=state.dateOrder==='asc'?1:-1;
    return [...rows].sort((a,b)=>direction*String(a.date).localeCompare(String(b.date))||String(a.id).localeCompare(String(b.id)));
  }
  function filtered() {
    const q=norm(state.query), av=state.amount.trim()?namount(state.amount):null;
    return ordered(state.payments.filter(p=> {
      if(state.filter==='pending'&&identified(p)) return false;
      if(state.filter==='identified'&&!identified(p)) return false;
      if(state.filter==='ready'&&!ready(p)) return false;
      if(state.filter==='missing'&&(attachmentList(p).length||p.accountingIdentified)) return false;
      if(state.showId&&p.showId!==state.showId) return false;
      if(state.from&&p.date<state.from) return false;if(state.to&&p.date>state.to) return false;
      if(state.amount.trim()&&(av===null||Math.round(p.amount*100)!==Math.round(av*100)))return false;
      if(q){const s=showOf(p);if(!norm([p.id,p.description,p.reference,p.thirdParty,p.receipt,p.invoice,p.entrepreneur,p.payer,p.nit,p.businessName,p.notes,s?.name,s?.city,s?.entrepreneur,...Object.values(p.original||{})].join(' ')).includes(q))return false;}
      return true;
    }));
  }
  const sum = rows => rows.reduce((a,p)=>a+Math.round(Number(p.amount||0)*100),0)/100;
  function workflow(){return `<div class="workflow-strip"><div class="workflow-step"><span class="step-no">1</span><div><strong>Lee el comprobante de WhatsApp</strong><p>Sube una imagen o PDF para buscar el abono por valor y fecha.</p></div></div><div class="workflow-step"><span class="step-no">2</span><div><strong>Relaciona y adjunta</strong><p>Asigna el show, confirma el empresario y guarda el soporte del pago.</p></div></div><div class="workflow-step"><span class="step-no">3</span><div><strong>Entrega a contabilidad</strong><p>Descarga la relación con los comprobantes organizados por abono.</p></div></div></div>`;}
  function render(){
    $$('.nav-button').forEach(el=>el.classList.toggle('active',el.dataset.view===state.view));$('#nav-count').textContent=state.payments.length;
    if(!state.loaded && !state.error)return;
    const error=state.error?`<div class="error-banner" role="alert">${esc(state.error)} <button class="link-button" data-action="retry">Volver a intentar</button>${state.error.includes('sesión')?'<a href="/acceso?returnTo=%2Fcrm%3Fseccion%3Dconciliacion" target="_top">Ingresar</a>':''}</div>`:'';
    if(state.view==='shows'){renderShows(error);return;}
    const pending=state.payments.filter(p=>!identified(p)),identifiedRows=state.payments.filter(identified),complete=state.payments.filter(ready),percent=state.payments.length?Math.round(identifiedRows.length/state.payments.length*100):0;
    $('#main').innerHTML=`${error}<div class="page-head"><div><div class="eyebrow">EL ORDEN DETRÁS DE CADA SHOW</div><h1>Conciliación de abonos</h1><p class="page-sub">Relaciona las consignaciones de contabilidad con los shows y comprobantes.</p></div><div class="head-actions"><button class="btn btn-primary" data-action="scan-receipt" ${!state.payments.length?'disabled':''}><span class="btn-icon">⌕</span>Leer comprobante</button><button class="btn" data-action="export" ${!state.payments.length?'disabled':''}><span class="btn-icon">↓</span>Exportar contabilidad</button><button class="btn" data-action="import"><span class="btn-icon">+</span>Importar archivo</button></div></div>
      <div class="stat-grid"><div class="stat-card"><div class="stat-top">Total de abonos<span class="stat-symbol">↙</span></div><div class="stat-value">${money(sum(state.payments))}</div><div class="stat-bottom">${state.payments.length} consignaciones importadas</div></div><div class="stat-card"><div class="stat-top">Por identificar<span class="stat-symbol">◷</span></div><div class="stat-value">${money(sum(pending))}</div><div class="stat-bottom">${pending.length} abonos pendientes o en revisión</div></div><div class="stat-card"><div class="stat-top">Identificados<span class="stat-symbol">✓</span></div><div class="stat-value">${money(sum(identifiedRows))}</div><div class="stat-bottom">${identifiedRows.length} abonos conciliados o facturados en origen</div></div><div class="stat-card highlight"><div class="stat-top">Listos para contabilidad<span class="stat-symbol">▤</span></div><div class="stat-value">${complete.length}<span style="font-size:13px;font-weight:500;color:#60734b"> / ${state.payments.length}</span></div><div class="stat-bottom">Con soporte o factura y tercero en origen</div><div class="progress-track"><div class="progress-fill" style="width:${state.payments.length?complete.length/state.payments.length*100:0}%"></div></div></div></div>
      ${state.showId?`<div class="show-focus"><span>Abonos del show: <strong>${esc(state.shows.find(s=>s.id===state.showId)?.name||'Show')}</strong></span><button class="link-button" data-action="clear-show">Ver todos los abonos ×</button></div>`:''}
      <section class="table-card" aria-label="Listado de abonos"><div class="section-top"><div><h2>Tu relación de consignaciones</h2><p>${state.payments.length?`${percent}% de los abonos identificados. Continúa donde quedaste.`:'Tu archivo de contabilidad es el punto de partida.'}</p></div><span class="pill-muted">COP · Pesos colombianos</span></div>
      <div class="tabs" role="tablist" aria-label="Estado de conciliación">${[['all','Todos',state.payments.length],['pending','Por identificar',pending.length],['identified','Identificados',identifiedRows.length],['ready','Listos',complete.length],['missing','Sin soporte',state.payments.filter(p=>!attachmentList(p).length&&!p.accountingIdentified).length]].map(([key,label,count])=>`<button class="tab ${state.filter===key?'active':''}" role="tab" aria-selected="${state.filter===key}" data-action="filter" data-filter="${key}">${label}<small>${count}</small></button>`).join('')}</div>
      <div class="filters"><div class="search-box"><span class="search-icon">⌕</span><input class="input" id="search" placeholder="Buscar empresario, show, referencia…" aria-label="Buscar abonos" value="${esc(state.query)}"></div><input class="input amount-filter" id="amount-filter" inputmode="decimal" placeholder="Valor exacto ($)" aria-label="Valor exacto en pesos" value="${esc(state.amount)}"><div class="field-inline"><label for="date-from">Desde</label><input type="date" class="input date-filter" id="date-from" aria-label="Fecha bancaria desde" title="Fecha bancaria desde" value="${esc(state.from)}"></div><div class="field-inline"><label for="date-to">Hasta</label><input type="date" class="input date-filter" id="date-to" aria-label="Fecha bancaria hasta" title="Fecha bancaria hasta" value="${esc(state.to)}"></div><div class="sort-field"><label for="date-order">Ordenar por fecha</label><select id="date-order" aria-label="Ordenar por fecha bancaria"><option value="asc" ${state.dateOrder==='asc'?'selected':''}>Ascendente · Más antiguos</option><option value="desc" ${state.dateOrder==='desc'?'selected':''}>Descendente · Más recientes</option></select></div><button class="link-button" data-action="clear-filters">Limpiar</button></div><div id="payments-table"></div></section>${workflow()}`;
    renderTable();
  }
  function renderTable(){
    const container=$('#payments-table');if(!container)return;
    if(!state.payments.length){container.innerHTML=`<div class="empty-state"><div class="empty-icon">▤</div><h3>Empecemos por tu archivo</h3><p>Importa el Excel que te envió contabilidad. Conservaremos las fechas, valores, terceros, recibos y facturas que ya tiene.</p><button class="btn btn-primary" data-action="import"><span class="btn-icon">↑</span>Cargar relación de consignaciones</button><p class="small-note">Archivos .xlsx o .csv · Puedes revisar las columnas antes de importar</p></div>`;return;}
    const rows=filtered(),pages=Math.max(1,Math.ceil(rows.length/40));state.page=Math.min(state.page,pages);
    const pageRows=rows.slice((state.page-1)*40,state.page*40);
    container.innerHTML=`<div class="table-scroll"><table><thead><tr><th aria-sort="${state.dateOrder==='asc'?'ascending':'descending'}">Fecha bancaria</th><th>Valor del abono</th><th>Show / empresario</th><th>Datos de origen</th><th>Estado</th><th>Soporte</th><th><span class="visually-hidden">Abrir</span></th></tr></thead><tbody>${pageRows.map(p=>{const s=showOf(p);return `<tr data-action="edit" data-id="${esc(p.id)}" tabindex="0" aria-label="Abrir abono de ${esc(money(p.amount))} del ${esc(date(p.date))}"><td class="date-cell">${esc(date(p.date))}<div class="secondary">Fila ${esc(p.sourceRow||'—')}</div></td><td class="amount-cell">${money(p.amount)}<div class="secondary">${esc(p.reference||'Sin referencia')}</div></td><td class="show-cell">${s?esc(s.name):'<span class="unassigned">Sin show asignado</span>'}<div class="secondary">${esc(p.entrepreneur||'Empresario por identificar')}</div>${originalShow(p)?`<div class="secondary" title="Dato original, pendiente de confirmar">Origen: ${esc(originalShow(p))}</div>`:''}</td><td>${esc(p.thirdParty||'Tercero sin identificar')}<div class="secondary">${esc([p.receipt?`RC ${p.receipt}`:'',p.invoice?`Fac. ${p.invoice}`:''].filter(Boolean).join(' · ')||p.description||'Sin datos contables')}</div></td><td>${badge(p)}</td><td><span class="support-label">${attachmentList(p).length?`↳ ${attachmentList(p).length} archivo${attachmentList(p).length===1?'':'s'}`:p.accountingIdentified?'Factura en contabilidad':'Sin soporte'}</span></td><td class="row-arrow">↗</td></tr>`;}).join('')}</tbody></table>${!pageRows.length?'<div class="empty-filter">No hay abonos con estos filtros. Prueba otro valor o amplía las fechas.</div>':''}</div><div class="table-bottom"><span>${rows.length} abonos · Total <strong>${money(sum(rows))}</strong></span><div class="pagination"><span>${rows.length?`${(state.page-1)*40+1}–${Math.min(state.page*40,rows.length)} de ${rows.length}`:'0 resultados'}</span><button class="page-btn" data-action="page" data-offset="-1" aria-label="Página anterior" ${state.page===1?'disabled':''}>‹</button><button class="page-btn" data-action="page" data-offset="1" aria-label="Página siguiente" ${state.page===pages?'disabled':''}>›</button></div></div>`;
  }
  function renderShows(error=''){
    $('#main').innerHTML=`${error}<div class="page-head"><div><div class="eyebrow">CADA FECHA TIENE SU HISTORIA</div><h1>Shows y sus abonos</h1><p class="page-sub">Reúne todas las consignaciones de un mismo negocio.</p></div><button class="btn btn-primary" data-action="new-show"><span class="btn-icon">+</span>Agregar referencia</button></div>${state.shows.length?`<div class="show-grid">${[...state.shows].sort((a,b)=>String(b.date).localeCompare(String(a.date))).map(s=>{const payments=state.payments.filter(p=>p.showId===s.id);return `<article class="show-card" tabindex="0" data-action="show-payments" data-id="${esc(s.id)}"><div class="show-date">${s.source==='crm'?'CRM · ':'Histórico · '}${esc(date(s.date))}${s.city?` · ${esc(s.city)}`:''}</div><h3>${esc(s.name)}</h3><p>${esc(s.entrepreneur||'Empresario por definir')}</p><div class="show-bottom"><div><small>Total de abonos relacionados</small><div class="show-total">${money(sum(payments))}</div></div><small>${payments.length} abonos ↗</small></div></article>`;}).join('')}</div>`:`<section class="table-card"><div class="empty-state"><div class="empty-icon">▦</div><h3>Un lugar para cada show</h3><p>Crea la fecha con el nombre del empresario. Después podrás relacionar todos los abonos de ese negocio.</p><button class="btn btn-primary" data-action="new-show">Agregar referencia histórica</button></div></section>`}<div class="notice" style="margin-top:22px">La fecha del show es diferente a la fecha bancaria del abono. El total corresponde únicamente a los pagos relacionados; no representa el valor del contrato ni su saldo.</div>`;
  }
  function openOverlay(html,type){state.overlay=type;$('#overlay-root').innerHTML=html;document.body.style.overflow='hidden';requestAnimationFrame(()=>$(type==='receipt'&&!receiptScan?'#receipt-paste-button':'#overlay-root .icon-close')?.focus());}
  function closeOverlay(force=false){if(state.busy&&!force)return;if(state.dirty&&!force&&!confirm('Tienes cambios sin guardar. ¿Quieres cerrar sin guardarlos?'))return;discardReceipt();state.selected=null;state.overlay=null;state.dirty=false;$('#overlay-root').innerHTML='';document.body.style.overflow='';}

  function discardReceipt(){++clipboardRead;clipboardBusy=false;const scan=receiptScan;receiptScan=null;scan?.controller?.abort();if(scan?.url)URL.revokeObjectURL(scan.url);const batch=receiptBatch;receiptBatch=null;batch?.dispose();}
  function startReceiptBatch(file,{forceGroup=false}={}){
    if(!['image/jpeg','image/png','image/webp'].includes(file.type))return toast('Para varios comprobantes juntos, elige una imagen JPG, PNG o WebP.',true);
    if(file.size>10*1024*1024)return toast('La imagen supera el máximo de 10 MB.',true);
    if(receiptBatch&&state.dirty&&!confirm('Hay comprobantes sin guardar. ¿Quieres sustituir la imagen del grupo?'))return;
    discardReceipt();
    const batch=new window.JacReceiptBatch({esc,money,date,amount:namount,api,
      open:html=>{if(receiptBatch===batch)openOverlay(html,'receipt');},
      busy:value=>{if(receiptBatch===batch)state.busy=value;},dirty:value=>{if(receiptBatch===batch)state.dirty=value;},isDirty:()=>state.dirty,
      forceGroup,shows:()=>state.shows,reload:()=>reload(),single:(file,manual=false,readingImage)=>{if(receiptBatch!==batch)return;state.busy=false;return readReceiptFile(file,{single:true,manual,readingImage});},close:()=>{if(receiptBatch===batch){state.busy=false;state.dirty=false;closeOverlay(true);}}
    });receiptBatch=batch;batch.start(file);
  }
  function receiptClipboard(){return `<div class="receipt-clipboard"><button type="button" class="btn" id="receipt-paste-button" data-action="paste-scan" aria-describedby="receipt-paste-hint">Pegar del portapapeles</button><p id="receipt-paste-hint" class="small-note">Copia la imagen del comprobante y pulsa <kbd>⌘ V</kbd> en Mac o <kbd>Ctrl V</kbd> en Windows.</p><p id="receipt-paste-message" class="small-note" role="status"></p><textarea id="receipt-paste-target" class="input" rows="2" hidden aria-label="Pegar imagen del comprobante" placeholder="Pega aquí con ⌘V, Ctrl+V o el menú Pegar" autocomplete="off"></textarea></div>`;}
  function receiptPasteHelp(message){
    const note=$('#receipt-paste-message'),target=$('#receipt-paste-target');
    if(note)note.textContent=message;
    if(target){target.hidden=false;target.value='';target.focus();}
  }
  async function pasteReceipt(){
    if(state.overlay!=='receipt'||state.busy||clipboardBusy)return;
    if(!navigator.clipboard?.read){receiptPasteHelp('Haz clic en el campo de abajo y usa ⌘V, Ctrl+V o el menú Pegar para pegar la imagen.');return;}
    const dialog=$('.receipt-modal'),epoch=accessEpoch,attempt=++clipboardRead,button=$('#receipt-paste-button');
    const current=()=>attempt===clipboardRead&&epoch===accessEpoch&&state.overlay==='receipt'&&dialog===$('.receipt-modal')&&!state.busy;
    clipboardBusy=true;if(button){button.disabled=true;button.textContent='Leyendo portapapeles…';}
    try{
      // Read only after this explicit click, never on opening or focusing the page.
      const items=await navigator.clipboard.read();if(!current())return;
      const formats=['application/pdf','image/png','image/jpeg','image/webp'];
      const documents=items.map(item=>({item,type:formats.find(type=>item.types.includes(type))})).filter(item=>item.type);
      if(documents.length!==1){receiptPasteHelp(documents.length?'Pega un solo comprobante a la vez.':'No hay una imagen o PDF compatible. Copia la imagen del comprobante; si tienes un enlace o un PDF, también puedes seleccionar el archivo.');return;}
      const {item,type}=documents[0],blob=await item.getType(type);if(!current())return;
      const extension={'application/pdf':'pdf','image/png':'png','image/jpeg':'jpg','image/webp':'webp'}[type];
      readReceiptFile(new File([blob],`comprobante-pegado.${extension}`,{type}));
    }catch{if(current())receiptPasteHelp('El navegador no permitió leer el portapapeles con el botón. Pega la imagen en el campo de abajo con ⌘V, Ctrl+V o el menú Pegar.');}
    finally{if(attempt===clipboardRead){clipboardBusy=false;if(button?.isConnected){button.disabled=false;button.textContent='Pegar del portapapeles';}}}
  }
  function receiptPreview(scan){
    if(!scan?.url)return '';
    return scan.file.type==='application/pdf'?`<div class="receipt-pdf"><span aria-hidden="true">▤</span><strong>Comprobante PDF</strong><a class="btn" href="${esc(scan.url)}" target="_blank" rel="noopener">Consultar PDF</a></div>`:`<a href="${esc(scan.url)}" target="_blank" rel="noopener" aria-label="Ver comprobante completo"><img class="receipt-image" src="${esc(scan.url)}" alt="Comprobante seleccionado para lectura"></a>`;
  }
  function renderReceipt(){
    const scan=receiptScan,loading=!!scan?.loading;
    const reading=scan?.result?.reading;
    openOverlay(`<div class="overlay modal-overlay"><section class="modal receipt-modal" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><div class="modal-header"><div><h2 id="receipt-title">Leer comprobante</h2><p>Sube el soporte para encontrar su abono por valor y fecha.</p></div><button class="icon-close" data-action="${loading?'cancel-scan':'close'}" aria-label="${loading?'Cancelar lectura':'Cerrar lectura'}">×</button></div><div class="modal-body"><input id="scan-file" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" hidden>
      ${!scan?`<button class="drop-zone receipt-upload" data-action="choose-scan"><strong>↑ Seleccionar imagen o PDF</strong><p>O arrastra el archivo aquí.<br>Detectamos si hay uno o varios comprobantes y buscamos sus abonos automáticamente.<br>Hasta 20 recibos por imagen · 10 MB · PDF de hasta 5 páginas.</p></button>${receiptClipboard()}<p class="small-note">JAC usa OpenAI para leer los comprobantes que elijas. Los soportes se guardan de forma privada al confirmar su asignación.</p>`:`<div class="receipt-layout"><div class="receipt-original">${receiptPreview(scan)}<p class="small-note">${esc(scan.file.name)}</p>${!loading?`<button class="link-button" data-action="choose-scan">Elegir otro comprobante</button>${receiptClipboard()}`:''}</div><div class="receipt-details">${loading?'<div class="loading-state" role="status"><span class="spinner"></span>Leyendo y comprobando valor y fecha…</div><button class="btn" data-action="cancel-scan">Cancelar lectura</button>':`
        <div id="receipt-error" role="alert">${scan.error?`<div class="error-banner">${esc(scan.error)}</div>`:''}</div>
        ${reading?.warnings?.length?`<div class="notice warning">${reading.warnings.map(esc).join('<br>')}</div>`:''}
        ${reading?.document==='multiple_payments'&&scan.file.type!=='application/pdf'?'<button class="btn btn-primary" data-action="split-scan">Separar los comprobantes de esta imagen</button>':''}
        <form id="receipt-search" class="receipt-search"><div class="form-grid"><div class="form-field"><label for="scan-amount">Valor leído (COP)</label><input class="input" id="scan-amount" inputmode="decimal" autocomplete="off" value="${esc(scan.amount)}" placeholder="Escribe el valor">${reading?.amountText?`<small>Texto leído: ${esc(reading.amountText)}</small>`:''}</div><div class="form-field"><label for="scan-date">Fecha leída</label><input class="input" id="scan-date" type="date" value="${esc(scan.date)}">${reading?.dateText?`<small>Texto leído: ${esc(reading.dateText)}</small>`:''}</div></div><button type="submit" class="btn" ${state.busy?'disabled':''}>${state.busy?'Buscando…':scan.matchesCurrent?'Actualizar coincidencias':'Buscar coincidencias'}</button><small>Corrige los datos si hace falta. Puedes buscar solo por valor o por fecha.</small></form>
        <div id="receipt-candidates" aria-live="polite">${receiptCandidatesMarkup(scan)}</div>`}</div></div>`}
      </div></section></div>`,'receipt');
    const zone=$('.receipt-upload');
    if(zone){zone.addEventListener('dragover',e=>{e.preventDefault();zone.classList.add('dragover');});zone.addEventListener('dragleave',()=>zone.classList.remove('dragover'));zone.addEventListener('drop',e=>{e.preventDefault();if(e.dataTransfer.files.length!==1)return toast('Selecciona un comprobante a la vez.',true);readReceiptFile(e.dataTransfer.files[0]);});}
  }
  function receiptCandidatesMarkup(scan){
    if(!scan?.result||!scan.matchesCurrent)return '<p class="secondary">Busca el movimiento con los datos del comprobante.</p>';
    const matches=scan.result.matches||[];
    if(!matches.length)return '<div class="notice">No hay abonos con estos datos. Revisa el valor y la fecha, o borra uno de los campos para ampliar la búsqueda.</div>';
    return `<h3 class="receipt-match-title">${scan.result.total} coincidencia${scan.result.total===1?'':'s'} · Elige el abono</h3>${matches.map(p=>`<button class="receipt-match" data-action="select-scan-payment" data-id="${esc(p.id)}"><span><strong>${money(p.amount)}</strong><span>${esc(date(p.date))} · ${p.kind==='exact'?'Coinciden valor y fecha':p.kind==='amount'?'Mismo valor · revisa la fecha':'Misma fecha · revisa el valor'}</span><small>${esc(state.shows.find(s=>s.id===p.showId)?.name||'Sin show asignado')} · ${esc(p.entrepreneur||'Empresario por identificar')}</small>${p.status==='identified'?'<small>Ya identificado · revisa antes de añadir otro soporte</small>':''}</span><span class="receipt-use">Usar este abono →</span></button>`).join('')}${scan.result.total>matches.length?'<p class="secondary">Se muestran las primeras 100 coincidencias. Añade el valor para acotar la búsqueda.</p>':''}`;
  }
  async function readReceiptFile(file,{single=false,manual=false,readingImage=null}={}){
    if(!file||state.busy)return;
    if(!['image/jpeg','image/png','image/webp','application/pdf'].includes(file.type)||!file.size||file.size>10*1024*1024)return toast('Usa un JPG, PNG, WebP o PDF de hasta 10 MB.',true);
    if(!single&&file.type!=='application/pdf')return startReceiptBatch(file);
    discardReceipt();
    const scan=receiptScan={file,url:URL.createObjectURL(readingImage||file),controller:new AbortController(),loading:true,error:'',amount:'',date:'',result:null,matchesCurrent:false,paymentId:null,attached:false,draft:null};
    state.busy=!manual;scan.loading=!manual;state.dirty=true;renderReceipt();if(manual)return;
    try{
      const body=new FormData();body.append('file',file);if(readingImage)body.append('readingImage',readingImage);
      const result=await api('/api/reconciliation/scan',{method:'POST',body,signal:scan.controller.signal});
      if(receiptScan!==scan)return;
      if(result.reading?.document==='multiple_payments'&&file.type!=='application/pdf'){state.busy=false;startReceiptBatch(file,{forceGroup:true});return;}
      scan.result=result;scan.amount=result.reading?.amount==null?'':new Intl.NumberFormat('es-CO',{maximumFractionDigits:2}).format(result.reading.amount);scan.date=result.reading?.date||'';scan.matchesCurrent=true;scan.loading=false;
      if(result.existingPaymentId){
        await reload();if(receiptScan!==scan)return;
        const p=state.payments.find(p=>p.id===result.existingPaymentId);if(!p)throw new Error('El abono del comprobante ya no está disponible.');
        discardReceipt();renderEditor(p);toast('Este comprobante ya está guardado en este abono.');return;
      }
      if(result.autoMatchId){await selectReceiptPayment(result.autoMatchId,true);return;}
    }catch(error){if(receiptScan===scan){scan.loading=false;scan.error=error.message;}}
    finally{if(receiptScan===scan){state.busy=false;if(state.overlay==='receipt')renderReceipt();}else if(!receiptScan&&!receiptBatch)state.busy=false;}
  }
  async function searchReceiptMatches(){
    const scan=receiptScan;if(!scan||state.busy)return;
    const amount=scan.amount.trim()?namount(scan.amount):null,date=scan.date||null;
    if((scan.amount.trim()&&(!Number.isFinite(amount)||amount<=0))||(!amount&&!date)){scan.error='Escribe un valor positivo y/o una fecha.';renderReceipt();return;}
    state.busy=true;scan.error='';renderReceipt();
    try{const result=await api('/api/reconciliation/scan/matches',{method:'POST',body:JSON.stringify({amount,date}),signal:scan.controller.signal});if(receiptScan!==scan)return;scan.result={...scan.result,...result};scan.matchesCurrent=true;}
    catch(error){if(receiptScan===scan)scan.error=error.message;}
    finally{if(receiptScan===scan){state.busy=false;renderReceipt();}}
  }
  async function selectReceiptPayment(id,automatic=false){
    const scan=receiptScan;if(!scan||(!automatic&&state.busy)||!scan.matchesCurrent)return;
    const candidate=scan.result.matches.find(p=>p.id===id);if(!candidate)return;
    state.busy=true;
    try{
      await reload();if(receiptScan!==scan)return;
      const p=state.payments.find(p=>p.id===id);if(!p)throw new Error('El abono ya no está disponible. Busca de nuevo.');
      if(p.version!==candidate.version){scan.error='Este abono cambió durante la lectura. Busca de nuevo para revisar su estado actual.';scan.matchesCurrent=false;renderReceipt();return;}
      scan.paymentId=p.id;scan.automatic=automatic;renderEditor(p);
      if(scan.draft?.id===p.id){for(const [key,value]of Object.entries(scan.draft.values)){const el=$(`[name="${key}"]`,$('#payment-form'));if(el&&key!=='version')el.value=value;}}
      state.dirty=true;
    }catch(error){if(receiptScan===scan){scan.error=error.message;renderReceipt();}}
    finally{if(receiptScan===scan){state.busy=false;if(state.overlay==='receipt')renderReceipt();}}
  }
  function renderReceiptPending(p){
    $('#receipt-pending')?.remove();const scan=receiptScan;if(!scan||scan.paymentId!==p.id)return;
    const div=document.createElement('div');div.id='receipt-pending';div.className='receipt-pending';
    div.innerHTML=`<div class="receipt-pending-preview">${receiptPreview(scan)}</div><div><strong>${scan.attached?'Comprobante guardado':scan.automatic?'Encontramos este abono por valor y fecha':'Comprobante listo para relacionar'}</strong><p>${scan.attached?'Completa los datos y guarda la identificación.':'Completa el show y el empresario. Al guardar quedará identificado con su comprobante adjunto.'}</p>${!scan.attached?'<button type="button" class="link-button" data-action="review-scan">Revisar coincidencias / cambiar abono</button>':''}</div>`;
    $('#editor-status').after(div);if(!scan.attached)state.dirty=true;
  }
  function editorStatus(p){const docs=[p.thirdParty,p.receipt,p.invoice].filter(originalValueKnown).length;if(p.accountingIdentified)return `${badge(p)} <p class="small-note">Factura y tercero registrados por contabilidad. No requiere revisión. Puedes seleccionar «En revisión» si necesitas verificar este abono.</p>`;return `${badge(p)} <span class="support-label" style="margin-left:7px">${docs===3?'Tercero, recibo y factura en origen':docs?'Datos contables parciales':'Sin datos contables en origen'}</span>`;}
  function renderEditor(p){
    state.selected=p.id;state.dirty=false;
    const s=showOf(p),fromReceipt=receiptScan?.paymentId===p.id;
    openOverlay(`<div class="overlay" data-backdrop="true"><section class="drawer" role="dialog" aria-modal="true" aria-labelledby="editor-title"><div class="drawer-header"><div><div class="eyebrow">DETALLE DEL ABONO</div><h2 id="editor-title">${money(p.amount)}</h2><div class="payment-meta">${esc(date(p.date))} · ${esc(p.reference||'Sin referencia bancaria')}</div></div><button class="icon-close" data-action="close" aria-label="Cerrar detalle">×</button></div><div class="drawer-body"><div id="editor-error" role="alert"></div><div id="editor-status" style="margin-bottom:22px">${editorStatus(p)}</div>
      ${originalShow(p)?`<div class="notice" style="margin-bottom:22px"><strong>Show anotado en contabilidad</strong><br>${esc(originalShow(p))}<br><span style="font-size:10px">Confirma la fecha y el negocio antes de relacionarlo.</span></div>`:''}<form id="payment-form"><input type="hidden" name="version" value="${esc(p.version)}"><div class="form-section"><h3><span class="section-index">01</span>Relacionar con un negocio</h3><div class="form-grid"><div class="form-field full"><div class="field-label-action"><label for="p-show">Show <span>*</span></label><button type="button" class="link-button" data-action="new-show-editor">+ Agregar referencia</button></div><select id="p-show" name="showId"><option value="">Selecciona el show</option>${[...state.shows].sort((a,b)=>String(b.date).localeCompare(String(a.date))).map(s=>`<option value="${esc(s.id)}" ${p.showId===s.id?'selected':''}>${s.source==='crm'?'CRM · ':'Histórico · '}${esc(date(s.date))} · ${esc(s.name)}${s.city?` · ${esc(s.city)}`:''}</option>`).join('')}</select><small>Un mismo show puede tener varios abonos.</small></div><div class="form-field"><label for="p-entrepreneur">Empresario <span>*</span></label><input class="input" id="p-entrepreneur" name="entrepreneur" value="${esc(p.entrepreneur)}" placeholder="Con quién hiciste el negocio" maxlength="300"></div><div class="form-field"><label for="p-payer">Quién consignó</label><input class="input" id="p-payer" name="payer" value="${esc(p.payer)}" placeholder="Titular del comprobante" maxlength="300"></div>${fromReceipt?'<div class="form-field full"><label>Estado al guardar</label><strong>Identificado</strong><input type="hidden" name="status" value="identified"></div>':`<div class="form-field full"><label for="p-status">Estado de conciliación</label><select id="p-status" name="status"><option value="pending" ${!p.status||p.status==='pending'?'selected':''}>${p.accountingEvidence?'Identificado y facturado en contabilidad':'Pendiente de identificar'}</option><option value="review" ${p.status==='review'?'selected':''}>En revisión</option><option value="identified" ${p.status==='identified'?'selected':''}>Identificado</option></select></div>`}</div></div>
      <div class="form-section"><h3><span class="section-index">02</span>Comprobante de pago</h3><div class="drop-zone" id="drop-zone" tabindex="0" role="button" aria-label="Adjuntar comprobantes" data-action="attach"><strong>↑ Arrastra el comprobante o haz clic para adjuntar</strong><p>Imágenes y PDF · También puedes pegar una imagen con Ctrl/Cmd + V.<br>Máximo 20 MB por archivo.</p></div><input id="support-files" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" multiple hidden><div id="upload-progress" class="upload-progress" aria-live="polite"></div><div id="attachments" class="attachment-list"></div></div>
      <div class="form-section"><h3><span class="section-index">03</span>Datos para facturación</h3><div class="form-grid"><div class="form-field full"><label for="p-billing">¿El cliente requiere factura?</label><select id="p-billing" name="billingStatus"><option value="unknown" ${!p.billingStatus||p.billingStatus==='unknown'?'selected':''}>Por confirmar</option><option value="required" ${p.billingStatus==='required'?'selected':''}>Sí, requiere factura</option><option value="not_required" ${p.billingStatus==='not_required'?'selected':''}>No requiere factura</option></select><small>La factura se emite manualmente en tu sistema de facturación.</small></div><div class="form-field"><label for="p-nit">NIT / identificación</label><input class="input" id="p-nit" name="nit" value="${esc(p.nit)}" placeholder="Ej. 900123456-7" maxlength="60"></div><div class="form-field"><label for="p-business">Razón social</label><input class="input" id="p-business" name="businessName" value="${esc(p.businessName)}" placeholder="Empresa a facturar" maxlength="300"></div></div></div>
      <div class="form-section"><div class="form-field"><label for="p-notes">Observaciones</label><textarea id="p-notes" name="notes" placeholder="Detalles del negocio, diferencias o datos por confirmar…" maxlength="5000">${esc(p.notes)}</textarea></div></div></form>
      <details class="original-data"><summary>Ver datos originales de contabilidad · ${esc(p.sheet||'Hoja')} / fila ${esc(p.sourceRow||'—')}</summary><div class="source-grid">${[['Fecha bancaria',date(p.date)],['Valor',money(p.amount)],['Tercero',p.thirdParty],['Recibo de caja',p.receipt],['Factura',p.invoice],['Referencia',p.reference],['Descripción',p.description],['Archivo de origen',p.importName]].map(([k,v])=>`<div class="source-item"><label>${esc(k)}</label><div>${esc(v===null||v===undefined||v===''?'—':v)}</div></div>`).join('')}${Object.entries(p.original||{}).map(([k,v])=>`<div class="source-item"><label>${esc(k)}</label><div>${esc(v===null||v===undefined||v===''?'—':v)}</div></div>`).join('')}</div></details>
      <p class="secondary" style="white-space:normal;max-width:none;margin-top:15px">«Identificado» confirma el show y el empresario. Los abonos con factura y tercero identificado en origen también están listos, aunque no tengan un archivo adjunto. Revisa el contenido del soporte antes de entregarlo.</p></div>${fromReceipt?'<div class="drawer-footer"><button class="btn btn-primary" data-action="identify-payment">Guardar identificación</button></div>':`<div class="drawer-footer"><button class="btn" data-action="save-payment">Guardar cambios</button><button class="btn btn-primary" data-action="identify-payment">✓ Guardar e identificar</button></div>`}</section></div>`,'editor');
    renderAttachments(p);setupDropZone();renderReceiptPending(p);
  }
  function renderAttachments(p){const el=$('#attachments');if(!el)return;el.innerHTML=attachmentList(p).map(f=>{const url=f.url||`/api/reconciliation/files/${encodeURIComponent(f.id)}`;return `<div class="attachment">${String(f.type||f.mimeType||'').startsWith('image/')?`<img class="attachment-thumb" src="${esc(url)}" alt="Miniatura del comprobante">`:'<span class="attachment-thumb">PDF</span>'}<div class="attachment-info"><a href="${esc(url)}" target="_blank" rel="noopener">${esc(f.name)}</a><small>${Math.round((f.size||0)/1024)} KB · Guardado</small></div><button type="button" class="btn btn-quiet btn-small" data-action="preview-file" data-id="${esc(f.id)}">Ver</button><button type="button" class="remove-attachment" data-action="delete-file" data-id="${esc(f.id)}" aria-label="Eliminar ${esc(f.name)}">×</button></div>`;}).join('');}
  function setupDropZone(){const zone=$('#drop-zone');if(!zone)return;zone.addEventListener('dragover',e=>{e.preventDefault();zone.classList.add('dragover');});zone.addEventListener('dragleave',()=>zone.classList.remove('dragover'));zone.addEventListener('drop',e=>{e.preventDefault();zone.classList.remove('dragover');uploadFiles([...e.dataTransfer.files]);});}
  async function uploadFiles(files){
    if(!files.length||!state.selected||state.busy)return;state.busy=true;const id=state.selected;let completed=0;
    try{for(const file of files){if(!['image/jpeg','image/png','image/webp','application/pdf'].includes(file.type))throw new Error(`${file.name}: usa JPG, PNG, WebP o PDF.`);if(file.size>20*1024*1024)throw new Error(`${file.name}: supera el máximo de 20 MB.`);$('#upload-progress').textContent=`Guardando soporte ${completed+1} de ${files.length}…`;const body=new FormData();body.append('file',file);const result=await api(`/api/reconciliation/payments/${encodeURIComponent(id)}/files`,{method:'POST',body});completed++;if(result.warning)toast(result.warning);}
      await reload({keepDraft:true});toast(`${completed} comprobante${completed===1?'':'s'} guardado${completed===1?'':'s'}.`);
    }catch(error){toast(error.message,true);if(completed)await reload({keepDraft:true}).catch(()=>{});}finally{state.busy=false;if($('#upload-progress'))$('#upload-progress').textContent='';if($('#support-files'))$('#support-files').value='';}
  }
  async function savePayment(identify){
    if(state.busy)return;const form=$('#payment-form'),data=Object.fromEntries(new FormData(form));data.version=Number(data.version);if(identify)data.status='identified';
    if(data.status==='identified'&&(!data.showId||!data.entrepreneur.trim())){$('#editor-error').innerHTML='<div class="error-banner">Selecciona un show y escribe el nombre del empresario para identificar este abono.</div>';$('#p-show').focus();return;}
    state.busy=true;$$('.drawer-footer button').forEach(b=>b.disabled=true);
    try{
      const scan=receiptScan;
      if(scan&&scan.paymentId===state.selected&&!scan.attached){
        const body=new FormData();body.append('file',scan.file);body.append('paymentVersion',String(data.version));
        await api(`/api/reconciliation/payments/${encodeURIComponent(state.selected)}/files`,{method:'POST',body});
        if(receiptScan!==scan)throw new Error('Tu acceso cambió. Vuelve a abrir la ficha.');
        scan.attached=true;await reload({keepDraft:true});renderReceiptPending(state.payments.find(p=>p.id===state.selected));
      }
      await api(`/api/reconciliation/payments/${encodeURIComponent(state.selected)}`,{method:'PATCH',body:JSON.stringify(data)});discardReceipt();state.dirty=false;await reload();toast(identify?'Abono identificado. Los cambios quedaron guardados.':'Cambios guardados.');
    }
    catch(error){if($('#editor-error')){$('#editor-error').innerHTML=`<div class="error-banner">${esc(error.message)}</div>`;$('.drawer-body').scrollTop=0;}else toast(error.message,true);}
    finally{state.busy=false;$$('.drawer-footer button').forEach(b=>b.disabled=false);}
  }
  let editorReturn=null;
  function newShow(fromEditor=false){
    if(fromEditor){editorReturn={id:state.selected,draft:Object.fromEntries(new FormData($('#payment-form')))};}else editorReturn=null;
    state.dirty=fromEditor&&state.dirty;
    openOverlay(`<div class="overlay modal-overlay"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="show-title"><div class="modal-header"><div><h2 id="show-title">Agregar referencia histórica</h2><p>Usa esta referencia para shows históricos que no aparecen en el CRM. No crea un evento en Calendar.</p></div><button class="icon-close" data-action="cancel-show" aria-label="Cerrar">×</button></div><form id="show-form"><div class="modal-body"><div id="show-error" role="alert"></div><div class="form-grid"><div class="form-field full"><label for="s-name">Nombre del show *</label><input class="input" id="s-name" name="name" required maxlength="300" placeholder="Ej. Fiesta de aniversario"></div><div class="form-field"><label for="s-date">Fecha del show *</label><input class="input" type="date" id="s-date" name="date" required></div><div class="form-field"><label for="s-city">Ciudad</label><input class="input" id="s-city" name="city" maxlength="150" placeholder="Ciudad / municipio"></div><div class="form-field full"><label for="s-entrepreneur">Empresario</label><input class="input" id="s-entrepreneur" name="entrepreneur" maxlength="300" placeholder="Nombre de quien contrata"></div></div></div><div class="modal-footer"><button type="button" class="btn" data-action="cancel-show">Cancelar</button><button type="submit" class="btn btn-primary">Agregar referencia</button></div></form></section></div>`,'show');setTimeout(()=>$('#s-name')?.focus(),30);
  }
  function returnToEditor(newShowId){const ret=editorReturn;editorReturn=null;if(!ret){closeOverlay(true);return;}const p=state.payments.find(p=>p.id===ret.id);if(!p){closeOverlay(true);return;}renderEditor(p);for(const [k,v]of Object.entries(ret.draft)){const el=$(`[name="${k}"]`,$('#payment-form'));if(el)el.value=v;}if(newShowId){$('#p-show').value=newShowId;const s=state.shows.find(s=>s.id===newShowId);if(s?.entrepreneur&&!$('#p-entrepreneur').value)$('#p-entrepreneur').value=s.entrepreneur;}state.dirty=true;}
  async function saveShow(form){state.busy=true;const btn=$('button[type="submit"]',form);btn.disabled=true;try{const data=Object.fromEntries(new FormData(form)),result=await api('/api/reconciliation/shows',{method:'POST',body:JSON.stringify(data)});await reload();returnToEditor((result.show||result).id);toast('Referencia guardada para conciliación.');}catch(error){if($('#show-error'))$('#show-error').innerHTML=`<div class="error-banner">${esc(error.message)}</div>`;else toast(error.message,true);}finally{state.busy=false;if(btn.isConnected)btn.disabled=false;}}
  async function loadImport(file){
    if(!file)return;if(!/\.(xlsx|csv)$/i.test(file.name)){toast('Selecciona un archivo .xlsx o .csv.',true);return;}if(file.size>20*1024*1024){toast('El archivo supera 20 MB. Divide el libro en archivos más pequeños.',true);return;}
    toast('Leyendo el archivo…');try{const content=await file.arrayBuffer();const sheets=/\.xlsx$/i.test(file.name)?(await FileTools.parseXlsx(file)).sheets:[{name:'CSV',rows:FileTools.parseCsv(await file.text())}];if(!sheets.length)throw new Error('El archivo no tiene hojas legibles.');importData={file,content,sheets,sheet:0,header:0,mapping:{},skipInvalid:false};guessHeader();renderImport();}catch(error){toast(error.message||'No se pudo leer el archivo.',true);}finally{$('#import-file').value='';}
  }
  const fields=[['date','Fecha bancaria *',['fecha','fecha consignacion','fecha de pago']],['amount','Valor del abono *',['valor','abono','credito','importe','consignacion']],['description','Descripción',['descripcion','concepto','detalle','observacion']],['reference','Referencia',['referencia','numero transaccion','transaccion']],['thirdParty','Tercero original',['tercero','cliente','nombre tercero','beneficiario']],['receipt','Recibo de caja',['recibo','recibo de caja','rc','r.c.']],['invoice','Factura',['factura','fv','factura de venta','fac.siigo','fac. siigo']]];
  function guessHeader(){const sheet=importData.sheets[importData.sheet];let best=0,score=-1;sheet.rows.slice(0,30).forEach((row,i)=>{const t=row.map(norm);const s=fields.reduce((sum,[, ,words])=>sum+(t.some(v=>words.some(w=>v===w||v.startsWith(w+' ')))?1:0),0);if(s>score){score=s;best=i;}});importData.header=best;guessMapping();}
  function headers(){const row=importData.sheets[importData.sheet].rows[importData.header]||[];return row.map((h,i)=>String(h??'').trim()||`Columna ${i+1}`);}
  function guessMapping(){const h=headers().map(norm);importData.mapping={};const used=new Set();for(const[key,,terms]of fields){let idx=h.findIndex((v,i)=>!used.has(i)&&terms.some(t=>v===t));if(idx<0)idx=h.findIndex((v,i)=>!used.has(i)&&terms.some(t=>v.startsWith(t+' ')||v.includes(' '+t)));importData.mapping[key]=idx>=0?String(idx):'';if(idx>=0)used.add(idx);}}
  function importRows(){
    const sheet=importData.sheets[importData.sheet],h=headers(),valid=[],invalid=[];const mapped=(row,key)=>{const idx=importData.mapping[key];return idx===''||idx===undefined?'':row[Number(idx)]??'';};
    sheet.rows.forEach((row,i)=>{if(i<=importData.header||!row.some(c=>c!==''&&c!==null&&c!==undefined))return;const d=ndate(mapped(row,'date')),amount=namount(mapped(row,'amount'));const issue=!d?'Fecha inválida o vacía':amount===null||!Number.isFinite(amount)?'Valor inválido o vacío':amount<=0?'El valor debe ser mayor que cero':'';
      if(issue){invalid.push({row:i+1,issue,date:mapped(row,'date'),amount:mapped(row,'amount')});return;}
      const original={};for(let j=0;j<Math.max(h.length,row.length);j++){let key=h[j]||`Columna ${j+1}`;if(Object.hasOwn(original,key))key+=` [${j+1}]`;original[key]=row[j]??'';}
      valid.push({sourceRow:i+1,sheet:sheet.name,date:d,amount,description:String(mapped(row,'description')),reference:String(mapped(row,'reference')),thirdParty:String(mapped(row,'thirdParty')),receipt:String(mapped(row,'receipt')),invoice:String(mapped(row,'invoice')),original});
    });return {valid,invalid};
  }
  function renderImport(){
    const h=headers();openOverlay(`<div class="overlay modal-overlay"><section class="modal large" role="dialog" aria-modal="true" aria-labelledby="import-title"><div class="modal-header"><div><h2 id="import-title">Importar consignaciones</h2><p>${esc(importData.file.name)} · Revisa las columnas antes de continuar.</p></div><button class="icon-close" data-action="close" aria-label="Cerrar importación">×</button></div><div class="modal-body"><div id="import-error" role="alert"></div><div class="import-layout"><div class="form-field"><label for="import-sheet">Hoja del libro</label><select id="import-sheet">${importData.sheets.map((s,i)=>`<option value="${i}" ${i===importData.sheet?'selected':''}>${esc(s.name)}</option>`).join('')}</select></div><div class="form-field"><label for="import-header">Fila de encabezados</label><input class="input" id="import-header" type="number" min="1" max="${importData.sheets[importData.sheet].rows.length}" value="${importData.header+1}"></div></div><div class="mapping-grid">${fields.map(([key,label])=>`<div><label for="map-${key}">${label}</label><select id="map-${key}" data-map="${key}"><option value="">${['date','amount'].includes(key)?'Seleccionar columna':'No está en el archivo'}</option>${h.map((name,i)=>`<option value="${i}" ${String(i)===importData.mapping[key]?'selected':''}>${i+1}. ${esc(name)}</option>`).join('')}</select></div>`).join('')}</div><div id="import-preview"></div></div><div class="modal-footer"><button class="btn" data-action="close">Cancelar</button><button class="btn btn-primary" data-action="confirm-import" id="confirm-import">Importar abonos</button></div></section></div>`,'import');renderImportPreview();
  }
  function renderImportPreview(){const {valid,invalid}=importRows(),missing=['date','amount'].some(k=>importData.mapping[k]===''),same=importData.mapping.date!==''&&importData.mapping.date===importData.mapping.amount;$('#import-preview').innerHTML=`<div class="preview-table"><table><thead><tr><th>Fila</th><th>Fecha bancaria</th><th>Valor</th><th>Tercero</th><th>Recibo</th><th>Factura</th></tr></thead><tbody>${valid.slice(0,5).map(r=>`<tr><td>${r.sourceRow}</td><td>${esc(date(r.date))}</td><td>${money(r.amount)}</td><td>${esc(r.thirdParty||'—')}</td><td>${esc(r.receipt||'—')}</td><td>${esc(r.invoice||'—')}</td></tr>`).join('')}${!valid.length?'<tr><td colspan="6">Selecciona las columnas de fecha y valor para ver la vista previa.</td></tr>':''}</tbody></table></div><div class="import-summary"><strong>${valid.length} abonos válidos</strong> · Total ${money(sum(valid))}. Se conservarán todas las columnas de cada fila.<br>Las coincidencias de fecha y valor no se consideran duplicados automáticamente.</div>${missing||same?`<div class="notice warning" style="margin-top:14px">${same?'La fecha y el valor deben corresponder a columnas diferentes.':'Selecciona una columna para fecha y otra para valor.'}</div>`:''}${invalid.length&&!missing?`<div class="notice warning" style="margin-top:14px"><strong>${invalid.length} filas necesitan revisión.</strong><br>${invalid.slice(0,6).map(r=>`Fila ${r.row}: ${esc(r.issue)} (fecha: ${esc(r.date)}, valor: ${esc(r.amount)})`).join('<br>')}${invalid.length>6?`<br>Y ${invalid.length-6} filas más.`:''}<label class="check-label"><input id="skip-invalid" type="checkbox" ${importData.skipInvalid?'checked':''}>Omitir estas ${invalid.length} filas en esta importación. Revisaré los datos en el archivo original.</label></div>`:''}<div class="notice" style="margin-top:15px">Los recibos, facturas y terceros existentes se guardan como datos de origen. La identificación del show se confirma después. Puedes importar las otras hojas del libro por separado.</div>`;$('#confirm-import').disabled=missing||same||!valid.length||(invalid.length>0&&!importData.skipInvalid);$('#confirm-import').textContent=`Importar ${valid.length} abonos`;}
  async function confirmImport(){
    if(state.busy)return;const {valid,invalid}=importRows();if(!valid.length||(invalid.length&&!importData.skipInvalid))return;state.busy=true;$('#confirm-import').disabled=true;$('#confirm-import').textContent='Guardando abonos…';
    try{const extra=new TextEncoder().encode(importData.sheets[importData.sheet].name),bytes=new Uint8Array(importData.content.byteLength+extra.length);bytes.set(new Uint8Array(importData.content));bytes.set(extra,importData.content.byteLength);const digest=await crypto.subtle.digest('SHA-256',bytes);const fileHash=[...new Uint8Array(digest)].map(x=>x.toString(16).padStart(2,'0')).join('');const result=await api('/api/reconciliation/import',{method:'POST',body:JSON.stringify({name:`${importData.file.name} · ${importData.sheets[importData.sheet].name}`,fileHash,rows:valid})});await reload();closeOverlay(true);toast(result.duplicate||result.alreadyImported||result.imported===0?(result.message||'Esta hoja ya estaba importada. No se crearon duplicados.'):`${result.imported??result.count??result.inserted??valid.length} abonos importados.${invalid.length?` Se omitieron ${invalid.length} filas según tu selección.`:''}`);importData=null;}
    catch(error){if($('#import-error')){$('#import-error').innerHTML=`<div class="error-banner">${esc(error.message)}</div>`;$('#confirm-import').disabled=false;$('#confirm-import').textContent=`Importar ${valid.length} abonos`;}else toast(error.message,true);}
    finally{state.busy=false;}
  }
  function exportModal(){const rows=filtered(),r=rows.filter(ready);openOverlay(`<div class="overlay modal-overlay"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="export-title"><div class="modal-header"><div><h2 id="export-title">Entrega a contabilidad</h2><p>Una relación clara y sus comprobantes.</p></div><button class="icon-close" data-action="close" aria-label="Cerrar">×</button></div><div class="modal-body"><div id="export-error" role="alert"></div><div class="radio-list"><label class="radio-option"><input type="radio" name="export-scope" value="ready" ${r.length?'checked':''} ${!r.length?'disabled':''}><span>Solo listos para contabilidad · ${r.length}<small>Abonos identificados con al menos un soporte adjunto, dentro de tus filtros actuales.</small></span></label><label class="radio-option"><input type="radio" name="export-scope" value="filtered" ${!r.length?'checked':''}><span>Todos los resultados actuales · ${rows.length}<small>Incluye pendientes, datos contables originales y anotaciones nuevas.</small></span></label><label class="radio-option"><input type="radio" name="export-scope" value="all"><span>Toda la relación · ${state.payments.length}<small>Exporta todos los abonos, sin aplicar filtros.</small></span></label></div><label class="check-label"><input id="export-files" type="checkbox" checked>Incluir los comprobantes en un archivo ZIP</label><div class="notice" style="margin-top:18px">Recibirás un CSV compatible con Excel y, si lo eliges, una carpeta por abono con sus soportes. Máximo 200 MB de soportes por paquete; puedes dividirlos por fechas. Descargar no marca los pagos como enviados ni emite facturas.</div></div><div class="modal-footer"><button class="btn" data-action="close">Cancelar</button><button class="btn btn-primary" data-action="download-export" id="download-export">↓ Descargar paquete</button></div></section></div>`,'export');}
  async function downloadExport(){if(state.busy)return;state.busy=true;const btn=$('#download-export');btn.disabled=true;btn.textContent='Preparando archivos…';try{const scope=$('input[name="export-scope"]:checked').value;let rows=scope==='all'?ordered(state.payments):filtered();if(scope==='ready')rows=rows.filter(ready);if(!rows.length)throw new Error('No hay abonos en la selección.');rows=rows.map(p=>{const s=showOf(p);return {...p,showName:s?.name||'',showDate:s?.date||'',showCity:s?.city||'',statusLabel:statusLabel(p)};});await FileTools.exportPackage(rows,{includeFiles:$('#export-files').checked,filename:`Conciliacion_JAC_${new Date().toISOString().slice(0,10)}`});closeOverlay(true);toast('La descarga está lista. Puedes compartirla con contabilidad.');}catch(error){if($('#export-error'))$('#export-error').innerHTML=`<div class="error-banner">${esc(error.message)}</div>`;else toast(error.message,true);}finally{state.busy=false;if(btn.isConnected){btn.disabled=false;btn.textContent='↓ Descargar paquete';}}}
  async function deleteFile(id){if(state.busy||!confirm('¿Eliminar este comprobante del abono? La identificación y los datos originales se conservarán.'))return;state.busy=true;try{await api(`/api/reconciliation/files/${encodeURIComponent(id)}`,{method:'DELETE'});await reload({keepDraft:true});toast('Comprobante eliminado.');}catch(error){toast(error.message,true);}finally{state.busy=false;}}
  function previewFile(id){const p=state.payments.find(p=>p.id===state.selected),f=attachmentList(p||{}).find(f=>f.id===id);if(!f)return;const existing=$('#file-preview');if(existing)existing.remove();const div=document.createElement('div');div.id='file-preview';div.className='attachment-preview';const url=f.url||`/api/reconciliation/files/${encodeURIComponent(id)}`;div.innerHTML=`<div style="text-align:right;margin-bottom:7px"><button type="button" class="link-button" data-action="close-preview">Cerrar vista previa ×</button></div>${String(f.type||f.mimeType).startsWith('image/')?`<img src="${esc(url)}" alt="Comprobante ${esc(f.name)}">`:`<iframe title="Comprobante ${esc(f.name)}" src="${esc(url)}"></iframe>`}`;$('#attachments').after(div);div.scrollIntoView({behavior:'smooth',block:'nearest'});}
  document.addEventListener('click',event=>{
    const target=event.target.closest('[data-action]');if(!target||target.disabled)return;const action=target.dataset.action;
    if(action==='nav'){state.view=target.dataset.view;render();}
    else if(action==='scan-receipt'){if(!state.busy){discardReceipt();state.selected=null;state.dirty=false;renderReceipt();}}
    else if(action==='choose-scan'){if(!state.busy)$('#scan-file')?.click();}
    else if(action==='paste-scan')pasteReceipt();
    else if(action==='split-scan'&&receiptScan&&!state.busy)startReceiptBatch(receiptScan.file);
    else if(action==='cancel-scan'){state.busy=false;state.dirty=false;closeOverlay(true);}
    else if(action==='select-scan-payment')selectReceiptPayment(target.dataset.id);
    else if(action==='review-scan'){if(receiptScan&&!state.busy){receiptScan.draft={id:state.selected,values:Object.fromEntries(new FormData($('#payment-form')))};state.selected=null;renderReceipt();}}
    else if(action==='import')$('#import-file').click();
    else if(action==='filter'){state.filter=target.dataset.filter;state.page=1;render();}
    else if(action==='page'){state.page+=Number(target.dataset.offset);renderTable();}
    else if(action==='clear-filters'){Object.assign(state,{query:'',amount:'',from:'',to:'',page:1});render();}
    else if(action==='clear-show'){state.showId='';render();}
    else if(action==='edit'){const p=state.payments.find(p=>p.id===target.dataset.id);if(p)renderEditor(p);}
    else if(action==='close')closeOverlay();
    else if(action==='attach')$('#support-files').click();
    else if(action==='save-payment')savePayment(false);
    else if(action==='identify-payment')savePayment(true);
    else if(action==='new-show')newShow();
    else if(action==='new-show-editor')newShow(true);
    else if(action==='cancel-show')returnToEditor();
    else if(action==='show-payments'){state.view='payments';state.showId=target.dataset.id;state.filter='all';state.page=1;render();}
    else if(action==='confirm-import')confirmImport();
    else if(action==='export')exportModal();
    else if(action==='download-export')downloadExport();
    else if(action==='delete-file')deleteFile(target.dataset.id);
    else if(action==='preview-file')previewFile(target.dataset.id);
    else if(action==='close-preview')$('#file-preview')?.remove();
    else if(action==='retry')reload().catch(()=>{});
  });
  document.addEventListener('input',event=>{const el=event.target;if(el.closest('#payment-form'))state.dirty=true;if(receiptScan&&['scan-amount','scan-date'].includes(el.id)){receiptScan[el.id==='scan-amount'?'amount':'date']=el.value;receiptScan.matchesCurrent=false;const candidates=$('#receipt-candidates');if(candidates)candidates.innerHTML='<p class="secondary">Pulsa Buscar coincidencias para aplicar los datos corregidos.</p>';}const keys={'search':'query','amount-filter':'amount','date-from':'from','date-to':'to'};if(keys[el.id]){state[keys[el.id]]=el.value;state.page=1;renderTable();}});
  document.addEventListener('change',event=>{const el=event.target;if(el.id==='scan-file')readReceiptFile(el.files[0]);if(el.id==='date-order'){state.dateOrder=el.value==='asc'?'asc':'desc';state.page=1;renderTable();}if(el.id==='import-file')loadImport(el.files[0]);if(el.id==='support-files')uploadFiles([...el.files]);if(el.id==='p-show'){const show=state.shows.find(s=>s.id===el.value);if(show?.entrepreneur&&!$('#p-entrepreneur').value)$('#p-entrepreneur').value=show.entrepreneur;state.dirty=true;}if(el.id==='import-sheet'){importData.sheet=Number(el.value);importData.skipInvalid=false;guessHeader();renderImport();}if(el.id==='import-header'){const value=Number(el.value);if(!Number.isInteger(value)||value<1||value>importData.sheets[importData.sheet].rows.length){toast('Selecciona un número de fila válido.',true);return;}importData.header=value-1;importData.skipInvalid=false;guessMapping();renderImport();}if(el.dataset.map){importData.mapping[el.dataset.map]=el.value;importData.skipInvalid=false;renderImportPreview();}if(el.id==='skip-invalid'){importData.skipInvalid=el.checked;renderImportPreview();}});
  document.addEventListener('submit',event=>{if(event.target.id==='receipt-search'){event.preventDefault();searchReceiptMatches();}if(event.target.id==='show-form'){event.preventDefault();saveShow(event.target);}if(event.target.id==='payment-form'){event.preventDefault();savePayment(false);}});
  document.addEventListener('paste',event=>{
    if(!['editor','receipt'].includes(state.overlay))return;
    const items=[...(event.clipboardData?.items||[])].filter(x=>x.kind==='file').map(x=>x.getAsFile()).filter(Boolean);
    const files=items.length?items:[...(event.clipboardData?.files||[])];
    if(files.length){event.preventDefault();if(state.busy)return;if(state.overlay==='receipt'){if(files.length!==1)return toast('Pega un comprobante a la vez.',true);readReceiptFile(files[0]);}else uploadFiles(files);}
    else if(state.overlay==='receipt'&&(event.target.id==='receipt-paste-target'||!event.target.closest?.('input,textarea,[contenteditable="true"]'))){event.preventDefault();receiptPasteHelp('Copia la imagen del comprobante, no su enlace ni el texto del mensaje. También puedes seleccionar o arrastrar el archivo.');}
  });
  document.addEventListener('input',event=>{if(event.target.id==='receipt-paste-target')event.target.value='';});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&state.overlay){if(state.overlay==='receipt'&&receiptScan?.loading){state.busy=false;state.dirty=false;closeOverlay(true);}else if(state.overlay==='show')returnToEditor();else closeOverlay();}if(event.key==='Enter'&&event.target.matches('[data-action="edit"],[data-action="show-payments"],#drop-zone')){event.preventDefault();event.target.click();}if(event.key==='Tab'&&state.overlay){const items=$$('button:not([disabled]),input:not([hidden]):not([disabled]),select:not([disabled]),textarea,a[href],[tabindex="0"]',$('#overlay-root')).filter(el=>el.offsetParent!==null);const first=items[0],last=items.at(-1);if(event.shiftKey&&document.activeElement===first){last?.focus();event.preventDefault();}else if(!event.shiftKey&&document.activeElement===last){first?.focus();event.preventDefault();}}});
  if(window.parent===window)window.addEventListener('beforeunload',event=>{if(state.dirty||state.busy){event.preventDefault();event.returnValue='';}});
  window.addEventListener('message',event=>{if(event.origin===location.origin&&event.source===window.parent&&event.data?.type==='jac-reconciliation-discard'){state.dirty=false;notifyParent();}});
  const revalidate=()=>{if(!state.busy&&document.visibilityState==='visible')reload({keepDraft:state.dirty}).catch(()=>{});};
  window.addEventListener('focus',revalidate);
  document.addEventListener('visibilitychange',revalidate);
  setInterval(revalidate,60000);
  reload().catch(()=>{});
})();
