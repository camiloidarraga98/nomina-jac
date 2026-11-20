import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { startAttendancePilot } from './attendance-pilot.mjs';
const {
  chromium
} = await import(process.env.JAC_PLAYWRIGHT_MODULE || 'playwright');
const captures = resolve(process.env.JAC_ATTENDANCE_CAPTURES || '.sites-runtime/asistencia');
await mkdir(captures, {
  recursive: true
});
const f = await startAttendancePilot({simulator: process.argv.includes('--simulator')}),
  browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROMIUM_PATH ? {
      executablePath: process.env.CHROMIUM_PATH
    } : {}),
    args: ['--no-sandbox']
  });
try {
  const ctx = await browser.newContext({
    viewport: {
      width: 1180,
      height: 820
    },
    locale: 'es-CO'
  });
  let p = await ctx.newPage();
  p.setDefaultTimeout(9000);
  const failures = [];
  p.on('pageerror', error => failures.push(error.message));
  p.on('dialog', dialog => dialog.accept());
  const unlock = async () => {
    await p.locator('#operator').click();
    await p.locator('#unlock [name=password]').fill(f.operatorPassword);
    await p.locator('#unlock button.primary').click();
    await p.locator('#management').waitFor();
  };
  await p.goto(f.origin + '/acceso');
  await p.locator('input[autocomplete=username]').fill('admin');
  await p.locator('input[type=password]').fill('admin');
  await p.locator('form button[type=submit],form button.primary,form button').first().click();
  await p.waitForURL('**/asistencia/').catch(async e => {
    console.error('Ruta', new URL(p.url()).pathname, 'aviso', await p.locator('[role=alert]').allTextContents(), failures);
    throw e;
  });
  await p.locator('#kiosk').waitFor();
  assert.equal(await p.getByText('Quincena', {
    exact: true
  }).count(), 0);
  await unlock();
  await p.locator('#showPeople').click();
  const names = ['Marina de Prueba', 'Daniel de Prueba', 'Luz de Prueba'];
  for (const [i, name] of names.entries()) {
    await p.locator('#personForm [name=code]').fill('DEMO-0' + (i + 1));
    await p.locator('#personForm [name=name]').fill(name);
    await p.locator('#personForm button').click();
    await p.locator('#peopleList li').filter({
      hasText: name
    }).waitFor();
  }
  const demo = p.locator('#peopleList li').filter({
    hasText: names[0]
  });
  await demo.getByRole('button', {
    name: 'Enrolar muestra sintética'
  }).click();
  await demo.getByText(/caduca en 24/).waitFor();
  await p.screenshot({
    path: captures + '/empleados.png'
  });
  await p.locator('#lock').click();
  await p.locator('#employee').selectOption({
    label: 'DEMO-01 · ' + names[0]
  });
  await p.screenshot({
    path: captures + '/kiosco.png'
  });
  await p.locator('#method').selectOption('simulation');
  await p.locator('#punch').click();
  await p.locator('#recent').getByText('Recibida · supervisión pendiente').waitFor();
  await p.evaluate(() => navigator.serviceWorker.ready);
  await p.waitForFunction(() => !!navigator.serviceWorker.controller);
  await ctx.setOffline(true);
  await p.reload();
  await p.locator('#kiosk').waitFor();
  await p.getByLabel('Salida', {
    exact: true
  }).check();
  await p.locator('#employee').selectOption({
    label: 'DEMO-01 · ' + names[0]
  });
  await p.locator('#punch').dblclick();
  await p.locator('#recent').getByText(/Guardada en este dispositivo/).waitFor();
  assert.equal((await f.db.prepare('SELECT COUNT(*) n FROM attendance_punches').first()).n, 1);
  await p.close();
  p = await ctx.newPage();
  p.setDefaultTimeout(9000);
  p.on('pageerror', error => failures.push(error.message));
  await p.goto(f.origin + '/asistencia/');
  await p.locator('#recent').getByText(/Guardada en este dispositivo/).waitFor();
  await p.screenshot({
    path: captures + '/sin-conexion.png'
  });
  // The server commits, but the first response is lost on its way to the kiosk.
  const attempts = [];
  let lost = 0;
  await p.route('**/api/attendance/punch', async route => {
    attempts.push({
      id: route.request().postDataJSON().id,
      time: Date.now()
    });
    if (!lost) {
      lost++;
      await route.fetch();
      await route.abort();
    } else await route.continue();
  });
  await ctx.setOffline(false);
  await p.locator('#sync').click();
  await p.waitForFunction(() => document.querySelectorAll('#recent li').length === 2 && !document.querySelector('#recent').textContent.includes('por enviar'), {}, {
    timeout: 22000
  });
  assert.equal(lost, 1);
  assert(attempts.length >= 2);
  assert.equal(attempts[0].id, attempts[1].id);
  assert(attempts[1].time - attempts[0].time >= 1500, 'retry uses backoff');
  assert.equal((await f.db.prepare('SELECT COUNT(*) n FROM attendance_punches').first()).n, 2);
  await unlock();
  await p.locator('#showPunches').click();
  const row = p.locator('#punchList article').first();
  await row.getByRole('button', {
    name: 'Supervisar'
  }).click();
  await row.locator('input').fill('Presencia confirmada por el operador de prueba');
  await row.getByText('Confirmar presencia', {
    exact: true
  }).click();
  await row.getByText('Supervisión presencial aprobada').waitFor();
  await p.screenshot({
    path: captures + '/gestion.png'
  });
  await p.locator('#showPeople').click();
  await p.locator('#batchForm input').fill('2');
  await p.locator('#batchForm button').click();
  await p.waitForFunction(() => document.querySelectorAll('#peopleList li').length === 5);
  p.on('dialog', dialog => dialog.accept());
  await p.locator('#peopleList li').filter({
    hasText: names[0]
  }).getByText('Retirar empleado').click();
  await p.locator('#peopleList li').filter({
    hasText: names[0]
  }).getByText('Inactivo').waitFor();
  const other = p.locator('#peopleList li').filter({
    hasText: names[1]
  });
  await other.getByText('Retirar empleado').click();
  await other.waitFor({
    state: 'detached'
  });
  await p.locator('#lock').click();
  await p.locator('#logout').click();
  await p.waitForURL('**/acceso');
  await ctx.setOffline(true);
  await p.goto(f.origin + '/asistencia/');
  assert.equal(await p.locator('#kiosk').isVisible(), false);
  assert.equal(await p.getByText(names[0], {
    exact: false
  }).count(), 0);
  assert.deepEqual(failures, []);
  console.log('PASS: JAC login, kiosk, roster, local enrollment, review, removal, offline reload/reopen, double tap, lost acknowledgement, retry and logout isolation.');
} finally {
  await browser.close();
  await f.close();
}
