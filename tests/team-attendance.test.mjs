import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID, createHash, generateKeyPairSync } from 'node:crypto';
import { startAttendancePilot } from '../scripts/attendance-pilot.mjs';

test('two independent kiosks share attendance only with ordinary JAC administrators', async (t) => {
  const pushes = [];
  const f = await startAttendancePilot({ enabled: false, notificationTransport: async (request) => {
    const url = new URL(request.url);
    assert.equal(url.hostname,'api.sandbox.push.apple.com');
    pushes.push({token:url.pathname.split('/').at(-1),payload:await request.json()});
    return new Response(null,{status:200});
  } });
  t.after(() => f.close());
  const hash = (value) => createHash('sha256').update(value).digest('hex');
  async function session(admin, email) {
    const token = randomBytes(32).toString('base64url'),
      uid = randomUUID();
    await f.db
      .prepare(
        "INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,created_at,updated_at) VALUES(?,?,?,'Operador ficticio','fixture',?,'','')"
      )
      .bind(uid, uid, email ?? uid + '@example.invalid', admin ? '["administrator"]' : '[]')
      .run();
    await f.db
      .prepare(
        "INSERT INTO payroll_sessions(id,user_id,user_version,expires_at,persistent) VALUES(?,?,1,'',1)"
      )
      .bind(hash(token), uid)
      .run();
    return token;
  }
  const [owner, second, staff] = await Promise.all([
    session(true,'camilo@mac2you.co'), session(true), session(false,'jhonalexcastano@gmail.com')
  ]);
  const auth = { Authorization: 'Bearer ' + owner },
    other = { Cookie: 'jac_session=' + second, Origin: f.origin };
  const call = (route, headers = {}, body) =>
    fetch(f.origin + route, {
      method: body ? 'POST' : 'GET',
      redirect: 'manual',
      headers: { ...headers, ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined
    });
  const admin = (a = auth, p) => call('/api/team-attendance/admin', a, p);
  const device = (headers, p) => call('/api/team-attendance/kiosk', headers, p);
  const cookie = (token) => ({ Cookie: 'jac_session='+token, Origin: f.origin });
  const noticeCommand = (token, command) => call('/api/notices',cookie(token),command);
  const privateKey=generateKeyPairSync('ec',{namedCurve:'P-256'}).privateKey.export({type:'pkcs8',format:'pem'}).toString();
  assert.equal((await noticeCommand(owner,{action:'configure',kind:'apple',environment:'sandbox',version:0,teamId:'TESTTEAM01',keyId:'SANDKEY001',privateKey})).status,200);
  const testTokens=['aa','bb','cc'].map(s=>s.repeat(32)), deviceIds=[];
  for(const [index, token] of [owner,staff,second].entries()){
    const id=randomUUID();
    assert.equal((await noticeCommand(token,{action:'register',id,platform:'ios',token:testTokens[index],environment:'sandbox'})).status,200);
    deviceIds.push(id);
  }
  assert.equal((await admin({})).status, 401);
  assert.equal((await admin({ Authorization: 'Bearer ' + staff })).status, 403);
  assert.equal((await call('/asistencia-equipo/')).status, 303);
  const panel = await call('/asistencia-equipo/', other);
  assert.equal(panel.status, 200);
  assert.match(await panel.text(), /Asistencia del equipo/);
  const uid = randomUUID(),
    person = { action: 'person', id: uid, name: 'Empleado ficticio', code: 'TEST-01' };
  assert.equal((await admin({ Cookie: 'jac_session=' + second }, person)).status, 403);
  assert.equal((await admin(other, person)).status, 200);
  const addKiosk = async (name) => {
    const id = randomUUID(),
      secret = randomBytes(32).toString('hex'),
      enrollment = randomUUID();
    const headers = { Authorization: 'JAC-Kiosk ' + secret, 'X-JAC-Device': id };
    const pair = { action: 'pair', id, hash: hash(secret), name };
    assert.equal((await admin(auth, pair)).status, 200);
    assert.equal((await admin(auth, pair)).status, 200);
    const signing = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
      'sign',
      'verify'
    ]);
    const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', signing.publicKey)).toString('base64');
    const command = { action: 'enroll', id: enrollment, device: id, employee: uid, revision: 1, publicKey };
    assert.equal((await admin(auth, command)).status, 403);
    assert.equal((await admin({ ...auth, 'x-jac-kiosk-token': secret }, command)).status, 200);
    assert.equal(
      (await admin({ ...auth, 'x-jac-kiosk-token': secret }, { ...command, id: randomUUID() })).status,
      409
    );
    const sign = async (input) => {
      const value = [
        input.photo ? 'jac-attendance-v2' : 'jac-attendance-v1',
        id,
        input.employee,
        input.enrollment,
        input.id,
        input.movement,
        new Date(input.occurredAt).toISOString(),
        ...(input.photo ? [hash(Buffer.from(input.photo, 'base64'))] : [])
      ].join('\n');
      const signature = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        signing.privateKey,
        new TextEncoder().encode(value)
      );
      return { ...input, signature: Buffer.from(signature).toString('base64') };
    };
    const enrollAnother = (employee) => admin({ ...auth, 'x-jac-kiosk-token': secret },
      { ...command, id: randomUUID(), employee });
    return { id, headers, enrollment, sign, enrollAnother };
  };
  const first = await addKiosk('Recepción ficticia'),
    next = await addKiosk('Sala ficticia');
  assert.equal((await admin(first.headers)).status, 401);
  const roster = await (await device(first.headers)).json();
  assert.deepEqual(Object.keys(roster).sort(), ['people']);
  assert.equal(roster.people[0].enrollment, first.enrollment);
  const input = await first.sign({
    id: randomUUID(),
    employee: uid,
    enrollment: first.enrollment,
    movement: 'entry',
    occurredAt: '2026-11-20T13:00:00Z'
  });
  assert.equal((await device(next.headers, input)).status, 409);
  assert.equal((await device(first.headers, { ...input, employee: randomUUID() })).status, 409);
  assert.equal((await device(first.headers, { ...input, face: 'reject' })).status, 400);
  // A generated 8 × 8 gray square, without personal data.
  const photo = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAAIAAgBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AP//Z';
  const out = await next.sign({
    ...input,
    id: randomUUID(),
    enrollment: next.enrollment,
    movement: 'exit',
    photo,
    occurredAt: '2026-11-20T22:00:00Z'
  });
  const [a, b] = await Promise.all([device(first.headers, input), device(next.headers, out)]);
  assert.equal(a.status, 200);
  assert.equal(b.status, 200);
  const receipt = await b.json();
  assert.equal(receipt.photoHash, hash(Buffer.from(photo, 'base64')));
  assert.deepEqual(await (await device(next.headers, out)).json(), receipt);
  const altered = Buffer.concat([Buffer.from([255,216,255,254,0,3,65]), Buffer.from(photo, 'base64').subarray(2)]).toString('base64');
  assert.equal((await device(next.headers, {...out, photo:altered})).status,409);
  assert.equal((await device(next.headers, await next.sign({...out, photo:altered}))).status,409);
  assert.equal((await device(next.headers, await next.sign({...out, photo:undefined}))).status,409);
  assert.equal((await device(next.headers, {...out, photo:'bm90LWEtanBlZw=='})).status,400);
  const photoPath = '/api/team-attendance/admin?photo=' + out.id;
  const portrait = await call(photoPath, other);
  assert.equal((await portrait.json()).jpeg, photo);
  assert.match(portrait.headers.get('cache-control'), /no-store/);
  for (const headers of [{}, next.headers]) assert.equal((await call(photoPath, headers)).status, 401);
  assert.equal((await call(photoPath, { Authorization: 'Bearer ' + staff })).status, 403);
  assert.equal((await call('/api/team-attendance/admin?photo=' + input.id, auth)).status, 404);
  assert.deepEqual(await a.json(), await (await device(first.headers, input)).json());
  assert.equal((await device(first.headers, { ...input, movement: 'exit' })).status, 409);
  const manual = {
    action: 'manual',
    id: randomUUID(),
    employee: uid,
    movement: 'entry',
    occurredAt: '2026-11-20T13:00:15Z',
    reason: 'Verificación presencial ficticia'
  };
  assert.equal((await admin(other, manual)).status, 200);
  assert.equal((await admin(other, manual)).status, 200);
  await t.test('accepted kiosk punches notify just the two named accounts with local time and the signed portrait', async () => {
    const alerts=(await f.db.prepare("SELECT id,source,title,body FROM jac_notices WHERE source LIKE 'attendance:%'").all()).results;
    assert.equal(alerts.length,2,'manual supervision and replays do not create a new notice');
    const entry=alerts.find(n=>n.source==='attendance:'+input.id), exit=alerts.find(n=>n.source==='attendance:'+out.id);
    assert.match(entry.body,/Empleado ficticio acaba de registrar su ingreso a laborar\.[\s\S]*8:00/);
    assert.match(exit.body,/Empleado ficticio acaba de registrar su salida de JAC Music\.[\s\S]*5:00/);
    assert.match(exit.body,/20.*2026.*Colombia/);
    const photoFile='/api/notices/file?id='+exit.id+'&file='+exit.id;
    for(const token of [staff,owner]){
      const res=await call('/api/notices?item='+exit.id,cookie(token));
      assert.equal(res.status,200);
      const {item}=await res.json();
      assert.deepEqual(item.attachments,[{id:exit.id,filename:'Foto de la marcación.jpg',mimeType:'image/jpeg',size:Buffer.from(photo,'base64').length}]);
      const file=await call(photoFile,cookie(token));
      assert.equal(file.headers.get('content-type'),'image/jpeg');
      assert.equal(Buffer.from(await file.arrayBuffer()).toString('base64'),photo);
    }
    for(const route of ['/api/notices?item='+exit.id,photoFile]){
      assert.equal((await call(route,cookie(second))).status,404,'another JAC administrator');
      assert.equal((await call(route)).status,401);
    }
    assert.equal((await noticeCommand(second,{action:'deleteAlert',id:exit.id,confirmation:exit.id})).status,404);
    for(let attempt=0;attempt<80&&pushes.length<4;attempt++)await new Promise(r=>setTimeout(r,50));
    assert.equal(pushes.length,4);
    for(const note of [entry,exit]){
      const sent=pushes.filter(p=>p.payload.noticeId===note.id);
      assert.deepEqual(sent.map(p=>p.token).sort(),testTokens.slice(0,2));
      for(const {payload} of sent){
        assert.deepEqual(payload.aps.alert,{title:note.title,body:note.body});
        assert.equal(payload.aps['mutable-content'],note===exit?1:undefined);
        assert.equal(JSON.stringify(payload).includes(photo),false);
      }
    }
    const rich=pushes.find(p=>p.token===testTokens[1]&&p.payload.noticeId===exit.id).payload;
    assert.equal(rich.kind,'attendance');
    const preview=(id,grant)=>call('/api/team-attendance/notification-photo?id='+id,{'Authorization':'JAC-Photo '+grant});
    const photoResponse=await preview(exit.id,rich.photoGrant);
    assert.equal(photoResponse.status,200);assert.match(photoResponse.headers.get('cache-control'),/no-store/);
    assert.equal(Buffer.from(await photoResponse.arrayBuffer()).toString('base64'),photo);
    assert.equal((await preview(entry.id,rich.photoGrant)).status,404);
    assert.equal((await preview(exit.id,rich.photoGrant.replace(/\.\d+\./,'.1600000000.'))).status,404);
    const parts=rich.photoGrant.split('.');
    parts[2]=(parts[2][0]==='A'?'B':'A')+parts[2].slice(1);
    assert.equal((await preview(exit.id,parts.join('.'))).status,404);
    assert.equal((await noticeCommand(staff,{action:'unregister',id:deviceIds[1]})).status,200);
    assert.equal((await preview(exit.id,rich.photoGrant)).status,404);
    assert.equal((await call(photoFile,cookie(staff))).status,200,'the alert stays in the signed-in inbox');
  });
  const feed = await (
    await call('/api/team-attendance/admin?employee=' + uid + '&day=2026-11-20', other)
  ).json();
  assert.equal(feed.records.length, 3);
  assert.equal(feed.records[0].id, out.id);
  assert.equal(feed.records[1].possibleDuplicate, 1);
  assert.ok(feed.records[1].supervisor);
  assert.equal(feed.records.find(r => r.id === out.id).hasPhoto, 1);
  assert.equal(feed.records.find(r => r.id === input.id).hasPhoto, 0);
  assert.equal(JSON.stringify(feed).includes(photo), false);
  const review = {
    action: 'review',
    id: randomUUID(),
    record: input.id,
    revision: 0,
    movement: 'entry',
    occurredAt: '2026-11-20T13:10:00Z',
    reason: 'Hora verificada en persona'
  };
  assert.equal((await admin(other, review)).status, 200);
  assert.equal((await admin(other, review)).status, 200);
  assert.equal((await admin(auth, { ...review, id: randomUUID() })).status, 409);
  const revised = (await (await admin(auth)).json()).records.find((r) => r.id === input.id);
  assert.equal(revised.originalTime, '2026-11-20T13:00:00.000Z');
  assert.equal(revised.occurredAt, '2026-11-20T13:10:00.000Z');
  assert.equal(
    (await (await call('/api/team-attendance/admin?record=' + input.id, auth)).json()).reviews.length,
    1
  );
  assert.equal((await admin(auth, { action: 'resetFace', employee: uid, revision: 1 })).status, 200);
  assert.equal((await device(first.headers, await first.sign({ ...input, id: randomUUID() }))).status, 409);
  assert.equal((await device(first.headers, input)).status, 200);
  assert.equal((await admin(auth, { action: 'archive', employee: uid, revision: 2 })).status, 200);
  assert.equal((await (await device(next.headers)).json()).people.length, 0);
  assert.equal((await (await admin(other)).json()).records.length, 3);

  await t.test('removal preserves dated records, receipts and photos while freeing the roster code', async () => {
    const remove = { action: 'removePerson', employee: uid, revision: 3 };
    assert.equal((await admin(next.headers, remove)).status, 401);
    assert.equal((await admin({ Authorization: 'Bearer ' + staff }, remove)).status, 403);
    assert.equal((await admin(auth, { ...remove, revision: 2 })).status, 409);
    const responses = await Promise.all([admin(other, remove), admin(auth, remove)]);
    for (const response of responses) {
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), { outcome: 'history' });
    }
    const replacement = { ...person, id: randomUUID(), code: person.code.toLowerCase() };
    assert.equal((await admin(auth, replacement)).status, 200);
    assert.equal((await admin(other, remove)).status, 200);
    const after = await (await call('/api/team-attendance/admin?employee=' + uid, auth)).json();
    assert.deepEqual(after.people.map((p) => p.id), [replacement.id]);
    assert.deepEqual(after.formerPeople, [{ id: uid, name: person.name, code: person.code }]);
    assert.equal(after.records.length, 3);
    assert.ok(after.records.every((r) => r.employee === uid && r.code === person.code));
    assert.equal(after.records.find((r) => r.id === input.id).revision, 1);
    assert.equal((await (await call(photoPath, auth)).json()).jpeg, photo);
    assert.deepEqual(await (await device(next.headers, out)).json(), receipt);
    assert.equal((await device(next.headers, await next.sign({ ...out, id: randomUUID() }))).status, 409);
    assert.equal((await admin(other, { ...manual, id: randomUUID() })).status, 409);
    for (const kiosk of [first, next]) {
      const roster = await (await device(kiosk.headers)).json();
      assert.deepEqual(roster.people.map((p) => p.id), [replacement.id]);
      assert.equal(roster.people[0].enrollment, null);
    }

    // This active replacement has two facial enrollments but has never marked.
    for (const kiosk of [first, next]) assert.equal((await kiosk.enrollAnother(replacement.id)).status, 200);
    const discard = { action: 'removePerson', employee: replacement.id, revision: 1 };
    assert.equal((await admin(auth, { ...discard, revision: 9 })).status, 409);
    for (const kiosk of [first, next]) assert.ok((await (await device(kiosk.headers)).json()).people[0].enrollment);
    for (const session of [auth, other]) {
      const removed = await admin(session, discard);
      assert.equal(removed.status, 200);
      assert.deepEqual(await removed.json(), { outcome: 'deleted' });
    }
    assert.equal(await f.db.prepare('SELECT id FROM jac_attendance_people WHERE id=?').bind(replacement.id).first(), null);
    assert.equal(await f.db.prepare('SELECT id FROM jac_attendance_enrollments WHERE employee=?').bind(replacement.id).first(), null);
    assert.equal((await (await device(first.headers)).json()).people.length, 0);
    assert.equal((await (await admin(other)).json()).formerPeople.length, 1);
  });

  await t.test('a first punch racing a removal is either preserved or rejected by both devices', async () => {
    const employee = randomUUID(), punch = { ...manual, employee, id: randomUUID() };
    assert.equal((await admin(auth, { ...person, id: employee, code: 'TEMP' })).status, 200);
    const [marked, removed] = await Promise.all([
      admin(other, punch), admin(auth, { action: 'removePerson', employee, revision: 1 })
    ]);
    assert.equal(removed.status, 200);
    assert.ok([200, 409].includes(marked.status));
    const accepted = marked.status === 200;
    assert.equal((await removed.json()).outcome, accepted ? 'history' : 'deleted');
    const after = await (await call('/api/team-attendance/admin?employee=' + employee, auth)).json();
    assert.equal(after.records.length, accepted ? 1 : 0);
    assert.equal(after.formerPeople.some((p) => p.id === employee), accepted);
    assert.ok(!after.people.some((p) => p.id === employee));
    assert.equal((await admin(auth, { ...punch, id: randomUUID() })).status, 409);
  });
  assert.equal((await admin(auth, { action: 'revoke', id: first.id })).status, 200);
  assert.equal((await device(first.headers)).status, 403);
  await f.db
    .prepare('UPDATE payroll_users SET active=0 WHERE id=(SELECT user_id FROM payroll_sessions WHERE id=?)')
    .bind(hash(second))
    .run();
  assert.equal((await admin(other)).status, 403);
});
