const API = '/api/fans/cumpleanos';
const STORAGE_KEY = 'jac-birthday-job-v1';
const RESET_STORAGE_KEY = 'jac-birthday-reset-v1';
const MAX_FILE_BYTES = 8 * 1024 * 1024;
const STILL_PHOTO_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']);
const PHOTO_EXTENSION = /\.(?:jpe?g|png|webp|heic|heif)$/i;
const POLL_DEADLINE = 12 * 60 * 1000;
const VERIFICATION_MAX_AGE = 120000;
const VERIFICATION_CODES = new Set(['verification_required', 'verification_expired', 'verification_rejected', 'verification_unavailable', 'verification_configuration']);
const DAILY_LIMIT_CODES = new Set(['daily_browser_limit', 'daily_ip_limit', 'daily_global_limit']);
const $ = id => document.getElementById(id);
const el = {
  form: $('photo-form'), input: $('photo-input'), upload: $('upload-zone'), selected: $('selected-photo'),
  preview: $('photo-preview'), previewNote: $('preview-note'), name: $('selected-name'), size: $('selected-size'), generate: $('generate-button'),
  camera: $('camera-action'), cameraInput: $('camera-input'), cameraButton: $('take-photo'),
  availability: $('availability'), human: $('human-check'),
  job: $('job-panel'), jobTitle: $('job-title'), progressTrack: $('progress-track'), progress: $('job-progress'),
  message: $('job-message'), detail: $('job-detail'), refresh: $('refresh-job'), cancel: $('cancel-job'),
  result: $('result-panel'), campaign: $('campaign-photo'), photoLabel: $('photo-label'), photoCaption: $('photo-caption'),
  download: $('download-photo'), share: $('share-photo'), delete: $('delete-photo'), error: $('error-message'),
  internalPanel: $('internal-panel'), internalDetails: $('internal-details'), internalForm: $('internal-form'),
  internalCode: $('internal-code'), internalSubmit: $('internal-submit'), internalActive: $('internal-active'),
  internalExit: $('internal-exit'), internalFeedback: $('internal-feedback'), internalOpen: $('open-internal'), internalHelp: $('internal-help'),
  internalReset: $('internal-reset'),
};
const internalHelpText = el.internalHelp.textContent;
let config = null;
let selectedFile = null;
let selectedURL = '';
let previewRevision = 0;
let previewProbe = null;
let resultURL = '';
let resultFile = null;
let jobID = '';
let requestID = '';
let pollTimer = null;
let pollStarted = 0;
let generation = 0;
let uploading = false;
let deleting = false;
let xhr = null;
let widgetID = null;
let turnstileToken = '';
let tokenIssuedAt = 0;
let challengeRevision = 0;
let verificationPending = false;
let verificationNeedsRefresh = false;
let creationBlocked = '';
let creationBlockedCode = '';
let creationBlockedMessage = '';
let internalAvailable = false;
let internalMode = false;
let internalBusy = false;
let internalController = null;
let internalRevision = 0;
let resetBusy = false;
let resetID = '';
let resetController = null;
let resetRevision = 0;
let activeStatus = '';
let resultLoading = false;
let serverConfigured = false;
let requestController = null;

