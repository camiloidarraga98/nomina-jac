'use strict';
const $ = (id) => document.getElementById(id);
const bridge = window.webkit?.messageHandlers?.teamAttendance;
const native = (action, values = {}) => bridge.postMessage({ action, ...values });
const zone = 'America/Bogota';
const when = (time) =>
  new Intl.DateTimeFormat('es-CO', { timeZone: zone, dateStyle: 'medium', timeStyle: 'short' }).format(
    new Date(time)
  );
const id = () => crypto.randomUUID();
function el(tag, label) {
  const node = document.createElement(tag);
  node.textContent = label;
  return node;
}
function button(label, action) {
  const node = el('button', label);
  node.type = 'button';
  node.onclick = () => run(action);
  return node;
}
function confirmAction(title, detail, confirmLabel = 'Confirmar') {
  const dialog = $('confirmation');
  $('question').textContent = title;
  $('explain').textContent = detail;
  $('confirmAction').textContent = confirmLabel;
  dialog.returnValue = 'cancel';
  dialog.showModal();
  return new Promise((resolve) =>
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'yes'), { once: true })
  );
}
async function api(payload, params = {}) {
  if (bridge) return native('admin', { payload: payload || null, params });
  const response = await fetch(
    '/api/team-attendance/admin?' + new URLSearchParams(params),
    payload
      ? {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
          cache: 'no-store'
        }
      : { cache: 'no-store' }
  );
  const result = await response.json();
  if (!response.ok) {
    if ([401, 403].includes(response.status)) {
      if ($('photoDialog').open) $('photoDialog').close();
      for (const key of ['rows', 'peopleList', 'deviceList', 'filter', 'revisions', 'original'])
        $(key).replaceChildren();
      $('manual').elements.employee.replaceChildren();
      people = [];
      if ($('review').open) $('review').close();
    }
    throw Error(result.error || 'No se pudo consultar Asistencia.');
  }
  return result;
}
let people = [],
  cursor = null,
  devInfo = {},
  writing = false,
  refreshID = 0,
  tab = 'history';
