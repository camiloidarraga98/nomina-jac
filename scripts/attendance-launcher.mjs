// Xcode and the interactive .command start the same loopback-only JAC worker.
// This entry uses only Node built-ins until the project's dependencies are ready.
import { spawn, execFileSync } from 'node:child_process';
import { createServer, request } from 'node:http';
import { existsSync, mkdirSync, openSync, closeSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const script = fileURLToPath(import.meta.url);
const root = resolve(dirname(script), '..');
process.chdir(root);
const port = Number(process.env.JAC_ATTENDANCE_TEST_PORT || 8789);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error('Puerto de pruebas inválido.');
const host = '127.0.0.1';
const origin = 'http://' + host + ':' + port;
const health = '/_jac/attendance-ready';
const folder = join(root, 'work/local/asistencia');
const pidFile = join(folder, 'servidor.pid');
const logFile = join(folder, 'servidor.log');
const operatorFile = join(folder, 'supervision.txt');
mkdirSync(folder, { recursive: true, mode: 0o700 });

async function status() {
  try {
    const response = await fetch(origin + health, { redirect: 'manual', signal: AbortSignal.timeout(800) });
    const marker = response.headers.get('X-JAC-Attendance');
    await response.body?.cancel();
    if (response.status === 204 && marker === 'ready') return 'ready';
    if (response.status === 503 && ['starting', 'failed'].includes(marker)) return marker;
    return 'occupied';
  } catch { return 'absent'; }
}

function ownedProcess() {
  try {
    const pid = Number(readFileSync(pidFile, 'utf8'));
    if (!Number.isSafeInteger(pid) || pid < 2) return null;
    const command = execFileSync('ps', ['-p', String(pid), '-o', 'command='], { encoding: 'utf8' }).trim();
    return command.endsWith(' ' + script + ' --serve') ? pid : null;
  } catch { return null; }
}

async function serve() {
  let step = 'install', failed = false, pilot, command;
  const listener = createServer((req, res) => {
    if (!['127.0.0.1:' + port, 'localhost:' + port].includes(req.headers.host) || !req.url.startsWith('/') || req.url.startsWith('//')) {
      res.writeHead(400).end(); return;
    }
    if (pilot) {
      // Forward the original Host, Origin, cookies and response headers to the
      // private worker on its assigned port, including when serving the web app.
      const upstream = request(pilot.origin, { path: req.url, method: req.method, headers: { ...req.headers, connection: 'close' } }, response => {
        res.writeHead(response.statusCode, response.headers);
        response.on('error', () => res.destroy());
        response.pipe(res);
      });
      upstream.on('error', () => { if (!res.headersSent) res.writeHead(502); res.end(); });
      res.on('close', () => upstream.destroy());
      req.pipe(upstream);
      return;
    }
    const headers = { 'Cache-Control': 'no-store', 'Connection': 'close', 'Retry-After': '2' };
    if (req.url === health && req.method === 'GET') {
      res.writeHead(503, { ...headers, 'X-JAC-Attendance': failed ? 'failed' : 'starting', 'X-JAC-Attendance-Step': step });
      res.end();
    } else {
      if (req.method === 'GET' && !failed) headers.Refresh = '2';
      res.writeHead(503, { ...headers, 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(failed ? 'Revisa servidor.log en work/local/asistencia.' : 'Preparando Asistencia de JAC…');
    }
  });
  // Only the process that owns the port may install, build or seed.
  await new Promise((done, reject) => { listener.once('error', reject); listener.listen(port, host, done); });
  writeFileSync(pidFile, String(process.pid), { mode: 0o600 });
  rmSync(operatorFile, { force: true });
  process.on('exit', () => {
    if (existsSync(pidFile) && readFileSync(pidFile, 'utf8') === String(process.pid)) {
      rmSync(operatorFile, { force: true });
      rmSync(pidFile, { force: true });
    }
  });
  const stop = async () => {
    if (command?.pid) { try { process.kill(-command.pid, 'SIGTERM'); } catch { /* already finished */ } }
    listener.close();
    await pilot?.close();
    process.exit(0);
  };
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, stop);
  const npm = args => new Promise((done, reject) => {
    const log = openSync(logFile, 'a', 0o600);
    try { command = spawn('npm', args, { detached: true, stdio: ['ignore', log, log] }); }
    finally { closeSync(log); }
    command.once('error', reject);
    command.once('exit', code => { command = undefined; if (code === 0) done(); else reject(Error('npm ' + args[0] + ' terminó con código ' + code)); });
  });
  try {
    const installing = join(folder, 'instalando');
    if (!existsSync('node_modules/.bin/workerd') || !existsSync('node_modules/.bin/esbuild') || existsSync(installing)) {
      writeFileSync(installing, '', { mode: 0o600 });
      await npm(['ci', '--no-audit', '--no-fund']);
      rmSync(installing);
    }
    step = 'build';
    const { startAttendancePilot } = await import('./attendance-pilot.mjs');
    pilot = await startAttendancePilot({ simulator: true, onPreparation: next => { step = next; } });
    writeFileSync(operatorFile, pilot.operatorPassword + '\n', { mode: 0o600 });
    console.log('JAC · Asistencia de prueba\n' + origin + '/acceso\nClave de supervisión en ' + operatorFile);
  } catch (error) {
    failed = true;
    console.error('No se pudo preparar Asistencia (' + step + ').', error.message);
    if (pilot) { const running = pilot; pilot = undefined; await running.close(); }
    // Give the simulator the specific setup failure; a subsequent Run can retry immediately.
    setTimeout(() => process.exit(1), 30_000);
  }
}

async function main() {
  const mode = process.argv[2], current = await status();
  if (mode === '--stop' || current === 'failed') {
    const pid = ownedProcess();
    if (pid) {
      process.kill(pid, 'SIGTERM');
      for (let n = 0; n < 40 && existsSync(pidFile); n++) await delay(100);
    }
    if (mode === '--stop') return;
  }
  if (['ready', 'starting'].includes(current)) {
    console.log(current === 'ready' ? 'El piloto de Asistencia ya está en ejecución.' : 'El piloto ya se está preparando.');
    if (existsSync(operatorFile)) console.log('Clave de supervisión en ' + operatorFile);
    return;
  }
  if (current === 'occupied') throw Error('Otro servicio ocupa el puerto ' + port + '. Revisa ese proceso en el Mac.');
  if (mode !== '--xcode') return serve();
  const log = openSync(logFile, 'a', 0o600);
  let child;
  try { child = spawn(process.execPath, [script, '--serve'], { detached: true, stdio: ['ignore', log, log] }); }
  finally { closeSync(log); }
  child.unref();
  for (let n = 0; n < 25; n++) {
    const state = await status();
    if (state === 'starting' || state === 'ready') return;
    if (state === 'failed' || state === 'occupied') break;
    await delay(120);
  }
  throw Error('Revisa el arranque del piloto en ' + logFile);
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