function storedJob() { try { return sessionStorage.getItem(STORAGE_KEY) || ''; } catch { return ''; } }
function rememberJob(id) { try { if (id) sessionStorage.setItem(STORAGE_KEY, id); else sessionStorage.removeItem(STORAGE_KEY); } catch { /* Photos remain usable when storage is disabled. */ } }
function storedReset() { try { return sessionStorage.getItem(RESET_STORAGE_KEY) || ''; } catch { return ''; } }
function rememberReset(id) { try { if (id) sessionStorage.setItem(RESET_STORAGE_KEY, id); else sessionStorage.removeItem(RESET_STORAGE_KEY); } catch { /* The in-memory operation ID still protects retries in this tab. */ } }
function validID(value) { return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function showError(message = '') {
  el.error.textContent = message; el.error.hidden = !message;
  if (message) {
    el.error.tabIndex = -1; el.error.focus({ preventScroll: true });
    el.error.scrollIntoView({ block: 'nearest' });
  }
}
function stopPolling() { clearTimeout(pollTimer); pollTimer = null; }
function clearRequest() { requestController?.abort(); requestController = null; }
function cleanupResult() {
  if (resultURL) URL.revokeObjectURL(resultURL);
  resultURL = ''; resultFile = null; el.download.removeAttribute('href');
}
function resetPhotoDisplay() {
  cleanupResult(); el.campaign.src = '/cumpleanos/master-v1.png';
  el.campaign.alt = 'Ejemplo de la foto: Jhon Alex y un acompañante brindan con gorritos rojos en su celebración de cumpleaños.';
  el.photoLabel.textContent = 'ASÍ SE CELEBRA CON EL REY';
  el.photoCaption.textContent = 'Tu lugar en este brindis está a la derecha.';
}
function controls() {
  const locked = uploading || deleting || Boolean(jobID);
  el.input.disabled = locked; $('change-photo').disabled = locked; $('remove-photo').disabled = locked;
  el.cameraInput.disabled = locked; el.cameraButton.disabled = locked;
  const needsProof = Boolean(config?.turnstileSiteKey) && !turnstileToken;
  el.generate.disabled = !serverConfigured || Boolean(creationBlocked) || internalBusy || resetBusy || !selectedFile || locked || (needsProof && (verificationPending || !verificationNeedsRefresh));
  el.generate.querySelector('span').textContent = creationBlocked || (needsProof && verificationNeedsRefresh ? 'Volver a verificar' : verificationPending ? 'Completa la verificación' : 'Crear mi foto con el Rey');
  el.cancel.disabled = uploading || deleting;
  el.delete.disabled = deleting;
  el.refresh.disabled = uploading || deleting;
  internalControls();
}
function setBusyPanel(title, message, detail) {
  el.form.hidden = true; el.result.hidden = true; el.job.hidden = false;
  el.jobTitle.textContent = title; el.message.textContent = message; el.detail.textContent = detail;
  el.progressTrack.hidden = false; el.progress.removeAttribute('value');
  el.progress.setAttribute('aria-label', 'Preparación de tu imagen');
  el.refresh.hidden = true;
}
function challengeVisible() {
  return serverConfigured && !creationBlocked && Boolean(config?.turnstileSiteKey) && !uploading && !deleting && !jobID && !el.form.hidden;
}
function discardChallenge() {
  challengeRevision++; turnstileToken = ''; tokenIssuedAt = 0; verificationPending = false;
  if (widgetID !== null) window.turnstile?.remove?.(widgetID);
  widgetID = null; el.human.replaceChildren(); el.human.hidden = true;
}
function renderChallenge() {
  if (!challengeVisible() || widgetID !== null || !window.turnstile) return;
  const revision = ++challengeRevision;
  const current = () => revision === challengeRevision && challengeVisible();
  verificationPending = true; el.human.hidden = false;
  const failed = message => {
    if (!current()) return;
    turnstileToken = ''; tokenIssuedAt = 0; verificationPending = false; verificationNeedsRefresh = true;
    controls(); showError(message);
  };
  widgetID = window.turnstile.render(el.human, {
    sitekey: config.turnstileSiteKey, theme: 'light', action: 'birthday-photo',
    retry: 'never', 'refresh-expired': 'manual', 'refresh-timeout': 'manual',
    callback(token) {
      if (!current()) return;
      turnstileToken = token; tokenIssuedAt = Date.now(); verificationPending = false; verificationNeedsRefresh = false; controls();
    },
    'expired-callback'() { failed('La verificación venció. Pulsa «Volver a verificar» para continuar.'); },
    'timeout-callback'() { failed('La verificación se interrumpió. Pulsa «Volver a verificar» para continuar.'); },
    'error-callback'() { failed('No pudimos completar la verificación. Puedes volver a verificar o recargar la página.'); },
  });
  controls();
}
function verifyAgain() {
  if (!challengeVisible() || verificationPending) return;
  discardChallenge(); verificationNeedsRefresh = false;
  if (!window.turnstile) {
    verificationNeedsRefresh = true; controls();
    showError('No pudimos cargar la verificación. Revisa tu conexión y recarga la página.'); return;
  }
  renderChallenge();
  el.human.scrollIntoView({ block: 'nearest' });
}
function supportsPhoto(file) {
  const type = (file.type || '').trim().toLowerCase();
  // Some file pickers omit HEIC's MIME type. The server validates the bytes;
  // explicit sequence/video MIME types never use the extension fallback.
  return STILL_PHOTO_TYPES.has(type) || ((!type || type === 'application/octet-stream' || type === 'binary/octet-stream') && PHOTO_EXTENSION.test(file.name || ''));
}
function clearSelectedPreview() {
  previewRevision++;
  if (previewProbe) {
    previewProbe.onload = null; previewProbe.onerror = null;
    previewProbe.removeAttribute('src'); previewProbe = null;
  }
  el.preview.hidden = true; el.preview.removeAttribute('src');
  el.previewNote.hidden = true; el.previewNote.textContent = '';
}
function prepareSelectedPreview(file, url) {
  const revision = previewRevision;
  // A separate Image gives each selection its own load/error callbacks.
  // A late event from an older file must never replace the current preview.
  const probe = new Image(); previewProbe = probe;
  const current = () => revision === previewRevision && selectedFile === file && selectedURL === url;
  el.previewNote.textContent = 'Cargando vista previa…'; el.previewNote.hidden = false;
  probe.onload = () => {
    if (!current()) return;
    el.preview.src = url; el.preview.hidden = false; el.previewNote.hidden = true;
    probe.onload = null; probe.onerror = null; previewProbe = null;
  };
  probe.onerror = () => {
    if (!current()) return;
    el.preview.hidden = true; el.preview.removeAttribute('src');
    el.previewNote.textContent = 'Vista previa no disponible; prepararemos tu foto al subirla.';
    el.previewNote.hidden = false;
    probe.onload = null; probe.onerror = null; previewProbe = null;
  };
  probe.src = url;
}
function choosePhoto(file) {
  if (uploading || jobID || deleting) return;
  if (!creationBlocked) showError();
  if (!file) return;
  if (!supportsPhoto(file)) {
    showError('Elige una foto JPG, PNG, WebP o HEIC/HEIF. Este apartado admite fotos, no videos ni secuencias.');
    el.input.value = ''; return;
  }
  if (!file.size || file.size > MAX_FILE_BYTES) {
    showError('Tu foto debe pesar hasta 8 MB. Elige una versión más liviana e inténtalo de nuevo.');
    el.input.value = ''; return;
  }
  clearSelectedPreview();
  if (selectedURL) URL.revokeObjectURL(selectedURL);
  selectedFile = file; selectedURL = URL.createObjectURL(file); requestID = crypto.randomUUID();
  prepareSelectedPreview(file, selectedURL); el.name.textContent = file.name || 'Mi foto';
  el.size.textContent = file.size < 1024 * 1024 ? `${Math.ceil(file.size / 1024)} KB` : `${(file.size / 1024 / 1024).toFixed(1)} MB`;
  el.selected.hidden = false; el.upload.hidden = true;
  controls();
}
function removePhoto() {
  if (uploading || jobID || deleting) return;
  clearSelectedPreview();
  if (selectedURL) URL.revokeObjectURL(selectedURL);
  selectedURL = ''; selectedFile = null; requestID = ''; el.input.value = ''; el.cameraInput.value = '';
  el.selected.hidden = true; el.upload.hidden = false; controls();
}
function responseError(status, body, blocked = false) {
  const error = new Error(blocked
    ? 'La protección de conexión interrumpió la solicitud. Consulta el estado de tu foto antes de volver a enviarla; si continúa, recarga la página.'
    : typeof body?.error === 'string' ? body.error : 'No pudimos completar la operación. Inténtalo de nuevo.');
  error.status = status; error.code = typeof body?.code === 'string' ? body.code : ''; error.blocked = blocked;
  return error;
}
async function responseData(response) {
  const type = response.headers.get('content-type') || '';
  const blocked = response.headers.get('cf-mitigated') === 'challenge' || (!type.includes('application/json') && [403, 503].includes(response.status));
  if (blocked) throw responseError(response.status, null, true);
  const parsed = type.includes('application/json') ? await response.json() : {};
  const data = parsed && typeof parsed === 'object' ? parsed : {};
  if (!response.ok) throw responseError(response.status, data);
  return data;
}
function internalControls() {
  el.internalPanel.hidden = false;
  el.internalPanel.setAttribute('aria-busy', String(internalBusy || resetBusy));
  el.internalOpen.setAttribute('aria-expanded', String(internalMode || el.internalDetails.open));
  el.internalDetails.hidden = internalMode;
  el.internalActive.hidden = !internalMode;
  el.internalCode.disabled = internalBusy || resetBusy || uploading || internalMode || !internalAvailable;
  el.internalSubmit.disabled = internalBusy || resetBusy || uploading || !internalAvailable || internalMode;
  el.internalSubmit.textContent = internalBusy && !internalMode ? 'Activando…' : 'Activar modo interno';
  el.internalExit.disabled = internalBusy || resetBusy || uploading;
  el.internalExit.textContent = internalBusy && internalMode ? 'Cerrando…' : 'Salir del modo interno';
  el.internalReset.disabled = internalBusy || resetBusy || uploading || !internalMode;
  el.internalReset.textContent = resetBusy ? 'Restableciendo…' : resetID ? 'Reintentar restablecimiento' : 'Restablecer creaciones para todos';
  el.internalHelp.textContent = config && !internalAvailable ? 'El acceso interno no está disponible en este momento. Recarga la página para volver a comprobarlo.' : internalHelpText;
}
function openInternalPanel() {
  el.internalPanel.hidden = false;
  el.internalDetails.open = true;
  internalControls();
  const target = internalMode ? el.internalExit : el.internalCode.disabled ? el.internalDetails.querySelector('summary') : el.internalCode;
  target.focus({ preventScroll: true }); el.internalPanel.scrollIntoView({ block: 'nearest' });
}
function internalFeedback(message = '', failed = false) {
  el.internalFeedback.textContent = message; el.internalFeedback.hidden = !message;
  el.internalFeedback.setAttribute('role', failed ? 'alert' : 'status');
  el.internalFeedback.classList.toggle('internal-error', failed);
  if (message) {
    el.internalFeedback.tabIndex = -1; el.internalFeedback.focus({ preventScroll: true });
    el.internalFeedback.scrollIntoView({ block: 'nearest' });
  }
}
function clearDailyBlock() {
  if (!DAILY_LIMIT_CODES.has(creationBlockedCode)) return;
  const quotaNotice = el.error.textContent === creationBlockedMessage;
  creationBlocked = ''; creationBlockedCode = ''; creationBlockedMessage = '';
  if (quotaNotice) showError();
}
async function changeInternalMode(activate) {
  if (internalBusy || resetBusy || uploading || (activate && !internalAvailable)) return;
  let code = activate ? el.internalCode.value : '';
  el.internalCode.value = '';
  if (activate && !code) { internalFeedback('Escribe el código de uso interno para continuar.', true); return; }
  const body = activate ? JSON.stringify({ code }) : undefined;
  code = '';
  const ticket = ++internalRevision;
  const controller = new AbortController(); internalController = controller;
  internalBusy = true; internalFeedback(); internalControls(); controls();
  try {
    const response = await fetch(`${API}?internal=1`, {
      method: activate ? 'POST' : 'DELETE', credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: controller.signal,
      ...(activate ? { headers: { 'Content-Type': 'application/json' }, body } : {}),
    });
    const data = await responseData(response);
    if (ticket !== internalRevision) return;
    if (data.internalMode !== activate) throw new Error('No pudimos confirmar el cambio de modo. Revisa tu conexión e inténtalo de nuevo.');
    internalMode = data.internalMode;
    if (config) config.internalMode = internalMode;
    if (activate) {
      // Unlocking changes only the daily budget. Selection, UUID,
      // captcha and an existing job retain their independent lifecycle.
      clearDailyBlock();
      el.internalDetails.open = false;
    }
    internalControls();
    internalFeedback(activate ? 'Modo interno activado. Puedes continuar con tu foto.' : 'Modo interno cerrado. Se aplican los límites públicos.');
  } catch (error) {
    if (error.name === 'AbortError' || ticket !== internalRevision) return;
    internalFeedback(error.blocked ? 'No pudimos confirmar el acceso interno. Revisa tu conexión y vuelve a intentarlo.' : error.message || 'No pudimos cambiar el modo interno. Inténtalo otra vez.', true);
  } finally {
    el.internalCode.value = '';
    if (ticket === internalRevision) {
      internalBusy = false; if (internalController === controller) internalController = null;
      internalControls(); controls();
    }
  }
}
async function resetCreations() {
  if (!internalMode || internalBusy || resetBusy || uploading) return;
  const question = resetID
    ? '¿Reintentar el mismo restablecimiento pendiente? Las fotos existentes se conservan.'
    : '¿Restablecer las creaciones para todos los dispositivos? Las fotos existentes se conservan.';
  if (!window.confirm(question)) return;
  resetID ||= crypto.randomUUID(); rememberReset(resetID);
  const ticket = ++resetRevision;
  const controller = new AbortController(); resetController = controller;
  resetBusy = true; internalFeedback(); controls();
  try {
    const response = await fetch(`${API}?internal-reset=1`, {
      method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: controller.signal,
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: resetID }),
    });
    const data = await responseData(response);
    if (ticket !== resetRevision) return;
    if (data.reset !== true || !Number.isSafeInteger(data.quotaGeneration) || data.quotaGeneration < 0) throw new Error('No pudimos confirmar el restablecimiento. Reintenta para consultar el mismo intento.');
    if (config) config.quotaGeneration = data.quotaGeneration;
    resetID = ''; rememberReset(''); clearDailyBlock();
    internalFeedback('Creaciones restablecidas para todos. Los demás dispositivos pueden actualizar la página para volver a crear.');
  } catch (error) {
    if (error.name === 'AbortError' || ticket !== resetRevision) return;
    if (error.code === 'internal_required') {
      internalMode = false; if (config) config.internalMode = false; el.internalDetails.open = true;
      internalFeedback('La sesión de uso interno venció. Vuelve a introducir el código para continuar.', true);
    } else {
      internalFeedback(error.blocked || !error.status
        ? 'No pudimos confirmar el restablecimiento. Puedes reintentar el mismo intento sin repetir la operación.'
        : error.message || 'No pudimos restablecer las creaciones. Puedes reintentar el mismo intento.', true);
    }
  } finally {
    if (ticket === resetRevision) {
      resetBusy = false; if (resetController === controller) resetController = null;
      controls();
    }
  }
}
function loadTurnstile() {
  verificationPending = true;
  if (window.turnstile) { renderChallenge(); return; }
  window.jacBirthdayTurnstileReady = renderChallenge;
  const script = document.createElement('script');
  script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=jacBirthdayTurnstileReady&render=explicit';
  script.async = true; script.defer = true;
  script.onerror = () => {
    if (!challengeVisible()) return;
    verificationPending = false; verificationNeedsRefresh = true; controls();
    showError('No pudimos cargar la verificación. Revisa tu conexión y recarga la página.');
  };
  document.head.append(script);
}
async function loadConfig() {
  try {
    const response = await fetch(API, { credentials: 'same-origin', cache: 'no-store', redirect: 'error' });
    config = await responseData(response); serverConfigured = config.enabled === true;
    internalAvailable = config.internalAvailable === true; internalMode = config.internalMode === true;
    internalControls();
    const hours = Number(config.retentionHours);
    if (Number.isFinite(hours) && hours > 0 && hours <= 168) document.querySelectorAll('[data-retention]').forEach(node => { node.textContent = String(hours); });
    el.availability.hidden = serverConfigured;
    if (!serverConfigured) el.availability.textContent = 'Estamos preparando la experiencia. Pronto podrás crear tu foto; mientras tanto, este es el brindis que te espera.';
    if (serverConfigured && config.turnstileSiteKey) loadTurnstile();
  } catch {
    serverConfigured = false; el.availability.hidden = false;
    el.availability.textContent = 'No pudimos conectar con la experiencia. Revisa tu conexión y recarga la página para volver a intentarlo.';
  }
  controls();
}
function pausePolling(message) {
  stopPolling(); el.progressTrack.hidden = true; el.message.textContent = message;
  el.detail.textContent = 'Puedes consultar de nuevo con el botón de abajo. Conservamos tu solicitud y no enviaremos otra generación.';
  el.refresh.hidden = false; controls();
}
function schedulePoll() {
  if (!jobID || !['queued', 'processing'].includes(activeStatus)) return;
  const elapsed = Date.now() - pollStarted;
  if (elapsed >= POLL_DEADLINE) { pausePolling('La imagen está tardando más de lo habitual.'); return; }
  stopPolling(); pollTimer = setTimeout(() => { void readJob(); }, elapsed < 120000 ? 5000 : 10000);
}
async function loadResult(id, ticket) {
  if (resultLoading || resultURL) return;
  resultLoading = true;
  const controller = new AbortController(); requestController = controller;
  try {
    const response = await fetch(`${API}?id=${encodeURIComponent(id)}&image=1`, { credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: controller.signal });
    if (!response.ok) { await responseData(response); return; }
    if (!(response.headers.get('content-type') || '').startsWith('image/png')) throw new Error('La foto no está disponible todavía. Vuelve a consultar tu resultado.');
    const blob = await response.blob();
    if (ticket !== generation || id !== jobID) return;
    if (!blob.size || blob.size > 24 * 1024 * 1024) throw new Error('No pudimos cargar tu imagen. Vuelve a consultar tu resultado.');
    cleanupResult(); resultURL = URL.createObjectURL(blob);
    resultFile = new File([blob], 'Mi-cumpleanos-con-el-Rey.png', { type: 'image/png' });
    el.campaign.src = resultURL; el.campaign.alt = 'Tu foto creada con IA brindando con Jhon Alex en su cumpleaños.';
    el.photoLabel.textContent = 'ESTE BRINDIS ES TUYO'; el.photoCaption.textContent = 'Imagen creada con IA para celebrar con el Rey.';
    el.download.href = resultURL;
    let canShare = false;
    try { canShare = Boolean(navigator.share && navigator.canShare?.({ files: [resultFile] })); } catch { /* Download is always available. */ }
    el.share.hidden = !canShare;
    el.job.hidden = true; el.form.hidden = true; el.result.hidden = false;
    showError(); controls();
  } catch (error) {
    if (error.name === 'AbortError' || ticket !== generation) return;
    pausePolling('Tu foto está lista, pero falta cargarla.'); showError(error.message || 'No pudimos cargar tu foto. Inténtalo otra vez.');
  } finally {
    resultLoading = false; if (requestController === controller) requestController = null;
  }
}
function terminalJob(job) {
  stopPolling(); el.progressTrack.hidden = true;
  const messages = {
    failed: 'No pudimos crear esta foto.',
    uncertain: 'Todavía no pudimos confirmar tu resultado.',
    cancelled: 'Tu solicitud fue cancelada.',
  };
  el.jobTitle.textContent = 'Sobre tu foto';
  el.message.textContent = job.message || messages[job.status] || 'No pudimos continuar con esta solicitud.';
  el.detail.textContent = job.status === 'uncertain'
    ? 'Para evitar repetir la generación, esta solicitud no se enviará de nuevo automáticamente. Puedes borrar tu foto aquí.'
    : 'Puedes borrar esta solicitud y volver a la foto de ejemplo.';
  el.refresh.hidden = true; el.cancel.textContent = 'Borrar mi foto y volver'; controls();
}
async function acceptJob(job, ticket) {
  if (ticket !== generation) return;
  if (!job || !validID(job.id) || job.id !== jobID) throw new Error('No pudimos confirmar tu solicitud. Consulta el estado antes de volver a enviarla.');
  activeStatus = job.status;
  if (job.status === 'ready') {
    stopPolling(); setBusyPanel('Tu brindis está listo', 'Cargando tu foto…', 'En un momento podrás guardarla o compartirla.');
    await loadResult(job.id, ticket); return;
  }
  if (['queued', 'processing'].includes(job.status)) {
    setBusyPanel('Estamos preparando el brindis', job.status === 'queued' ? 'Tu foto está esperando su turno.' : 'Estamos creando tu foto con el Rey.', job.message || 'Puede tardar unos minutos. No necesitas volver a subir tu foto.');
    el.cancel.textContent = 'Cancelar y borrar mi foto'; schedulePoll(); controls(); return;
  }
  terminalJob(job);
}
async function readJob() {
  if (!jobID || uploading || deleting) return;
  stopPolling(); const id = jobID, ticket = generation;
  const controller = new AbortController(); clearRequest(); requestController = controller;
  try {
    const response = await fetch(`${API}?id=${encodeURIComponent(id)}`, { credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: controller.signal });
    const data = await responseData(response);
    if (ticket !== generation || id !== jobID) return;
    if (!data.job) throw new Error('No pudimos consultar tu solicitud. Inténtalo de nuevo.');
    if (requestController === controller) requestController = null;
    await acceptJob(data.job, ticket);
  } catch (error) {
    if (error.name === 'AbortError' || ticket !== generation || id !== jobID) return;
    if (error.blocked) {
      pausePolling('La conexión necesita una comprobación antes de consultar tu foto.'); showError(error.message); return;
    }
    if ([401, 403, 404, 410].includes(error.status)) {
      rememberJob(''); jobID = ''; if (error.status === 410) requestID = ''; activeStatus = ''; el.job.hidden = true; el.result.hidden = true; el.form.hidden = false;
      resetPhotoDisplay(); showError(error.status === 410 ? 'Esta foto ya venció. Puedes crear una nueva cuando quieras.' : 'Esta solicitud ya no está disponible en este navegador. Puedes elegir otra foto.'); controls(); return;
    }
    pausePolling('No pudimos consultar el estado de tu foto.'); showError(error.message || 'Revisa tu conexión e inténtalo otra vez.');
  } finally {
    if (requestController === controller) requestController = null;
  }
}
function upload(data, ticket) {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest(); xhr = request;
    request.open('POST', API); request.responseType = 'json'; request.withCredentials = true; request.timeout = 120000;
    request.upload.addEventListener('progress', event => {
      if (ticket !== generation) return;
      if (event.lengthComputable) {
        const percent = Math.min(100, Math.round(event.loaded * 100 / event.total));
        el.progress.value = percent; el.message.textContent = percent === 100 ? 'Confirmando la subida…' : `Subiendo tu foto · ${percent}%`;
      }
    });
    request.addEventListener('load', () => {
      if (xhr === request) xhr = null;
      const body = request.response;
      const type = request.getResponseHeader('content-type') || '';
      const blocked = request.getResponseHeader('cf-mitigated') === 'challenge' || (!type.includes('application/json') && [403, 503].includes(request.status));
      if (!blocked && request.status >= 200 && request.status < 300 && body?.job) resolve(body.job);
      else reject(responseError(request.status, body, blocked));
    });
    request.addEventListener('error', () => { if (xhr === request) xhr = null; reject(new Error('Se interrumpió la conexión durante la subida.')); });
    request.addEventListener('timeout', () => { if (xhr === request) xhr = null; reject(new Error('La subida tardó más de lo esperado.')); });
    request.addEventListener('abort', () => { if (xhr === request) xhr = null; const error = new Error('Subida cancelada.'); error.name = 'AbortError'; reject(error); });
    request.send(data);
  });
}
async function submitPhoto(event) {
  event.preventDefault();
  if (uploading || deleting || jobID || creationBlocked || internalBusy || resetBusy) return;
  showError();
  if (!serverConfigured) { showError('Estamos preparando la experiencia. Vuelve a visitarnos pronto.'); return; }
  if (!selectedFile) { showError('Primero elige una foto tuya.'); el.input.focus(); return; }
  if (config?.turnstileSiteKey && (!turnstileToken || Date.now() - tokenIssuedAt > VERIFICATION_MAX_AGE)) {
    if (!verificationPending) verifyAgain();
    return;
  }
  const proof = turnstileToken;
  requestID ||= crypto.randomUUID();
  const data = new FormData(); data.append('photo', selectedFile); data.append('id', requestID);
  if (proof) data.append('turnstileToken', proof);
  // A proof is single-use. Stop the widget before hiding its parent; only an
  // explicit later action may request another proof, never an upload callback.
  discardChallenge(); verificationNeedsRefresh = Boolean(config?.turnstileSiteKey);
  generation++; const ticket = generation;
  jobID = requestID; activeStatus = 'queued'; rememberJob(jobID);
  pollStarted = Date.now(); uploading = true;
  setBusyPanel('Tu foto va camino al brindis', 'Subiendo tu foto…', 'Estamos enviando la foto que elegiste de forma privada.');
  el.progress.value = 0; el.progress.setAttribute('aria-label', 'Progreso de la subida de tu foto');
  controls();
  try {
    const job = await upload(data, ticket);
    if (ticket !== generation) return;
    uploading = false; await acceptJob(job, ticket);
  } catch (error) {
    if (ticket !== generation || error.name === 'AbortError') return;
    uploading = false;
    if (error.blocked) {
      pausePolling('La conexión interrumpió la confirmación de tu foto.'); showError(error.message); return;
    }
    if ((error.status >= 400 && error.status < 500 && ![408, 409].includes(error.status)) || VERIFICATION_CODES.has(error.code)) {
      rememberJob(''); jobID = ''; activeStatus = ''; el.job.hidden = true; el.form.hidden = false;
      const internalExpired = DAILY_LIMIT_CODES.has(error.code) && internalMode;
      if (internalExpired) { internalMode = false; if (config) config.internalMode = false; }
      if (DAILY_LIMIT_CODES.has(error.code)) creationBlocked = 'Límite diario alcanzado';
      if (error.code === 'verification_configuration') creationBlocked = 'Creación no disponible';
      if (DAILY_LIMIT_CODES.has(error.code) || error.code === 'verification_configuration') {
        creationBlockedCode = error.code; creationBlockedMessage = error.message;
      }
      showError(error.message); controls();
      if (internalExpired) internalFeedback('La sesión de uso interno venció. Vuelve a introducir el código para continuar.');
      return;
    }
    pausePolling('Vamos a comprobar si tu foto llegó.');
    el.detail.textContent = 'Consulta el estado antes de volver a enviarla. Así conservamos el mismo intento.';
    showError(error.message); void readJob();
  } finally {
    if (ticket === generation) { uploading = false; controls(); }
  }
}
async function deleteJob() {
  if (!jobID || uploading || deleting) return;
  const id = jobID; deleting = true; generation++; stopPolling(); clearRequest(); showError(); controls();
  const controller = new AbortController(); requestController = controller;
  try {
    const response = await fetch(`${API}?id=${encodeURIComponent(id)}`, { method: 'DELETE', credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: controller.signal });
    if (![404, 410].includes(response.status)) await responseData(response);
    rememberJob(''); jobID = ''; requestID = ''; activeStatus = ''; pollStarted = 0;
    el.job.hidden = true; el.result.hidden = true; el.form.hidden = false; resetPhotoDisplay();
    clearSelectedPreview(); selectedFile = null; if (selectedURL) URL.revokeObjectURL(selectedURL); selectedURL = '';
    el.input.value = ''; el.cameraInput.value = ''; el.selected.hidden = true; el.upload.hidden = false;
    discardChallenge(); verificationNeedsRefresh = Boolean(config?.turnstileSiteKey);
    el.availability.hidden = false; el.availability.textContent = 'Tu solicitud se canceló y tus fotos dejaron de estar disponibles.';
    if (!serverConfigured) el.availability.textContent += ' Estamos preparando la experiencia para nuevas fotos.';
  } catch (error) {
    if (error.name !== 'AbortError') { showError('No pudimos confirmar el borrado. Revisa tu conexión y vuelve a pulsar el botón.'); el.refresh.hidden = false; }
  } finally {
    deleting = false; if (requestController === controller) requestController = null; controls();
  }
}
async function sharePhoto() {
  if (!resultFile || !navigator.share) return;
  try { await navigator.share({ files: [resultFile], title: 'Mi foto con el Rey del Chupe', text: 'Ya estoy listo pa celebrar el cumpleaños del Rey del Chupe en el Movistar Arena.' }); }
  catch (error) { if (error.name !== 'AbortError') showError('No pudimos abrir el menú para compartir. Puedes descargar tu foto y enviarla desde tu galería.'); }
}

