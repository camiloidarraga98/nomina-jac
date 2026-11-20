'use strict';

(() => {
  const $ = id => document.getElementById(id),
    native = window.AttendanceStorage.native,
    bio = window.AttendanceBiometrics;
  let identity = null,
    roster = [],
    ticket = null,
    grantTimer,
    refreshTimer,
    retryTimer, opening,
    syncing = false,
    saving = false,
    device,
    management = null,
    generation = 0;
  const labelMove = value => value === 'entry' ? 'Entrada' : 'Salida';
  const localDate = value => new Date(value).toLocaleString('es-CO', {
    dateStyle: 'short',
    timeStyle: 'medium'
  });
  const dataStore = (op, key, value) => window.AttendanceStorage.access(identity.id, op, key, value);
  const say = text => {
    $('message').textContent = text;
  };
  const el = (tag, text, cls) => {
    const n = document.createElement(tag);
    n.textContent = text;
    if (cls) n.className = cls;
    return n;
  };
  function button(title, action) {
    const b = el('button', title);
    b.type = 'button';
    b.onclick = () => task(action, b);
    return b;
  }
  async function task(action, b) {
    if (b) b.disabled = true;
    try {
      await action();
    } catch (error) {
      say(error.message || 'Revisa la conexión.');
    } finally {
      if (b) b.disabled = false;
    }
  }
  function stopGrant() {
    clearTimeout(grantTimer);
    ticket = null;
    management = null;
    $('peopleList').replaceChildren();
    $('punchList').replaceChildren();
    $('unlock').reset();
  }
  function screen(name) {
    for (const mode of ['kiosk', 'unlock', 'management']) $(mode).hidden = mode !== name;
    $('title').textContent = name === 'management' ? 'Gestión de asistencia' : 'Registro de asistencia';
    $('operator').hidden = name !== 'kiosk';
    $('lock').hidden = name !== 'management';
    $('logout').hidden = !identity;
  }
  function clearPrivate() {
    generation++;
    clearTimeout(retryTimer);
    clearInterval(refreshTimer);
    stopGrant();
    identity = null;
    roster = [];
    $('recent').replaceChildren();
    $('employee').replaceChildren();
    screen(null);
  }
  const hint = window.AttendanceStorage.activeAccount;
  function sameAccount() {
    return !!identity && (native || hint() === identity.id);
  }
  async function api(command, body, operator = false) {
    const method = body === undefined ? 'GET' : 'POST',
      g = generation;
    let status, data;
    if (native) {
      const r = await native.postMessage({
        action: 'api',
        command,
        method,
        ...(body === undefined ? {} : {body}),
        ticket: operator ? ticket?.ticket || '' : ''
      });
      status = r.status;
      data = r.data;
    } else {
      const r = await fetch('/api/attendance/' + command, {
        method,
        cache: 'no-store',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          ...(operator && ticket ? {
            'X-Attendance-Operator': ticket.ticket
          } : {})
        },
        ...(body === undefined ? {} : {
          body: JSON.stringify(body)
        })
      });
      status = r.status;
      data = await r.json();
    }
    if (g !== generation) throw Error('Cambió la sesión.');
    if (status < 200 || status >= 300) {
      if (status === 401 || status === 403 && command === 'session') {
        clearPrivate();
        $('connection').textContent = 'Sesión cerrada';
      }
      if (status === 403 && operator) {
        stopGrant();
        screen('kiosk');
      }
      throw Object.assign(Error(data.error || 'El servicio no está disponible.'), {
        status
      });
    }
    return data;
  }
  async function boot() {
    let profile;
    try {
      profile = await api('session');
      $('connection').textContent = 'Conectado';
    } catch (e) {
      if (e.status && e.status < 500) {
        say(e.message);
        return;
      }
      const account = native ? await native.postMessage({
        action: 'account'
      }) : hint();
      if (account) profile = await window.AttendanceStorage.access(account, 'read', 'profile');
      if (!profile) {
        $('connection').textContent = 'Sin conexión';
        say(native && e.message ? 'No se pudo cargar la sesión de Asistencia. ' + e.message : 'Conecta este dispositivo e inicia sesión para preparar el kiosco.');
        return;
      }
      $('connection').textContent = 'Sin conexión';
    }
    if (profile.role !== 'kiosk' || (!native && hint() !== profile.id)) {
      clearPrivate();
      say('Vuelve a iniciar sesión en JAC.');
      return;
    }
    identity = {
      id: profile.id,
      name: profile.name,
      role: profile.role
    };
    await dataStore('write', 'profile', profile);
    device = await dataStore('device', 'device', crypto.randomUUID());
    roster = profile.people;
    for (const sample of await dataStore('list', 'sample/')) {
      if (sample.expires <= Date.now() || !roster.some(p => p.id === sample.employee)) await bio.remove(dataStore, sample.employee);
    }
    renderRoster();
    screen('kiosk');
    await recent();
    await sync();
    refreshTimer = setInterval(() => {
      if (!document.hidden && identity) void refresh().catch(() => {});
    }, 30000);
  }
  function renderRoster() {
    const selected = $('employee').value;
    $('employee').replaceChildren(new Option('Selecciona un empleado', ''), ...roster.map(p => new Option(p.code + ' · ' + p.name, p.id)));
    if (roster.some(p => p.id === selected)) $('employee').value = selected;
  }
  async function refresh() {
    // Foreground and online events also fire while the first session GET is
    // pending in WebKit. There is no earlier identity to invalidate then.
    if (!identity) return;
    if (!sameAccount()) {
      clearPrivate();
      return;
    }
    try {
      const p = await api('session');
      if (p.id !== identity.id) {
        clearPrivate();
        return;
      }
      roster = p.people;
      await dataStore('write', 'profile', p);
      renderRoster();
      $('connection').textContent = 'Conectado';
      await sync();
    } catch (e) {
      if (identity) $('connection').textContent = e.status ? 'Servicio no disponible' : 'Sin conexión';
    }
  }
  async function recent() {
    if (!identity) return;
    const rows = (await dataStore('list', 'punch/')).sort((a, b) => b.device_time.localeCompare(a.device_time));
    const list = $('recent');
    list.replaceChildren();
    for (const p of rows.slice(0, 12)) {
      const li = document.createElement('li');
      li.append(el('strong', labelMove(p.movement) + ' · ' + (roster.find(e => e.id === p.employee)?.name || p.personName)));
      li.append(el('small', localDate(p.device_time)));
      const msg = p.delivery === 'blocked' ? 'Bloqueada · ' + p.error : p.received_at ? p.state === 'approved' ? 'Recibida · supervisión aprobada' : 'Recibida · supervisión pendiente' : 'Guardada en este dispositivo · por enviar';
      li.append(el('span', msg, p.delivery === 'blocked' ? 'warning' : p.state === 'approved' ? 'ok' : 'muted'));
      list.append(li);
    }
    if (!rows.length) list.append(el('li', 'Aún no hay marcaciones en este dispositivo.', 'muted'));
  }
  async function sync(force = false) {
    if (syncing || !sameAccount()) return;
    syncing = true;
    clearTimeout(retryTimer);
    const account = identity.id,
      store = (op, k, v) => window.AttendanceStorage.access(account, op, k, v);
    let next = Infinity;
    try {
      const rows = await store('list', 'punch/');
      for (const p of rows) {
        if (identity?.id !== account || !sameAccount()) break;
        if (p.delivery === 'blocked') continue;
        // Received entries are read together below.
        if (p.received_at) continue;
        if (!force && p.next > Date.now()) {
          next = Math.min(next, p.next);
          continue;
        }
        const {
          id,
          employee,
          device,
          movement,
          device_time,
          method
        } = p;
        try {
          const ack = await api('punch', {
            account,
            id,
            employee,
            device,
            movement,
            device_time,
            method
          });
          if (ack.id !== id || !ack.received_at) throw Error('Confirmación incompleta.');
          Object.assign(p, ack, {
            delivery: 'received',
            attempts: 0,
            next: 0
          });
          $('connection').textContent = 'Conectado';
        } catch (e) {
          if (e.status === 401 || identity?.id !== account) break;
          if (e.status >= 400 && e.status < 500 && e.status !== 429) {
            p.delivery = 'blocked';
            p.error = e.message;
          } else {
            p.attempts = (p.attempts || 0) + 1;
            p.next = Date.now() + Math.min(120000, 2000 * 2 ** Math.min(8, p.attempts - 1));
            next = Math.min(next, p.next);
            $('connection').textContent = 'Por sincronizar';
          }
        }
        await store('write', 'punch/' + id, p);
      }
      if (sameAccount() && identity.id === account) {
        const known = rows.filter(p => p.received_at).sort((a, b) => b.device_time.localeCompare(a.device_time)).slice(0, 12);
        if (known.length) {
          try {
            const reply = await api('status', {
              ids: known.map(p => p.id)
            });
            for (const state of reply.records) {
              const p = known.find(p => p.id === state.id);
              if (p && p.state !== state.state) await store('write', 'punch/' + p.id, {
                ...p,
                state: state.state
              });
            }
          } catch {/* A lost status read preserves the acknowledged receipt. */}
        }
      }
    } finally {
      syncing = false;
      if (identity?.id === account) {
        await recent();
        if (Number.isFinite(next)) retryTimer = setTimeout(() => void sync(), Math.max(100, next - Date.now()));
      }
    }
  }
  $('punchForm').onsubmit = e => {
    e.preventDefault();
    if (saving || !sameAccount()) return;
    saving = true;
    $('punch').disabled = true;
    void task(async () => {
      const employee = $('employee').value,
        person = roster.find(p => p.id === employee);
      if (!person) throw Error('Selecciona un empleado activo.');
      const movement = new FormData($('punchForm')).get('movement');
      const method = await bio.verify(dataStore, employee, $('method').value);
      const id = crypto.randomUUID(),
        row = {
          id,
          employee,
          device,
          movement,
          device_time: new Date().toISOString(),
          method,
          personName: person.name,
          delivery: 'local',
          next: 0
        };
      const inserted = await dataStore('enqueue', 'punch/' + id, row);
      if (!inserted) {
        say('La marcación ya quedó en la cola del dispositivo.');
        return;
      }
      $('employee').value = '';
      say(method === 'simulation_failed' ? 'Fallo de la simulación. Marcación guardada para revisión humana.' : 'Marcación guardada para supervisión.');
      await recent();
      await sync();
    }).finally(() => {
      saving = false;
      $('punch').disabled = false;
    });
  };
  $('method').onchange = () => {
    $('methodInfo').textContent = $('method').value === 'supervised' ? 'El operador revisará la marcación antes de aprobarla.' : 'Datos sintéticos. La verificación facial real está bloqueada.';
  };
  $('operator').onclick = () => {
    say('');
    screen('unlock');
    $('unlock').elements.password.focus();
  };
  $('cancel').onclick = () => {
    stopGrant();
    screen('kiosk');
  };
  async function lock() {
    const previous = ticket;
    try {
      if (previous) await api('lock', {}, true);
    } finally {
      stopGrant();
      screen('kiosk');
      say('');
      await refresh();
    }
  }
  $('lock').onclick = () => task(lock);
  async function loadManagement() {
    management = await api('management', {}, true);
    await drawManagement();
  }
  $('unlock').onsubmit = e => {
    e.preventDefault();
    void task(async () => {
      const f = e.target.elements,
        pass = f.password.value;
      f.password.value = '';
      ticket = await api('unlock', {
        password: pass
      });
      grantTimer = setTimeout(() => {
        stopGrant();
        screen('kiosk');
        say('La sesión del operador venció.');
      }, Math.max(0, Date.parse(ticket.expires) - Date.now()));
      await loadManagement();
      screen('management');
      say('');
    }, e.submitter);
  };
  function tab(people) {
    $('showPunches').setAttribute('aria-pressed', String(!people));
    $('showPeople').setAttribute('aria-pressed', String(people));
    $('managePunches').hidden = people;
    $('managePeople').hidden = !people;
  }
  $('showPeople').onclick = () => tab(true);
  $('showPunches').onclick = () => tab(false);
  async function drawManagement() {
    const snapshot = management,
      activeTicket = ticket;
    const people = [],
      punches = [];
    for (const p of snapshot.people) {
      const li = el('li', '');
      li.append(el('strong', p.code + ' · ' + p.name));
      const enrolled = await bio.enrolled(dataStore, p.id);
      li.append(el('small', p.active ? enrolled ? 'Muestra sintética local · caduca en 24 h' : 'Sin muestra sintética' : 'Inactivo'));
      if (p.active) {
        const actions = el('div', '', 'actions');
        actions.append(button(enrolled ? 'Borrar muestra' : 'Enrolar muestra sintética', async () => {
          await api('enrollment-access', {
            employee: p.id,
            action: enrolled ? 'remove' : 'enroll'
          }, true);
          if (activeTicket !== ticket) return;
          if (enrolled) await bio.remove(dataStore, p.id);else await bio.enroll(dataStore, p.id);
          await loadManagement();
        }), button('Retirar empleado', async () => {
          if (!confirm('¿Retirar a ' + p.name + '? Se conservará cualquier marcación.')) return;
          const res = await api('retire', {
            id: p.id,
            revision: p.revision
          }, true);
          await bio.remove(dataStore, p.id);
          say(res.status === 'inactive' ? 'Empleado desactivado con su historial.' : 'Empleado eliminado.');
          await loadManagement();
          await refresh();
        }));
        li.append(actions);
      }
      people.push(li);
    }
    for (const p of snapshot.punches) {
      const row = el('article', '', 'review');
      row.append(el('strong', labelMove(p.effective_movement) + ' · ' + p.name), el('small', 'Dispositivo ' + localDate(p.effective_time) + ' · Recepción ' + localDate(p.received_at)), el('span', p.review_state === 'approved' ? 'Supervisión presencial aprobada' : 'Pendiente de revisión humana', p.review_state === 'approved' ? 'ok' : 'warning'));
      if (p.method === 'simulation_failed') row.append(el('small', 'Falló la simulación sintética.', 'warning'));
      if (p.possible_duplicate || p.clock_difference) row.append(el('small', [p.possible_duplicate ? 'Posible duplicado' : '', p.clock_difference ? 'Revisar diferencia de reloj o envío tardío' : ''].filter(Boolean).join(' · '), 'warning'));
      const detail = el('details', ''),
        summary = el('summary', 'Original e historial');
      detail.append(summary, el('p', labelMove(p.movement) + ' · ' + localDate(p.device_time) + ' · ' + {
        supervised: 'Supervisión solicitada',
        simulation: 'Simulación sintética',
        simulation_failed: 'Simulación fallida'
      }[p.method]));
      for (const a of snapshot.audit.filter(a => a.punch === p.id)) detail.append(el('p', 'Rev. ' + a.revision + ' · ' + (a.action === 'approve' ? 'Aprobación' : 'Corrección') + ' · ' + a.operator_name + ' · ' + localDate(a.recorded_at) + ' · ' + labelMove(a.movement) + ' ' + localDate(a.device_time) + ' · ' + a.reason));
      row.append(detail);
      const controls = el('div', '', 'actions');
      if (p.review_state !== 'approved') controls.append(button('Supervisar', () => reviewForm(row, p, 'approve')));
      controls.append(button('Corregir', () => reviewForm(row, p, 'correct')));
      row.append(controls);
      punches.push(row);
    }
    if (ticket !== activeTicket || !ticket) return;
    $('peopleList').replaceChildren(...(people.length ? people : [el('li', 'Crea empleados ficticios para iniciar la prueba.', 'muted')]));
    $('punchList').replaceChildren(...(punches.length ? punches : [el('p', 'Las marcaciones recibidas aparecerán aquí.', 'muted')]));
  }
  function reviewForm(row, p, action) {
    row.querySelector('form')?.remove();
    const form = el('form', ''),
      move = el('select', ''),
      time = el('input', '');
    const input = (text, node) => {
      const label = el('label', text);
      label.append(node);
      form.append(label);
    };
    const reason = el('input', '');
    reason.required = true;
    reason.minLength = 3;
    reason.maxLength = 400;
    if (action === 'correct') {
      move.append(new Option('Entrada', 'entry'), new Option('Salida', 'exit'));
      move.value = p.effective_movement;
      time.type = 'datetime-local';
      time.step = '1';
      time.required = true;
      const d = new Date(p.effective_time);
      time.value = new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 19);
      input('Movimiento corregido', move);
      input('Hora local corregida', time);
    }
    input(action === 'approve' ? 'Motivo de la confirmación presencial' : 'Motivo de la corrección', reason);
    const submit = el('button', action === 'approve' ? 'Confirmar presencia' : 'Guardar corrección', 'primary');
    form.append(submit);
    row.append(form);
    reason.focus();
    const id = crypto.randomUUID();
    form.onsubmit = e => {
      e.preventDefault();
      void task(async () => {
        await api('review', {
          id,
          punch: p.id,
          revision: p.revision,
          action,
          reason: reason.value,
          movement: action === 'correct' ? move.value : p.effective_movement,
          device_time: action === 'correct' ? new Date(time.value).toISOString() : p.effective_time
        }, true);
        await loadManagement();
        await sync(true);
        say('Revisión registrada.');
      }, submit);
    };
  }
  for (const [id, batch] of [['personForm', false], ['batchForm', true]]) {
    $(id).onsubmit = e => {
      e.preventDefault();
      const fields = e.target.elements;
      void task(async () => {
        const people = batch ? Array.from({
          length: Number(fields.count.value)
        }, () => {
          const id = crypto.randomUUID(),
            code = 'DEMO-' + id.slice(0, 8);
          return {
            id,
            code,
            name: 'Empleado de prueba ' + code.slice(5)
          };
        }) : [{
          id: crypto.randomUUID(),
          code: fields.code.value,
          name: fields.namedItem('name').value
        }];
        await api('people', {
          people
        }, true);
        if (!batch) e.target.reset();
        await loadManagement();
        await refresh();
        say('Empleados de prueba disponibles.');
      }, e.submitter);
    };
  }
  $('sync').onclick = () => task(() => sync(true), $('sync'));
  $('logout').onclick = () => task(async () => {
    if (native) {
      await native.postMessage({
        action: 'logout'
      });
      return;
    }
    const r = await fetch('/api/auth', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        action: 'logout'
      })
    });
    if (!r.ok) throw Error('Conéctate para cerrar la sesión.');
    clearPrivate();
    location.replace('/acceso');
  });
  window.addEventListener('storage', e => {
    if (e.key === 'jac.attendance.session-change' && identity && !sameAccount()) {
      clearPrivate();
      location.replace('/acceso');
    }
  });
  function openKiosk() {
    if (opening) return opening;
    $('retryConnection').hidden = true;
    $('connection').textContent = 'Conectando…';
    say('');
    opening = boot().catch(e => {
      clearPrivate();
      say(e.message || 'No se pudo preparar este dispositivo.');
    }).finally(() => {
      opening = null;
      $('retryConnection').hidden = !!identity;
      if (native && !identity) $('logout').hidden = false;
    });
    return opening;
  }
  $('retryConnection').onclick = () => void openKiosk();
  window.addEventListener('online', () => { if (identity) void refresh(); else void openKiosk(); });
  window.addEventListener('offline', () => {
    $('connection').textContent = 'Sin conexión';
    if (ticket) {
      stopGrant();
      screen('kiosk');
    }
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && ticket) {
      void lock().catch(() => {});
    } else if (!document.hidden && identity) void refresh();
  });
  window.addEventListener('pageshow', e => {
    if (e.persisted) location.reload();
  });
  if (!native && 'serviceWorker' in navigator) void navigator.serviceWorker.register('./sw.js', {
    scope: './'
  }).catch(() => say('No se pudo preparar la interfaz sin conexión.'));
  void openKiosk();
})();