function message(value) {
  return value?.message || String(value || 'No se pudo completar la operación.');
}
async function run(action) {
  if (writing) return;
  writing = true;
  try {
    await action();
  } catch (e) {
    $('notice').textContent = message(e);
  } finally {
    writing = false;
  }
}
function fill(select, items, placeholder, former = []) {
  const previous = select.value;
  const option = (p) => new Option(p.name + ' · ' + p.code, p.id);
  select.replaceChildren(new Option(placeholder, ''), ...items.map(option));
  if (former.length) {
    const group = document.createElement('optgroup');
    group.label = 'Personal eliminado';
    group.append(...former.map(option));
    select.append(group);
  }
  if (Array.from(select.options).some((o) => o.value === previous)) select.value = previous;
}
function line(title, detail) {
  const wrap = el('div', ''),
    description = el('div', ''),
    actions = el('div', '');
  wrap.className = 'item';
  actions.className = 'item-actions';
  description.append(el('strong', title), el('small', detail));
  wrap.append(description, actions);
  return { wrap, actions };
}
function drawRoster(feed) {
  people = feed.people;
  fill($('filter'), people, 'Todo el equipo', feed.formerPeople);
  fill(
    $('manual').elements.employee,
    people.filter((p) => p.active),
    'Selecciona un empleado'
  );
  $('peopleList').replaceChildren();
  $('deviceList').replaceChildren();
  if (!people.length) $('peopleList').append(el('p', 'Agrega al primer empleado para empezar.'));
  for (const p of people) {
    const item = line(p.name, p.code + (p.active ? '' : ' · Inactivo'));
    if (p.active) {
      if (bridge && devInfo.paired && !devInfo.revoked && !devInfo.unavailable) {
        const enrolled = devInfo.enrolled?.includes(p.id);
        item.actions.append(
          button(enrolled ? 'Verificar perfil' : 'Inscribir rostro', async () => {
            if (enrolled) {
              const result = await native('verify', { employee: p.id });
              $('notice').textContent = result.message;
              return;
            }
            if (
              !(await confirmAction(
                'Inscribir a ' + p.name,
                'Comprueba presencialmente que esta persona corresponde a la ficha ' +
                  p.code +
                  ' y que acepta la verificación facial y la foto que se guarda con cada marcación.'
              ))
            )
              return;
            await native('enroll', { employee: p.id });
            await load();
            $('notice').textContent = 'Rostro inscrito en este dispositivo.';
          })
        );
      }
      item.actions.append(
        button('Retirar rostro', async () => {
          if (
            await confirmAction(
              'Retirar el rostro de ' + p.name,
              'Esto invalida sus inscripciones en todos los kioscos. Podrás volver a inscribirlo en persona.'
            )
          ) {
            await api({ action: 'resetFace', employee: p.id, revision: p.revision });
            await load();
          }
        }),
        button('Desactivar', async () => {
          if (
            await confirmAction(
              'Desactivar a ' + p.name,
              'El historial se conserva en JAC. La persona dejará de poder marcar.'
            )
          ) {
            await api({ action: 'archive', employee: p.id, revision: p.revision });
            await load();
          }
        })
      );
    }
    const remove = button('Eliminar empleado', async () => {
      const confirmed = await confirmAction(
        '¿Eliminar a ' + p.name + ' de Asistencia?',
        'La ficha ' + p.code + ' se retirará de Personal y de los kioscos. Sus entradas, salidas y fotos anteriores seguirán en Marcaciones.',
        'Eliminar empleado'
      );
      if (!confirmed) return;
      const result = await api({ action: 'removePerson', employee: p.id, revision: p.revision });
      await reload();
      $('notice').textContent = p.name + ' se eliminó de Personal.' +
        (result.outcome === 'history' ? ' Puedes consultar su historial en Marcaciones.' : '');
    });
    remove.className = 'delete-person';
    item.actions.append(remove);
    $('peopleList').append(item.wrap);
  }
  $('pair').hidden = !bridge || devInfo.paired;
  if (!feed.devices.length) $('deviceList').append(el('p', 'Aún no hay kioscos vinculados.'));
  for (const d of feed.devices) {
    const item = line(d.name, d.active ? 'Habilitado' : 'Desactivado');
    if (d.active)
      item.actions.append(
        button('Desactivar kiosco', async () => {
          if (
            await confirmAction(
              'Desactivar ' + d.name,
              'El servidor dejará de recibir marcaciones de este dispositivo.'
            )
          ) {
            await api({ action: 'revoke', id: d.id });
            await load();
          }
        })
      );
    $('deviceList').append(item.wrap);
  }
}
async function load(older = false) {
  const ticket = ++refreshID;
  const feed = await api(null, {
    employee: $('filter').value,
    day: $('day').value,
    cursor: older ? cursor || '' : ''
  });
  if (ticket !== refreshID) return;
  let info = {};
  if (bridge) info = await native('info');
  if (ticket !== refreshID) return;
  devInfo = info;
  drawRoster(feed);
  if (!older) $('rows').replaceChildren();
  for (const r of feed.records) {
    const tr = el('tr', ''),
      person = el('td', r.employeeName),
      date = el('td', when(r.occurredAt)),
      source = el('td', r.deviceName || 'Supervisión presencial');
    person.append(el('small', r.code));
    date.append(el('small', 'Recibido ' + when(r.receivedAt)));
    source.append(el('small', r.deviceName ? 'Comparación en el kiosco' : r.supervisor + ' · ' + r.reason));
    const review = button(r.revision ? 'Ver revisión' : 'Revisar', () => openReview(r));
    review.className = 'review-link';
    if (r.hasPhoto) {
      const photo = button('Ver foto', () => openPhoto(r));
      photo.className = 'review-link';
      source.append(photo);
    }
    source.append(review);
    if (Math.abs(new Date(r.originalTime) - new Date(r.receivedAt)) > 300000)
      date.append(el('small', 'Hora de recepción distinta'));
    if (r.possibleDuplicate) source.append(el('small', 'Revisar posible duplicado'));
    tr.append(person, el('td', r.movement === 'entry' ? 'Entrada' : 'Salida'), date, source);
    $('rows').append(tr);
  }
  cursor = feed.nextCursor;
  $('more').hidden = !cursor;
  $('empty').textContent = $('rows').childElementCount ? '' : 'No hay marcaciones para esta consulta.';
}
let selectedRecord, reviewDraft;
let photoRequest = 0, photoURL;
function clearPhoto() {
  ++photoRequest;
  $('punchPhoto').hidden = true;
  $('punchPhoto').removeAttribute('src');
  if (photoURL) URL.revokeObjectURL(photoURL);
  photoURL = null;
  $('photoRecord').textContent = '';
  $('photoStatus').textContent = '';
}
async function openPhoto(record) {
  clearPhoto();
  const request = photoRequest, dialog = $('photoDialog');
  $('photoRecord').textContent = [record.employeeName, record.originalMovement === 'entry' ? 'Entrada' : 'Salida', when(record.originalTime)].join(' · ');
  $('photoStatus').textContent = 'Cargando foto…';
  dialog.showModal();
  try {
    const result = await api(null, { photo: record.id });
    if (request !== photoRequest || !dialog.open || document.hidden) return;
    const bytes = Uint8Array.from(atob(result.jpeg), (c) => c.charCodeAt(0));
    photoURL = URL.createObjectURL(new Blob([bytes], { type: 'image/jpeg' }));
    $('punchPhoto').src = photoURL;
    $('punchPhoto').hidden = false;
    $('photoStatus').textContent = '';
  } catch (e) {
    if (request === photoRequest && dialog.open) $('photoStatus').textContent = message(e);
  }
}
async function openReview(record) {
  const audit = await api(null, { record: record.id });
  selectedRecord = record;
  reviewDraft = null;
  const form = $('reviewForm');
  form.elements.movement.value = record.movement;
  form.elements.date.value = new Date(new Date(record.occurredAt).getTime() - 5 * 3600000)
    .toISOString()
    .slice(0, 19);
  form.elements.reason.value = '';
  $('original').textContent =
    record.employeeName +
    ' · Original: ' +
    (record.originalMovement === 'entry' ? 'Entrada' : 'Salida') +
    ' · ' +
    when(record.originalTime);
  $('revisions').replaceChildren(
    ...audit.reviews.map((r) =>
      el(
        'li',
        r.reviewer +
          ' · ' +
          (r.movement === 'entry' ? 'Entrada' : 'Salida') +
          ' · ' +
          when(r.occurredAt) +
          ' · ' +
          r.reason
      )
    )
  );
  $('review').showModal();
}
let paged = false;
function reload() {
  paged = false;
  return load();
}
function formHandler(form, action) {
  form.onsubmit = (e) => {
    e.preventDefault();
    run(async () => {
      const submit = e.submitter;
      submit.disabled = true;
      try {
        await action(Object.fromEntries(new FormData(form)));
      } finally {
        submit.disabled = false;
      }
    });
  };
}
function startAdmin() {
  $('admin').hidden = false;
  $('photoDialog').addEventListener('close', clearPhoto);
  const dismissPhoto = () => { if ($('photoDialog').open) $('photoDialog').close(); };
  window.addEventListener('pagehide', dismissPhoto);
  document.addEventListener('visibilitychange', () => { if (document.hidden) dismissPhoto(); });
  $('settings').hidden = !!bridge;
  for (const b of document.querySelectorAll('[data-tab]'))
    b.onclick = () => {
      tab = b.dataset.tab;
      for (const o of document.querySelectorAll('[data-tab]')) {
        o.setAttribute('aria-pressed', o === b);
        $(o.dataset.tab).hidden = o !== b;
      }
      run(reload);
    };
  $('refresh').onclick = () => run(reload);
  $('more').onclick = () =>
    run(async () => {
      await load(true);
      paged = true;
    });
  for (const input of [$('day'), $('filter')]) input.onchange = () => run(reload);
  $('closeReview').onclick = () => $('review').close();
  formHandler($('reviewForm'), async (v) => {
    const timestamp = new Date(v.date + '-05:00').toISOString(),
      key = JSON.stringify(v);
    if (reviewDraft?.key !== key)
      reviewDraft = {
        key,
        payload: {
          action: 'review',
          id: id(),
          record: selectedRecord.id,
          revision: selectedRecord.revision,
          movement: v.movement,
          occurredAt: timestamp,
          reason: v.reason
        }
      };
    try {
      await api(reviewDraft.payload);
    } finally {
      $('review').close();
    }
    await reload();
    $('notice').textContent = 'Revisión guardada con el registro original.';
  });
  formHandler($('add'), async (values) => {
    await api({ action: 'person', id: id(), ...values });
    $('add').reset();
    await reload();
    $('notice').textContent = 'Empleado guardado en JAC.';
  });
  formHandler($('pair'), async (values) => {
    await native('pair', { name: values.name });
    await reload();
    $('notice').textContent = 'Kiosco habilitado. Inscribe los rostros desde Personal.';
  });
  let manualDraft = null;
  formHandler($('manual'), async (values) => {
    if (
      !(await confirmAction(
        'Confirmar supervisión presencial',
        'Verifica personalmente la identidad. La marcación quedará firmada con tu cuenta administradora.'
      ))
    )
      return;
    const key = JSON.stringify(values);
    if (manualDraft?.key !== key)
      manualDraft = {
        key,
        payload: { action: 'manual', id: id(), occurredAt: new Date().toISOString(), ...values }
      };
    await api(manualDraft.payload);
    manualDraft = null;
    $('manual').reset();
    await reload();
    $('notice').textContent = 'Marcación recibida por JAC.';
  });
  run(reload);
  setInterval(() => {
    if (
      !document.hidden &&
      tab === 'history' &&
      !paged &&
      !writing &&
      !$('confirmation').open &&
      !$('review').open
    )
      run(reload);
  }, 20000);
}
let move = 'entry',
  scanning = false,
  canMark = false,
  resetTimer,
  statusBusy = false;