el.input.addEventListener('change', () => choosePhoto(el.input.files?.[0]));
el.internalOpen.addEventListener('click', openInternalPanel);
el.internalReset.addEventListener('click', () => { void resetCreations(); });
el.internalForm.addEventListener('submit', event => { event.preventDefault(); void changeInternalMode(true); });
el.internalExit.addEventListener('click', () => { void changeInternalMode(false); });
el.internalDetails.addEventListener('toggle', () => { if (!el.internalDetails.open) el.internalCode.value = ''; internalControls(); });
el.camera.hidden = !(navigator.maxTouchPoints > 0 || window.matchMedia('(pointer: coarse)').matches);
el.cameraButton.addEventListener('click', () => { if (!uploading && !deleting && !jobID) el.cameraInput.click(); });
el.cameraInput.addEventListener('change', () => {
  const file = el.cameraInput.files?.[0];
  // Clear the native picker so a retake with the same filename still changes.
  el.cameraInput.value = '';
  if (file) choosePhoto(file);
});
$('change-photo').addEventListener('click', () => { if (!uploading && !jobID) el.input.click(); });
$('remove-photo').addEventListener('click', removePhoto);
el.form.addEventListener('submit', event => { void submitPhoto(event); });
el.cancel.addEventListener('click', () => { void deleteJob(); }); el.delete.addEventListener('click', () => { void deleteJob(); });
el.refresh.addEventListener('click', () => { showError(); pollStarted = Date.now(); void readJob(); });
el.share.addEventListener('click', () => { void sharePhoto(); });
for (const name of ['dragenter', 'dragover']) el.upload.addEventListener(name, event => { event.preventDefault(); if (!el.input.disabled) el.upload.classList.add('dragging'); });
for (const name of ['dragleave', 'drop']) el.upload.addEventListener(name, event => { event.preventDefault(); el.upload.classList.remove('dragging'); });
el.upload.addEventListener('drop', event => {
  if (el.input.disabled) return;
  const files = event.dataTransfer?.files;
  if (files?.length > 1) { showError('Elige una sola foto donde aparezcas tú.'); return; }
  choosePhoto(files?.[0]);
});
window.addEventListener('pagehide', event => {
  resetRevision++; resetController?.abort(); resetController = null; resetBusy = false;
  internalRevision++; internalController?.abort(); internalController = null; internalBusy = false;
  el.internalCode.value = ''; internalControls(); controls();
  stopPolling(); clearRequest();
  if (!event.persisted) { xhr?.abort(); clearSelectedPreview(); if (selectedURL) URL.revokeObjectURL(selectedURL); cleanupResult(); }
});
window.addEventListener('pageshow', event => {
  if (event.persisted && jobID && !uploading && !deleting && !resultURL) { pollStarted = Date.now(); void readJob(); }
});

const internalRequested = new URLSearchParams(location.search).get('interno') === '1' || location.hash === '#internal-panel';
resetID = storedReset(); if (!validID(resetID)) { resetID = ''; rememberReset(''); }
if (internalRequested) openInternalPanel();
await loadConfig();
if (internalRequested) openInternalPanel();
const resumed = storedJob() || config?.activeJobId || '';
if (validID(resumed)) {
  discardChallenge(); verificationNeedsRefresh = Boolean(config?.turnstileSiteKey);
  jobID = resumed; requestID = resumed; pollStarted = Date.now();
  setBusyPanel('Recuperando tu brindis', 'Consultando tu foto…', 'Buscamos la solicitud que dejaste en este navegador.');
  controls(); await readJob();
} else rememberJob('');
