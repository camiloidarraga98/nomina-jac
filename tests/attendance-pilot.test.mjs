import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { startAttendancePilot, seedAttendance } from '../scripts/attendance-pilot.mjs';
for (const simulator of [false, true]) test(`${simulator ? 'iPad simulator' : 'compiled JAC'}: isolated kiosk and operator, versioned supervision and idempotent offline delivery`, async () => {
  const f = await startAttendancePilot({simulator});
  try {
    const call = (path, {
      cookie = '',
      body,
      grant = '',
      origin = f.origin
    } = {}) => fetch(f.origin + path, {
      method: body === undefined ? 'GET' : 'POST',
      redirect: 'manual',
      headers: {
        Origin: origin,
        Cookie: cookie,
        'Content-Type': 'application/json',
        'X-Attendance-Operator': grant
      },
      ...(body === undefined ? {} : {
        body: JSON.stringify(body)
      })
    });
    const login = async (username, password) => {
      const res = await call('/api/auth', {
        body: {
          action: 'login',
          username,
          password
        }
      });
      assert.equal(res.status, 200, await res.clone().text());
      return {
        cookie: res.headers.getSetCookie().map(c => c.split(';')[0]).join('; '),
        profile: (await res.json()).attendance
      };
    };
    const payrollBefore = JSON.stringify((await f.db.prepare('SELECT * FROM payroll_state').all()).results);
    const probe = () => call('/_jac/attendance-ready');
    const ready = await probe();
    assert.equal(ready.status, 204);
    assert.equal(ready.headers.get('X-JAC-Attendance'), 'ready');
    assert.equal(await ready.text(), '');
    assert.equal((await call('/_jac/attendance-ready', {body:{}})).status, 405);
    await f.db.prepare("UPDATE payroll_users SET active=0 WHERE username='operador'").run();
    const starting = await probe();
    assert.equal(starting.status, 503);
    assert.equal(starting.headers.get('X-JAC-Attendance'), 'starting');
    assert.equal(starting.headers.get('Retry-After'), '2');
    await f.db.prepare("UPDATE payroll_users SET active=1 WHERE username='operador'").run();
    assert.equal((await probe()).status, 204);
    const k = await login('admin', 'admin');
    const supervisor = await f.db.prepare("SELECT id FROM payroll_users WHERE attendance_role='operator'").first();
    const otherId = randomUUID();
    await f.db.prepare(`INSERT INTO payroll_users (id,username,email,name,password_hash,permissions,created_at,updated_at)
      SELECT ?,'otra','otra@attendance.invalid','Administradora de prueba',password_hash,'["administrator"]',created_at,updated_at
      FROM payroll_users WHERE id=?`).bind(otherId,k.profile.id).run();
    const other = await login('otra', 'admin');
    assert.equal(other.profile, undefined);
    assert.equal((await call('/api/auth', {body:{action:'login',username:'operador',password:f.operatorPassword}})).status,401);
    const mobile = await fetch(f.origin + '/api/auth', {
      method: 'POST',
      headers: {Origin: f.origin, 'Content-Type':'application/json', 'User-Agent':'JACNomina-iPad/1.0'},
      body: JSON.stringify({action:'login',username:'admin',password:'admin'})
    });
    assert.equal(mobile.status, 200);
    assert.equal((await mobile.json()).attendance.id, k.profile.id);
    assert.equal(mobile.headers.getSetCookie().length, 1);
    const appCookie=mobile.headers.getSetCookie()[0].split(';')[0];
    assert.equal((await (await call('/api/attendance/session',{cookie:appCookie})).json()).id,k.profile.id);
    assert.equal((await call('/api/mobile/payroll?workspace=1',{cookie:appCookie})).status,403);
    assert.equal(k.profile.role, 'kiosk');
    assert.equal((await f.db.prepare("SELECT owner FROM payroll_users WHERE username='admin'").first()).owner, 0);
    await assert.rejects(seedAttendance(f.db, 'x'.repeat(32), 'other-password'), /Ya existe/);
    const api = (cmd, body, grant = '', cookie = k.cookie) => call('/api/attendance/' + cmd, {
      body,
      grant,
      cookie
    });
    assert.equal((await call('/', {
      cookie: k.cookie
    })).headers.get('location'), f.origin + '/asistencia/');
    assert.equal((await call('/asistencia/', {
      cookie: k.cookie
    })).status, 200);
    for (const path of ['/asistencia','/asistencia/','/asistencia/index.html','/asistencia/biometrics.js','/api/attendance/session']) {
      assert.equal((await call(path,{cookie:other.cookie})).status,403,path);
    }
    assert.equal((await call('/attendance/index.html',{cookie:other.cookie})).status,404);
    assert.equal((await call('/asistencia/biometrics.js')).status,401);
    for (const p of ['/crm', '/quincena', '/api/payroll', '/api/mobile/payroll?workspace=1', '/api/users', '/api/reconciliation/state', '/api/calendar', '/api/notices', '/api/media', '/fotografia-offline.html', '/compartir/demo', '/configuracion', '/payroll/print']) assert.equal((await call(p, {
      cookie: k.cookie
    })).status, 403, p);
    assert.equal((await call('/api/auth', {
      cookie: k.cookie,
      body: {
        action: 'password',
        currentPassword: 'admin',
        password: 'change'
      }
    })).status, 403);
    assert.equal((await api('management', {})).status, 403);
    assert.equal((await api('unlock', {
      password: 'admin'
    })).status, 403);
    const granted = await api('unlock', {
      password: f.operatorPassword
    });
    assert.equal(granted.status, 200);
    const {
      ticket
    } = await granted.json();
    for (const cmd of ['unlock','management','people','enrollment-access','review','punch','status']) {
      assert.equal((await api(cmd, {}, ticket, other.cookie)).status,403,cmd);
    }
    const employees = ['A', 'B', 'C'].map(code => ({
      id: randomUUID(),
      name: 'Prueba ' + code,
      code
    }));
    assert.equal((await api('people', {
      people: employees
    }, ticket)).status, 201);
    const enroll = {
      employee: employees[0].id,
      action: 'enroll'
    };
    assert.equal((await api('enrollment-access', enroll)).status, 403);
    assert.equal((await api('enrollment-access', enroll, ticket)).status, 200);
    assert.equal((await api('enrollment-access', {
      ...enroll,
      template: 'x'
    }, ticket)).status, 400);
    assert.equal((await api('people', {
      people: [{
        ...employees[0],
        id: randomUUID()
      }]
    }, ticket)).status, 409);
    assert.equal((await api('retire', {
      id: employees[2].id,
      revision: 1
    }, ticket)).status, 200);
    const roster = await (await api('session')).json();
    assert.deepEqual(roster.people.map(p => p.code), ['A', 'B']);
    const draft = {
      account: k.profile.id,
      id: randomUUID(),
      employee: employees[0].id,
      device: randomUUID(),
      movement: 'entry',
      device_time: new Date(Date.now() - 86400000).toISOString(),
      method: 'simulation'
    };
    assert.equal((await api('punch', {
      ...draft,
      verified: true
    })).status, 400);
    assert.equal((await api('punch', {
      ...draft,
      photo: 'image'
    })).status, 400);
    assert.equal((await api('punch', {
      ...draft,
      account: otherId
    })).status, 403);
    assert.equal((await call('/api/attendance/punch', {
      cookie: k.cookie,
      body: draft,
      origin: 'http://elsewhere.invalid'
    })).status, 403);
    const [first, repeat] = await Promise.all([api('punch', draft), api('punch', draft)]);
    assert.equal(first.status, 200);
    assert.deepEqual(await first.json(), await repeat.json());
    const ack = await (await api('punch', draft)).json();
    assert.equal(ack.state, 'pending');
    assert(ack.clock_difference);
    assert.notEqual(ack.received_at, draft.device_time);
    assert.equal((await api('punch', {
      ...draft,
      movement: 'exit'
    })).status, 409);
    const dup = await (await api('punch', {
      ...draft,
      id: randomUUID(),
      device: randomUUID(),
      method: 'supervised'
    })).json();
    assert(dup.possible_duplicate);
    assert.equal(dup.state, 'pending');
    assert.equal((await api('punch', {
      ...draft,
      id: randomUUID(),
      movement: 'exit',
      method: 'simulation_failed'
    })).status, 200);
    const approve = {
      id: randomUUID(),
      punch: draft.id,
      revision: 0,
      action: 'approve',
      reason: 'Presencia confirmada en la prueba',
      movement: draft.movement,
      device_time: draft.device_time
    };
    assert.equal((await api('review', approve)).status, 403);
    const approved = await api('review', approve, ticket);
    assert.equal(approved.status, 200, await approved.clone().text());
    assert.equal((await api('review', approve, ticket)).status, 200);
    assert.deepEqual((await (await api('status', {
      ids: [draft.id]
    })).json()).records, [{
      id: draft.id,
      state: 'approved'
    }]);
    assert.equal((await api('review', {
      ...approve,
      id: randomUUID()
    }, ticket)).status, 409);
    const correct = {
      ...approve,
      id: randomUUID(),
      revision: 1,
      action: 'correct',
      movement: 'exit',
      reason: 'Ajuste de movimiento ficticio'
    };
    assert.equal((await api('review', correct, ticket)).status, 200);
    const dashboard = await (await api('management', {}, ticket)).json(),
      row = dashboard.punches.find(p => p.id === draft.id);
    assert.equal(row.movement, 'entry');
    assert.equal(row.effective_movement, 'exit');
    assert.equal(row.review_state, 'pending');
    assert.equal(row.revision, 2);
    assert.equal(dashboard.audit.length, 2);
    assert(dashboard.audit.every(r => r.operator === supervisor.id));
    await assert.rejects(f.db.prepare('DELETE FROM attendance_punches WHERE id=?').bind(draft.id).run());
    assert.equal((await (await api('retire', {
      id: employees[0].id,
      revision: 1
    }, ticket)).json()).status, 'inactive');
    assert.equal((await api('punch', draft)).status, 200);
    assert.equal((await api('punch', {
      ...draft,
      id: randomUUID()
    })).status, 409);
    assert.equal(JSON.stringify((await f.db.prepare('SELECT * FROM payroll_state').all()).results), payrollBefore);
    // A reassigned username or a different account with the kiosk role cannot inherit this grant.
    await f.db.prepare("UPDATE payroll_users SET attendance_role='operator' WHERE id=?").bind(otherId).run();
    assert.equal((await api('management', {}, ticket, other.cookie)).status,403);
    await f.db.prepare("UPDATE payroll_users SET attendance_role='kiosk' WHERE id=?").bind(otherId).run();
    assert.equal((await api('session', undefined, '', other.cookie)).status,403);
    await f.db.prepare("UPDATE payroll_users SET username='retirado' WHERE id=?").bind(k.profile.id).run();
    assert.equal((await api('enrollment-access', enroll, ticket)).status,403);
    await f.db.prepare("UPDATE payroll_users SET attendance_role=NULL,username='admin' WHERE id=?").bind(otherId).run();
    assert.equal((await api('session', undefined, '', other.cookie)).status,403);
    await f.db.prepare("UPDATE payroll_users SET username='otra' WHERE id=?").bind(otherId).run();
    await f.db.prepare("UPDATE payroll_users SET username='admin' WHERE id=?").bind(k.profile.id).run();
    await api('lock', {}, ticket);
    assert.equal((await api('management', {}, ticket)).status, 403);
    assert.equal((await call('/api/auth', {
      cookie: k.cookie,
      body: {
        action: 'logout'
      }
    })).status, 200);
    assert.equal((await api('session')).status, 401);
  } finally {
    await f.close();
  }
});
test('an inert pilot binding never enables fixture credentials, shell or API', async () => {
  const f = await startAttendancePilot({
    enabled: false
  });
  try {
    const r = await fetch(f.origin + '/api/auth', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Origin: f.origin
      },
      body: JSON.stringify({
        action: 'login',
        username: 'admin',
        password: 'admin'
      })
    });
    assert.equal(r.status, 401);
    for (const path of ['/asistencia/', '/api/attendance/session', '/attendance/index.html', '/_jac/attendance-ready']) {
      const response = await fetch(f.origin + path);
      assert.equal(response.status, 404);
      assert.equal(response.headers.get('X-JAC-Attendance'), null);
    }
  } finally {
    await f.close();
  }
});
test('iOS target embeds the shared offline resources and selects kiosk before any payroll workspace', async () => {
  const [project, root, store, bridge] = await Promise.all(['ios/JACNomina.xcodeproj/project.pbxproj', 'ios/JACNomina/JACNominaApp.swift', 'ios/JACNomina/PayrollStore.swift', 'ios/JACNomina/AttendanceView.swift'].map(p => readFile(p, 'utf8')));
  assert.match(project, /\.\.\/public\/attendance/);
  assert.match(project, /files = \(04200CFFD12D083534B07BB1,ABA001000000000000000004/);
  assert(root.indexOf('let kiosk = store.attendanceKiosk') < root.indexOf('let overview = store.overview'));
  assert.match(store, /if allowWorkspaceCaches, let cached = client.cachedWorkspace/);
  assert.match(store, /if allowWorkspaceCaches, let record = client.cachedAgenda/);
  assert.match(bridge, /\.completeFileProtection/);
  assert.match(bridge, /isExcludedFromBackup = true/);
  assert.match(bridge, /message.frameInfo.isMainFrame/);
  const folder = 'ios/JACNomina.xcodeproj/xcshareddata/xcschemes';
  const schemes = await readdir(folder);
  assert(!schemes.some(name => /asistencia/i.test(name)));
  const scheme = await readFile(folder + '/JACNomina.xcscheme', 'utf8');
  assert.match(scheme, /BlueprintName="JACNomina"/);
  assert.match(scheme, /iphonesimulator.*?asistencia-mac\.command/);
  assert(!scheme.includes('--attendance-local'));
  assert.match(bridge, /return store.attendanceKiosk\?\.id == account/);
});
