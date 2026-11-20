import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createServer } from 'node:net';
import { copyFile, mkdir, mkdtemp, readFile, readdir, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const exec = promisify(execFile);
test('A fresh Mac requests its own architecture and discards incomplete or unverified downloads', async t => {
  for (const [machine, archiveArch] of [['arm64', 'arm64'], ['x86_64', 'x64']]) {
    await t.test(machine, async t => {
      const root = await mkdtemp(join(tmpdir(), 'JAC fresh Mac '));
      t.after(() => rm(root, { recursive: true, force: true }));
      const scripts = join(root, 'scripts');
      const commands = join(root, 'commands');
      await mkdir(scripts);
      await mkdir(commands);
      await copyFile('scripts/asistencia-mac.command', join(scripts, 'asistencia-mac.command'));
      await writeFile(join(commands, 'uname'), `#!/bin/sh
if [ "$1" = -s ]; then echo Darwin; else echo "${machine}"; fi
`, { mode: 0o700 });
      await writeFile(join(commands, 'curl'), `#!/bin/sh
while [ "$1" != --output ]; do shift; done
echo "$3" >> requests
printf 'incomplete archive' > "$2"
test -f connected
`, { mode: 0o700 });
      await writeFile(join(commands, 'tar'), '#!/bin/sh\ntouch unexpected-extraction\nexit 1\n', { mode: 0o700 });
      const run = () => exec('/bin/bash', ['scripts/asistencia-mac.command', '--prepare-runtime'], {
        cwd: root, env: { ...process.env, PATH: commands + ':' + process.env.PATH }, timeout: 5000
      });
      await assert.rejects(run(), error => /No se pudo descargar/.test(error.stderr));
      await writeFile(join(root, 'connected'), '');
      await assert.rejects(run(), error => /no coincide con la oficial/.test(error.stderr));
      const urls = (await readFile(join(root, 'requests'), 'utf8')).trim().split('\n');
      assert.equal(urls.length, 2);
      assert.equal(urls[0], urls[1]);
      const url = new URL(urls[0]);
      assert.equal(url.origin, 'https://nodejs.org');
      const version = url.pathname.split('/')[2];
      assert.match(version, /^v24\.\d+\.\d+$/);
      assert.equal(url.pathname, '/dist/' + version + '/node-' + version + '-darwin-' + archiveArch + '.tar.gz');
      assert.deepEqual(await readdir(join(root, 'work/local/toolchain')), []);
      await assert.rejects(stat(join(root, 'unexpected-extraction')), { code: 'ENOENT' });
    });
  }
});

test('Xcode starts one headless fixture, reports setup failures and retries without touching another process', async () => {
  const root = await mkdtemp(join(tmpdir(), 'JAC simulator '));
  const reservation = createServer();
  await new Promise(done => reservation.listen(0, '127.0.0.1', done));
  const port = reservation.address().port;
  await new Promise(done => reservation.close(done));
  const origin = 'http://127.0.0.1:' + port;
  const options = { cwd: root, env: { ...process.env, JAC_ATTENDANCE_TEST_PORT: String(port) }, timeout: 15000 };
  const launch = flag => exec('/bin/bash', ['scripts/asistencia-mac.command', flag], options);
  const health = async (state, step) => {
    for (let i = 0; i < 80; i++) {
      const r = await fetch(origin + '/_jac/attendance-ready');
      await r.body?.cancel();
      if (r.status === (state === 'ready' ? 204 : 503) && r.headers.get('X-JAC-Attendance') === state &&
          (!step || r.headers.get('X-JAC-Attendance-Step') === step)) return;
      await delay(100);
    }
    assert.fail('El iniciador no llegó a ' + state + '/' + step);
  };
  try {
    await mkdir(join(root, 'scripts'));
    for (const file of ['asistencia-mac.command', 'attendance-launcher.mjs'])
      await copyFile('scripts/' + file, join(root, 'scripts', file));
    const bin = join(root, 'work/local/toolchain/node/bin');
    await mkdir(bin, {recursive:true});
    await symlink(process.execPath, join(bin, 'node'));
    await writeFile(join(bin, 'npm'), `#!/bin/sh
set -eu
if [ "$1" = --version ]; then echo 11; exit 0; fi
echo "$1" >> work/calls
if [ "$1" = ci ]; then
  while [ ! -f work/installed ]; do sleep 0.1; done
  mkdir -p node_modules/.bin
  touch node_modules/.bin/workerd node_modules/.bin/esbuild
else
  exit 1
fi
`, {mode:0o700});
    await writeFile(join(root, 'scripts/attendance-pilot.mjs'), `
      import {createServer} from 'node:http';
      import {existsSync} from 'node:fs';
      export async function startAttendancePilot({simulator, onPreparation}) {
        if (!simulator || existsSync('work/fail-build')) throw Error('Simulated worker build failure');
        onPreparation('database');
        const server = createServer((req,res) => {
          if (req.url === '/_jac/attendance-ready') res.writeHead(204, {'X-JAC-Attendance':'ready'}).end();
          else res.end(req.headers.origin + ' ' + req.headers.host);
        });
        await new Promise(done => server.listen(0,'127.0.0.1',done));
        return {origin:'http://127.0.0.1:'+server.address().port,operatorPassword:'synthetic-only',close:()=>new Promise(done=>server.close(done))};
      }
    `);
    await writeFile(join(root, '.gitignore'), 'work/\nnode_modules/\ndist/\n');
    await writeFile(join(root, 'work/fail-build'), '');
    await Promise.all([launch('--xcode'), launch('--xcode')]);
    await health('starting', 'install');
    const premature = await fetch(origin + '/api/auth', {method:'POST', body:'fixture'});
    assert.equal(premature.status, 503);
    assert.equal(premature.headers.get('Set-Cookie'), null);
    await premature.body.cancel();
    await writeFile(join(root, 'work/installed'), '');
    await health('failed', 'build');
    await rm(join(root, 'work/fail-build'));
    await launch('--xcode');
    await health('ready');
    const pidFile = join(root, 'work/local/asistencia/servidor.pid');
    const first = await readFile(pidFile, 'utf8');
    await launch('--xcode');
    assert.equal(await readFile(pidFile, 'utf8'), first);
    const response = await fetch(origin + '/api/auth', {method:'POST', headers:{Origin:origin}});
    assert.equal(await response.text(), origin + ' 127.0.0.1:' + port);
    assert.equal((await stat(join(root, 'work/local/asistencia/supervision.txt'))).mode & 0o777, 0o600);
    await launch('--stop');
    await launch('--xcode');
    await health('ready');
    assert.deepEqual((await readFile(join(root, 'work/calls'),'utf8')).trim().split('\n'), ['ci']);
  } finally {
    await launch('--stop').catch(() => {});
    await rm(root, { recursive:true, force:true });
  }
});
