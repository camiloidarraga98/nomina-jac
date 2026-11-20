// The pilot only constructs its own Miniflare database. No Wrangler commands or remote bindings.
import { Miniflare } from 'miniflare';
import { readFile, readdir, stat } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID } from 'node:crypto';
import { hashPassword } from '../lib/payroll-auth-crypto.ts';
export async function seedAttendance(db, pepper, operatorPassword) {
  const roles = [['admin', 'admin', 'Kiosco de prueba', 'kiosk'], ['operador', operatorPassword, 'Operador de prueba', 'operator']];
  for (const [username] of roles) if (await db.prepare('SELECT 1 FROM payroll_users WHERE username=? COLLATE NOCASE OR email=? COLLATE NOCASE').bind(username, username + '@attendance.invalid').first()) throw Error('Ya existe la cuenta ' + username + '. Se canceló la preparación.');
  const now = new Date().toISOString();
  await db.batch(roles.map(([username, password, name, role]) => db.prepare("INSERT INTO payroll_users (id,username,email,name,password_hash,owner,active,permissions,section_access,attendance_role,created_at,updated_at) VALUES (?,?,?,?,?,0,1,'[]','[]',?,?,?)").bind(randomUUID(), username, username + '@attendance.invalid', name, hashPassword(password, pepper), role, now, now)));
}
export async function startAttendancePilot({
  port = 0,
  enabled = true,
  simulator = false,
  notificationTransport,
  onPreparation = () => {}
} = {}) {
  const root = resolve(simulator ? 'scripts' : 'dist/server');
  const assets = resolve(simulator ? 'public' : 'dist/client');
  let modules, browserAssets;
  if (simulator) {
    const {simulatorWorker} = await import('./attendance-simulator.mjs');
    modules = [await simulatorWorker()];
  } else {
    const entry = resolve(root, 'index.js');
    await stat(entry);
    modules = [entry, ...(await readdir(root, {recursive: true}))
      .filter(p => p.endsWith('.js') && p !== 'index.js').map(p => resolve(root, p))]
      .map(path => ({type: 'ESModule', path}));
  }
  onPreparation('database');
  const pepper = randomBytes(32).toString('hex'),
    operatorPassword = randomBytes(15).toString('base64url');
  const mime = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript',
    '.css': 'text/css',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.woff2': 'font/woff2',
    '.json': 'application/json'
  };
  const mf = new Miniflare({
    host: '127.0.0.1',
    port,
    modulesRoot: root,
    modules,
    compatibilityDate: '2026-05-15',
    compatibilityFlags: ['nodejs_compat'],
    d1Databases: {
      DB: 'attendance-pilot-ephemeral'
    },
    r2Buckets: {
      BUCKET: 'attendance-pilot-empty'
    },
    bindings: {
      JAC_READY: '1',
      JAC_HOSTING: 'cloudflare',
      PAYROLL_AUTH_KEY: pepper,
      ...(notificationTransport ? {PAYROLL_MAIL_KEY: randomBytes(32).toString('base64url')} : {}),
      ...(enabled ? {
        JAC_ATTENDANCE_PILOT: 'isolated-local'
      } : {})
    },
    outboundService: notificationTransport ?? (() => new Response('External service disabled', {
      status: 503
    })),
    serviceBindings: {
      ASSETS: async req => {
        const name = new URL(req.url).pathname;
        if (simulator && ['/_jac/acceso.js', '/_jac/acceso.css'].includes(name)) {
          browserAssets ??= import('./attendance-simulator.mjs').then(m => m.browserLoginAssets())
            .catch(error => { browserAssets = undefined; throw error; });
          const file = (await browserAssets).get(name);
          return new Response(req.method === 'HEAD' ? null : file.contents, {headers: {'Content-Type': file.type}});
        }
        const path = resolve(assets, '.' + name);
        if (!path.startsWith(assets + sep)) return new Response(null, {
          status: 404
        });
        try {
          return new Response(await readFile(path), {
            headers: {
              'Content-Type': mime[extname(path)] || 'application/octet-stream'
            }
          });
        } catch {
          return new Response(null, {
            status: 404
          });
        }
      }
    }
  });
  try {
    const db = await mf.getD1Database('DB');
    for (const f of (await readdir('drizzle')).filter(f => f.endsWith('.sql')).sort()) {
      const sql = await readFile('drizzle/' + f, 'utf8');
      for (const statement of sql.split('--> statement-breakpoint').map(s => s.trim()).filter(Boolean)) await db.prepare(statement).run();
    }
    // Separate migration namespace. Ordinary JAC database upgrades never install a pilot fixture.
    const attendance = await readFile('db/attendance-pilot/001.sql', 'utf8');
    for (const statement of attendance.split('--> statement-breakpoint').map(s => s.trim()).filter(Boolean)) await db.prepare(statement).run();
    await seedAttendance(db, pepper, operatorPassword);
    return {
      mf,
      db,
      origin: (await mf.ready).origin,
      operatorPassword,
      close: () => mf.dispose()
    };
  } catch (error) {
    await mf.dispose();
    throw error;
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const pilot = await startAttendancePilot({
    port: 8789
  });
  console.log('JAC · Asistencia de prueba\n' + pilot.origin + '/acceso\nKiosco: admin / admin\nClave de supervisión del piloto: ' + pilot.operatorPassword + '\nLa base de prueba se descarta al detener el proceso.');
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, async () => {
    await pilot.close();
    process.exit(0);
  });
}
