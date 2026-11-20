import { z } from 'zod';
import { attendancePilotOrigin, attendanceSession, passwordLogin, rateLimit } from './payroll-auth-store';
import { randomToken, sessionToken, tokenHash } from './payroll-auth-crypto';
const uuid = z.string().uuid();
const date = z.string().datetime({
  offset: true
}).transform(value => new Date(value).toISOString());
const movement = z.enum(['entry', 'exit']);
const punchInput = z.object({
  account: uuid,
  id: uuid,
  employee: uuid,
  device: uuid,
  movement,
  device_time: date,
  method: z.enum(['supervised', 'simulation', 'simulation_failed'])
}).strict();
const person = z.object({
  id: uuid,
  code: z.string().trim().regex(/^[a-zA-Z0-9_-]{1,32}$/),
  name: z.string().trim().min(1).max(80)
}).strict();
const reviewInput = z.object({
  id: uuid,
  punch: uuid,
  revision: z.number().int().nonnegative(),
  action: z.enum(['approve', 'correct']),
  reason: z.string().trim().min(3).max(400),
  movement,
  device_time: date
}).strict();
const headers = {
  'Cache-Control': 'private, no-store',
  'Referrer-Policy': 'same-origin',
  'X-Content-Type-Options': 'nosniff',
  'Vary': 'Cookie'
};
const reply = (body: unknown, status = 200) => Response.json(body, {
  status,
  headers
});
const issue = (message: string, status: number) => reply({
  error: message
}, status);
const privateSession = "SELECT 1 FROM payroll_sessions s JOIN payroll_users u ON s.user_id=u.id AND s.user_version=u.version WHERE s.id=? AND u.id=? AND u.active=1 AND u.owner=0 AND u.username COLLATE BINARY='admin' AND u.attendance_role='kiosk' AND (s.persistent=1 OR s.expires_at>strftime('%Y-%m-%dT%H:%M:%fZ','now'))";
const manager = "SELECT g.operator FROM attendance_operator_grants g JOIN payroll_users o ON o.id=g.operator AND o.version=g.operator_version WHERE o.active=1 AND o.attendance_role='operator' AND g.id=? AND g.session=? AND g.expires_at>strftime('%Y-%m-%dT%H:%M:%fZ','now') AND EXISTS(" + privateSession + ")";
const roster = "SELECT id,code,name,active,revision FROM attendance_people";
const history = "SELECT p.*,e.name,e.code,COALESCE(r.revision,0) AS revision,COALESCE(r.movement,p.movement) AS effective_movement,COALESCE(r.device_time,p.device_time) AS effective_time,CASE WHEN r.action='approve' THEN 'approved' ELSE 'pending' END AS review_state,r.operator AS reviewed_by FROM attendance_punches p JOIN attendance_people e ON e.id=p.employee LEFT JOIN attendance_reviews r ON r.punch=p.id AND r.revision=(SELECT MAX(revision) FROM attendance_reviews WHERE punch=p.id)";
type Row = Record<string, string | number>;
type Ctx = {
  db: D1Database;
  account: string;
  session: string;
  gate: string[];
};
async function recordPunch(ctx: Ctx, input: z.infer<typeof punchInput>) {
  const {
    db,
    account,
    session
  } = ctx;
  if (input.account !== account) return issue('La marcación pertenece a otra cuenta.', 403);
  const values = [input.id, input.employee, account, input.device, input.movement, input.device_time, new Date().toISOString(), input.method];
  await db.prepare(`INSERT INTO attendance_punches SELECT ?,?,?,?,?,?,?,?,
   EXISTS(SELECT 1 FROM attendance_punches WHERE employee=? AND movement=? AND ABS(unixepoch(device_time)-unixepoch(?))<=90),
   ABS(unixepoch('now')-unixepoch(?))>300
   WHERE EXISTS(SELECT 1 FROM attendance_people WHERE id=? AND active=1) AND EXISTS(${privateSession})
   ON CONFLICT(id) DO NOTHING`).bind(...values, input.employee, input.movement, input.device_time, input.device_time, input.employee, session, account).run();
  const row = await db.prepare(`${history} WHERE p.id=? AND p.actor=? AND EXISTS(${privateSession})`).bind(input.id, account, session, account).first<Row>();
  if (!row || row.employee !== input.employee || row.device !== input.device || row.movement !== input.movement || row.device_time !== input.device_time || row.method !== input.method) return issue('Empleado inactivo o identificador en conflicto. Requiere revisión.', 409);
  return reply({
    id: row.id,
    received_at: row.received_at,
    state: row.review_state,
    possible_duplicate: !!row.possible_duplicate,
    clock_difference: !!row.clock_difference
  });
}
async function review(ctx: Ctx, input: z.infer<typeof reviewInput>) {
  const {
    db,
    gate
  } = ctx;
  const add = await db.prepare(`INSERT INTO attendance_reviews (id,punch,revision,action,reason,operator,recorded_at,movement,device_time)
 SELECT ?,p.id,?,?,?,(${manager}),?,?,? FROM (${history}) p WHERE p.id=? AND p.revision=?
 AND (?='correct' OR (p.review_state='pending' AND p.effective_movement=? AND p.effective_time=?))
 AND EXISTS(${manager}) ON CONFLICT DO NOTHING`).bind(input.id, input.revision + 1, input.action, input.reason, ...gate, new Date().toISOString(), input.movement, input.device_time, input.punch, input.revision, input.action, input.movement, input.device_time, ...gate).run();
  if (!add.meta.changes) {
    const previous = await db.prepare(`SELECT * FROM attendance_reviews WHERE id=? AND operator=(${manager})`).bind(input.id, ...gate).first<Row>();
    if (!previous || previous.punch !== input.punch || previous.revision !== input.revision + 1 || previous.action !== input.action || previous.reason !== input.reason || previous.movement !== input.movement || previous.device_time !== input.device_time) return issue('La revisión cambió. Actualiza el registro.', 409);
  }
  return reply({
    ok: true
  });
}
async function management(ctx: Ctx, path: string, body: unknown) {
  const {
    db,
    gate
  } = ctx;
  if (!(await db.prepare(manager).bind(...gate).first())) return issue('Autentica a un operador de Asistencia.', 403);
  if (path === 'management') {
    const people = await db.prepare(roster + ' WHERE EXISTS(' + manager + ') ORDER BY code').bind(...gate).all();
    const punches = await db.prepare(history + ' WHERE EXISTS(' + manager + ') ORDER BY p.received_at DESC,p.id').bind(...gate).all();
    const audit = await db.prepare('SELECT r.*,o.name AS operator_name FROM attendance_reviews r JOIN payroll_users o ON o.id=r.operator WHERE EXISTS(' + manager + ') ORDER BY r.punch,r.revision').bind(...gate).all();
    return reply({
      people: people.results,
      punches: punches.results,
      audit: audit.results
    });
  }
  if (path === 'enrollment-access') {
    const {
      employee,
      action
    } = z.object({
      employee: uuid,
      action: z.enum(['enroll', 'remove'])
    }).strict().parse(body);
    const eligible = await db.prepare(`SELECT id FROM attendance_people WHERE id=? AND (active=1 OR ?='remove') AND EXISTS(${manager})`).bind(employee, action, ...gate).first();
    return eligible ? reply({
      employee,
      action,
      kind: 'synthetic'
    }) : issue('Empleado no disponible.', 409);
  }
  if (path === 'people') {
    const input = z.object({
      people: z.array(person).min(1).max(30)
    }).strict().parse(body);
    try {
      const changes = await db.batch(input.people.map(p => db.prepare(`INSERT INTO attendance_people(id,code,name) SELECT ?,?,? WHERE EXISTS(${manager})`).bind(p.id, p.code, p.name, ...gate)));
      return changes.every(q => q.meta.changes === 1) ? reply({
        ok: true
      }, 201) : issue('Autentica al operador.', 403);
    } catch (e) {
      if (String(e).includes('UNIQUE')) return issue('Ya existe ese identificador interno.', 409);
      throw e;
    }
  }
  if (path === 'retire') {
    const {
      id,
      revision
    } = z.object({
      id: uuid,
      revision: z.number().int().positive()
    }).strict().parse(body);
    const where = 'WHERE id=? AND revision=? AND active=1 AND EXISTS(' + manager + ')';
    const [removed, disabled] = await db.batch([db.prepare('DELETE FROM attendance_people ' + where + ' AND NOT EXISTS(SELECT 1 FROM attendance_punches WHERE employee=?)').bind(id, revision, ...gate, id), db.prepare('UPDATE attendance_people SET active=0, revision=revision+1 ' + where + ' AND EXISTS(SELECT 1 FROM attendance_punches WHERE employee=?)').bind(id, revision, ...gate, id)]);
    return removed.meta.changes || disabled.meta.changes ? reply({
      status: removed.meta.changes ? 'deleted' : 'inactive'
    }) : issue('El empleado cambió. Actualiza el listado.', 409);
  }
  if (path === 'review') return review(ctx, reviewInput.parse(body));
  return issue('Solicitud desconocida.', 404);
}
type PilotEnv = {
  DB: D1Database;
  ASSETS: Fetcher;
};
const assets = new Set(['index.html', 'app.js', 'storage.js', 'biometrics.js', 'sw.js', 'style.css']);
export async function attendanceBoundary(request: Request, env: PilotEnv): Promise<Response | null> {
  const url = new URL(request.url),
    path = url.pathname;
  // The raw bundle is only read through ASSETS by this handler or from the native app.
  if (path === '/attendance' || path.startsWith('/attendance/')) return issue('Sección no disponible.', 404);
  const readiness = path === '/_jac/attendance-ready';
  const api = path.startsWith('/api/attendance/'),
    page = path === '/asistencia' || path.startsWith('/asistencia/');
  // Pilot bindings are only supplied by the loopback/simulator runner.
  const enabled = attendancePilotOrigin(url);
  if (!enabled) return page || api || readiness ? issue('Sección no disponible.', 404) : null;
  if (readiness) {
    if (request.method !== 'GET') return issue('Método no permitido.', 405);
    // Miniflare can accept HTTP while the runner is still migrating its empty database.
    // Both fixture accounts are inserted in the final transaction.
    try {
      const ready = await env.DB.prepare(
        "SELECT COUNT(*) AS count FROM payroll_users WHERE active=1 AND owner=0 AND password_hash<>'' " +
        "AND ((username COLLATE BINARY='admin' AND attendance_role='kiosk') OR (username='operador' AND attendance_role='operator'))"
      ).first<{count: number}>();
      if (ready?.count === 2) return new Response(null, {status: 204, headers: {...headers, 'X-JAC-Attendance': 'ready'}});
    } catch {
      // The pilot schema may not exist yet.
    }
    return new Response(null, {status: 503, headers: {...headers, 'X-JAC-Attendance': 'starting', 'Retry-After': '2'}});
  }
  const token = sessionToken(request.headers.get('cookie') || '', !['localhost', '127.0.0.1'].includes(url.hostname));
  const current = token ? await attendanceSession(token) : null;
  const identity = current?.kiosk;
  if (!page && !api) {
    if (!current?.restricted) return null;
    if (path === '/jac-music-offline.js' && request.method === 'GET') return null; // Used by JAC login to erase the prior offline music vault.
    if (path === '/api/auth' && request.method === 'POST') {
      const content = await request.clone().text();
      if (content.length <= 4000 && (() => {
        try {
          return JSON.parse(content).action === 'logout';
        } catch {
          return false;
        }
      })()) return null;
    }
    if (identity && path === '/' && request.method === 'GET') return Response.redirect(new URL('/asistencia/', url), 303);
    return issue('Esta cuenta solo permite ponchar en Asistencia.', 403);
  }
  if (!identity) {
    if (current) return issue('Asistencia está reservada al kiosco de prueba.', 403);
    if (page && ['/asistencia', '/asistencia/'].includes(path) && request.method === 'GET') {
      return Response.redirect(new URL('/acceso?returnTo=/asistencia/', url), 303);
    }
    return issue('Inicia sesión en JAC.', 401);
  }
  if (page) {
    if (!['GET', 'HEAD'].includes(request.method)) return issue('Método no permitido.', 405);
    if (path === '/asistencia') return Response.redirect(new URL('/asistencia/', url), 303);
    const file = path.slice('/asistencia/'.length) || 'index.html';
    if (!assets.has(file)) return issue('Página desconocida.', 404);
    url.pathname = '/attendance/' + file;
    url.search = '';
    const data = await env.ASSETS.fetch(new Request(url, {
      method: request.method
    }));
    const response = new Response(data.body, data);
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; worker-src 'self'; media-src 'none'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
    response.headers.set('Permissions-Policy', 'camera=(), microphone=()');
    return response;
  }
  const command = path.slice('/api/attendance/'.length),
    session = tokenHash(token),
    db = env.DB;
  const grant = request.headers.get('x-attendance-operator') || '';
  const ctx = {
    db,
    account: identity.id,
    session,
    gate: [tokenHash(grant), session, session, identity.id]
  };
  try {
    if (request.method === 'GET' && command === 'session') return reply({
      ...identity,
      people: (await db.prepare(roster + ' WHERE active=1 AND EXISTS(' + privateSession + ') ORDER BY code').bind(session, identity.id).all()).results
    });
    if (request.method !== 'POST') return issue('Método no permitido.', 405);
    if (request.headers.get('origin') !== url.origin) return issue('Origen no autorizado.', 403);
    if (!request.headers.get('content-type')?.startsWith('application/json')) return issue('Se requiere JSON.', 415);
    if (Number(request.headers.get('content-length')) > 16384) return issue('Solicitud demasiado grande.', 413);
    const reader = request.body?.getReader();
    if (!reader) return issue('Faltan datos.', 400);
    const chunks: Uint8Array[] = [];
    let size = 0;
    for (;;) {
      const {
        done,
        value
      } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 16384) {
        await reader.cancel();
        return issue('Solicitud demasiado grande.', 413);
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let at = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, at);
      at += chunk.length;
    }
    const body: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (command === 'unlock') {
      const input = z.object({
        password: z.string().min(1).max(512)
      }).strict().parse(body);
      await rateLimit(request, 'attendance-supervision');
      // The isolated fixture provides a separate supervisor verifier. It cannot start a JAC session.
      const op = await passwordLogin('operador', input.password);
      if (!op || op.attendance_role !== 'operator') return issue('Clave de supervisión incorrecta.', 403);
      const ticket = randomToken(),
        expires = new Date(Date.now() + 5 * 60_000).toISOString();
      const result = await db.batch([db.prepare('DELETE FROM attendance_operator_grants WHERE expires_at<=?').bind(new Date().toISOString()), db.prepare(`INSERT INTO attendance_operator_grants SELECT ?,?,id,version,? FROM payroll_users WHERE id=? AND version=? AND active=1 AND attendance_role='operator' AND EXISTS(${privateSession})`).bind(tokenHash(ticket), session, expires, op.id, op.version, session, identity.id)]);
      if (!result[1].meta.changes) return issue('La sesión cambió.', 403);
      return reply({
        ticket,
        expires,
        name: op.name
      });
    }
    if (command === 'lock') {
      await db.prepare('DELETE FROM attendance_operator_grants WHERE id=? AND session=?').bind(ctx.gate[0], session).run();
      return reply({
        ok: true
      });
    }
    if (command === 'status') {
      const {
        ids
      } = z.object({
        ids: z.array(uuid).min(1).max(30)
      }).strict().parse(body);
      const rows = await db.prepare(`SELECT id,review_state AS state FROM (${history}) WHERE actor=? AND id IN (SELECT value FROM json_each(?)) AND EXISTS(${privateSession})`).bind(identity.id, JSON.stringify(ids), session, identity.id).all();
      return reply({
        records: rows.results
      });
    }
    if (command === 'punch') return await recordPunch(ctx, punchInput.parse(body));
    return await management(ctx, command, body);
  } catch (e) {
    if (e instanceof z.ZodError || e instanceof SyntaxError) return issue('Revisa los datos de la operación.', 400);
    if (e instanceof Error && e.message === 'RATE_LIMIT') return issue('Espera antes de volver a autenticarte.', 429);
    return issue('Servicio temporalmente no disponible.', 503);
  }
}