const term = () => (move === 'entry' ? 'entrada' : 'salida');
const scanInstruction = $('scanHelp').textContent;
function outcome(title, detail, person = '') {
  clearTimeout(resetTimer);
  $('home').hidden = true;
  $('outcome').hidden = false;
  $('outTitle').textContent = title;
  $('outDetail').textContent = detail;
  $('outName').textContent = person;
  resetTimer = setTimeout(home, 16000);
}
function home() {
  clearTimeout(resetTimer);
  $('claim').open = false;
  $('claimCode').value = '';
  $('home').hidden = false;
  $('outcome').hidden = true;
  $('outName').textContent = '';
}
function clock() {
  const now = new Date(),
    parts = new Intl.DateTimeFormat('es-CO', {
      timeZone: zone,
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    }).formatToParts(now);
  $('clock').textContent = parts
    .filter((x) => ['hour', 'minute'].includes(x.type))
    .map((x) => x.value)
    .join(':');
  $('period').textContent = parts.find((x) => x.type === 'dayPeriod')?.value || '';
  $('date').textContent = new Intl.DateTimeFormat('es-CO', {
    timeZone: zone,
    weekday: 'long',
    day: 'numeric',
    month: 'long'
  }).format(now);
}
async function kioskStatus() {
  if (statusBusy || scanning || document.hidden) return;
  statusBusy = true;
  try {
    const s = await native('status');
    canMark = s.paired === true;
    if (!canMark) {
      $('connection').textContent = 'Por habilitar';
      $('connection').className = '';
      $('scanHelp').textContent =
        'Para habilitar este dispositivo, toca Salir y entra con tu cuenta administradora a Gestión → Asistencia → Kioscos.';
      $('delivery').textContent = '';
      return;
    }
    $('scanHelp').textContent = scanInstruction;
    $('connection').textContent = s.online ? 'En línea' : 'Sin conexión';
    $('connection').className = s.online ? 'online' : '';
    $('device').textContent = s.name;
    $('delivery').textContent = s.warning || (s.pending ? s.pending + ' por enviar al servidor' : '');
  } catch (e) {
    canMark = false;
    $('connection').textContent = 'Kiosco no disponible';
    $('connection').className = '';
    $('delivery').textContent = message(e);
  } finally {
    $('scan').disabled = !canMark || scanning;
    statusBusy = false;
  }
}
function startKiosk() {
  $('kiosk').hidden = false;
  clock();
  setInterval(clock, 15000);
  kioskStatus();
  setInterval(kioskStatus, 15000);
  for (const b of document.querySelectorAll('[data-move]'))
    b.onclick = () => {
      if (scanning) return;
      move = b.dataset.move;
      for (const other of document.querySelectorAll('[data-move]'))
        other.setAttribute('aria-pressed', b === other);
      $('scanLabel').textContent = 'Escanear para marcar ' + term();
    };
  $('scan').onclick = async () => {
    if (scanning || !canMark) return;
    scanning = true;
    $('scan').disabled = true;
    try {
      const code = $('claim').open ? $('claimCode').value.trim() : '';
      if ($('claim').open && !code)
        throw Error(
          'Escribe tu código o cierra la verificación por código para usar la identificación automática.'
        );
      const result = await native('mark', { movement: move, code });
      $('claimCode').value = '';
      $('claim').open = false;
      outcome(
        result.received ? 'Marcación recibida' : 'Pendiente de envío',
        term() +
          ' · ' +
          when(result.occurredAt) +
          (result.received ? '' : ' · El iPad volverá a intentar el envío.'),
        result.greeting
      );
    } catch (e) {
      const detail = message(e);
      outcome(detail.includes('Perfil incorrecto') ? 'Perfil incorrecto' : 'Marcación sin confirmar', detail);
    } finally {
      scanning = false;
      $('scan').disabled = !canMark;
      kioskStatus();
    }
  };
  $('back').onclick = home;
  $('help').onclick = () =>
    outcome(
      'Supervisión presencial',
      'Pide al administrador que verifique tu identidad y registre el movimiento desde Asistencia.'
    );
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      home();
    } else {
      kioskStatus();
    }
  });
}
(async () => {
  if (!bridge) return startAdmin();
  const mode = await native('mode');
  if (mode === 'kiosk') return startKiosk();
  if (mode === 'admin') return startAdmin();
  throw Error('Vuelve a iniciar sesión en Asistencia.');
})().catch((e) => {
  $('accessError').textContent = message(e);
  $('accessError').hidden = false;
});
