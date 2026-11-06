// Private results live only in memory and are discarded on close or logout.
export function createInternalGallery({ api, authorized, onExpired }) {
  const $ = id => document.getElementById(id);
  const dialog = $('gallery-dialog'), grid = $('gallery-grid'), status = $('gallery-status');
  const previous = $('gallery-previous'), next = $('gallery-next'), refresh = $('gallery-refresh');
  const detail = $('gallery-detail'), detailImage = $('gallery-detail-image'), detailStatus = $('gallery-detail-status');
  const dateFormat = new Intl.DateTimeFormat('es-CO', { timeZone: 'America/Bogota', dateStyle: 'medium', timeStyle: 'short' });
  let revision = 0, controller = null, busy = false, cursor = '', nextCursor = '', history = [], page = 1;
  let urls = [], queue = [], workers = 0, observer = null, expiryTimer = null, detailRevision = 0, detailController = null, detailURL = '';

  function closeDetail() {
    detailRevision++; detailController?.abort(); detailController = null;
    detailImage.removeAttribute('src'); detailImage.hidden = true;
    if (detailURL) URL.revokeObjectURL(detailURL);
    detailURL = ''; detailStatus.textContent = ''; if (detail.open) detail.close();
  }
  function clearPage() {
    revision++; controller?.abort(); controller = null; observer?.disconnect(); observer = null;
    clearTimeout(expiryTimer); expiryTimer = null;
    closeDetail(); grid.replaceChildren(); urls.forEach(url => URL.revokeObjectURL(url));
    urls = []; queue = []; workers = 0; busy = false;
  }
  function close() {
    clearPage(); cursor = ''; nextCursor = ''; history = []; page = 1; status.textContent = '';
    if (dialog.open) dialog.close();
    document.body.classList.remove('gallery-open');
  }
  function expired() { close(); onExpired(); }
  function active(ticket) { return ticket === revision && dialog.open && authorized(); }
  function controls() {
    refresh.disabled = busy; previous.disabled = busy || !history.length; next.disabled = busy || !nextCursor;
    grid.setAttribute('aria-busy', String(busy)); $('gallery-page').textContent = `Página ${page}`;
  }
  async function fetchPrivate(query, signal) {
    const response = await fetch(`${api}?internal-gallery=1${query}`, { credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal });
    if (!response.ok) {
      const body = (response.headers.get('content-type') || '').includes('application/json') ? await response.json() : {};
      throw Object.assign(new Error(body.error || 'No pudimos cargar las creaciones. Inténtalo de nuevo.'), { status: response.status });
    }
    return response;
  }
  async function openPhoto(item, ticket) {
    if (!active(ticket)) return;
    closeDetail(); detail.showModal(); detailStatus.textContent = 'Abriendo foto…';
    $('gallery-detail-date').textContent = dateFormat.format(new Date(item.createdAt));
    const current = ++detailRevision, pending = new AbortController(); detailController = pending;
    try {
      const response = await fetchPrivate(`&id=${encodeURIComponent(item.id)}`, pending.signal);
      if (!(response.headers.get('content-type') || '').startsWith('image/png')) throw new Error('No pudimos abrir esta foto.');
      const blob = await response.blob();
      if (!active(ticket) || current !== detailRevision || !detail.open) return;
      detailURL = URL.createObjectURL(blob); detailImage.src = detailURL; detailImage.hidden = false; detailStatus.textContent = '';
    } catch (error) {
      if (!active(ticket) || current !== detailRevision || error.name === 'AbortError') return;
      if ([401, 403].includes(error.status)) { expired(); return; }
      detailStatus.textContent = error.message;
    }
  }
  function pump(ticket) {
    if (!active(ticket)) return;
    while (workers < 3 && queue.length) {
      const entry = queue.shift(); workers++;
      void thumbnail(entry, ticket).finally(() => { if (active(ticket)) { workers--; pump(ticket); } });
    }
  }
  async function thumbnail({ item, image, button, note }, ticket) {
    button.disabled = true; note.textContent = 'Cargando vista previa…';
    try {
      const response = await fetchPrivate(`&id=${encodeURIComponent(item.id)}&preview=1`, controller.signal);
      if (!(response.headers.get('content-type') || '').startsWith('image/jpeg')) throw new Error('Vista previa no disponible');
      const blob = await response.blob();
      if (blob.size > 512 * 1024) throw new Error('Vista previa no disponible');
      if (!active(ticket)) return;
      const url = URL.createObjectURL(blob); urls.push(url); image.src = url; image.hidden = false;
      note.textContent = 'Ver foto'; button.disabled = false;
      button.onclick = () => { void openPhoto(item, ticket); };
    } catch (error) {
      if (!active(ticket) || error.name === 'AbortError') return;
      if ([401, 403].includes(error.status)) { expired(); return; }
      note.textContent = error.status === 404 ? 'Foto no disponible' : 'Reintentar vista previa';
      button.disabled = error.status === 404;
      button.onclick = () => { button.disabled = true; queue.push({ item, image, button, note }); pump(ticket); };
    }
  }
  function card(item, ticket) {
    const figure = document.createElement('figure'), button = document.createElement('button');
    const image = document.createElement('img'), note = document.createElement('span'), caption = document.createElement('figcaption');
    const date = dateFormat.format(new Date(item.createdAt));
    figure.className = 'gallery-card'; button.type = 'button'; button.className = 'gallery-photo';
    button.disabled = true; button.setAttribute('aria-label', `Ver creación del ${date}`);
    image.alt = `Creación del ${date}`; image.width = 480; image.height = 600; image.hidden = true; image.decoding = 'async';
    note.textContent = 'Vista previa'; note.className = 'gallery-photo-note';
    const time = document.createElement('time'); time.dateTime = item.createdAt; time.textContent = date; caption.append(time);
    button.append(image, note); figure.append(button, caption); grid.append(figure);
    const entry = { item, image, button, note };
    if (observer) { button.galleryEntry = entry; observer.observe(button); } else queue.push(entry);
  }
  async function load(target = '', direction = 'refresh') {
    if (busy || !authorized() || !dialog.open) return;
    const oldCursor = cursor;
    clearPage(); const ticket = revision; controller = new AbortController(); busy = true;
    status.textContent = 'Cargando creaciones…'; controls();
    try {
      const response = await fetchPrivate(target ? `&cursor=${encodeURIComponent(target)}` : '', controller.signal), data = await response.json();
      if (!active(ticket)) return;
      if (!Array.isArray(data.items) || data.items.length > 12 || typeof data.nextCursor !== 'string' || !Number.isSafeInteger(data.total) || !Number.isFinite(data.sessionExpiresIn) || data.sessionExpiresIn <= 0 || data.sessionExpiresIn > 8 * 3600000) throw new Error('No pudimos leer la galería. Pulsa Actualizar.');
      expiryTimer = setTimeout(expired, data.sessionExpiresIn);
      if (direction === 'next') { history.push(oldCursor); page++; }
      else if (direction === 'previous') { history.pop(); page--; }
      else { history = []; page = 1; }
      cursor = target; nextCursor = data.nextCursor;
      $('gallery-total').textContent = `${data.total.toLocaleString('es-CO')} ${data.total === 1 ? 'creación' : 'creaciones'}`;
      status.textContent = data.items.length ? 'De la más reciente a la más antigua · Hora de Colombia' : 'Todavía no hay creaciones terminadas en esta página.';
      if ('IntersectionObserver' in window) observer = new IntersectionObserver(entries => {
        if (!active(ticket) || !observer) return;
        for (const entry of entries) if (entry.isIntersecting) { observer.unobserve(entry.target); queue.push(entry.target.galleryEntry); }
        pump(ticket);
      }, { root: dialog, rootMargin: '180px' });
      for (const item of data.items) card(item, ticket);
      pump(ticket);
    } catch (error) {
      if (!active(ticket) || error.name === 'AbortError') return;
      if ([401, 403].includes(error.status)) { expired(); return; }
      status.textContent = error.message;
    } finally { if (active(ticket)) { busy = false; controls(); } }
  }
  function open() {
    if (!authorized()) return;
    if (!dialog.open) dialog.showModal();
    document.body.classList.add('gallery-open'); void load();
  }
  $('gallery-close').addEventListener('click', close);
  dialog.addEventListener('cancel', event => { event.preventDefault(); close(); });
  $('gallery-detail-close').addEventListener('click', closeDetail);
  detail.addEventListener('cancel', event => { event.preventDefault(); closeDetail(); });
  refresh.addEventListener('click', () => { void load(); });
  previous.addEventListener('click', () => { if (history.length) void load(history[history.length - 1], 'previous'); });
  next.addEventListener('click', () => { if (nextCursor) void load(nextCursor, 'next'); });
  window.addEventListener('pagehide', close);
  // Do not retain other people's photos in a hidden tab or the back/forward cache.
  document.addEventListener('visibilitychange', () => { if (document.hidden) close(); });
  return { open, close };
}
