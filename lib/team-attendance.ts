import { z } from 'zod';
import { sessionToken, tokenHash } from './payroll-auth-crypto';
import { sectionSql } from './payroll-permissions';

const prefix = '/api/team-attendance/';
const adminQuery = `SELECT u.id FROM payroll_sessions s JOIN payroll_users u ON u.id=s.user_id AND u.version=s.user_version
  WHERE s.id=? AND (s.persistent=1 OR s.expires_at>strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  AND u.active=1 AND u.password_hash<>'' AND ${sectionSql('u', 'crm')}`;
const deviceQuery = 'SELECT id FROM jac_attendance_devices WHERE id=? AND secret_hash=? AND active=1';
const uuid = z
  .string()
  .uuid()
  .transform((s) => s.toLowerCase());
const name = z.string().trim().min(1).max(80);
const moment = z
  .string()
  .datetime({ offset: true })
  .transform((v) => new Date(v).toISOString());
const movement = z.enum(['entry', 'exit']);
const devicePunch = z
  .object({
    id: uuid,
    employee: uuid,
    enrollment: uuid,
    movement,
    occurredAt: moment,
    signature: z.string().regex(/^[A-Za-z0-9+/]{86}==$/)
  })
  .strict();
const actions = z.discriminatedUnion('action', [
  z.object({ action: z.literal('person'), id: uuid, code: z.string().trim().min(1).max(32), name }).strict(),
  z.object({ action: z.literal('archive'), employee: uuid, revision: z.number().int().positive() }).strict(),
  z
    .object({ action: z.literal('resetFace'), employee: uuid, revision: z.number().int().positive() })
    .strict(),
  z.object({ action: z.literal('pair'), id: uuid, hash: z.string().regex(/^[0-9a-f]{64}$/), name }).strict(),
  z.object({ action: z.literal('revoke'), id: uuid }).strict(),
  z
    .object({
      action: z.literal('enroll'),
      id: uuid,
      employee: uuid,
      device: uuid,
      revision: z.number().int().positive(),
      publicKey: z.string().regex(/^[A-Za-z0-9+/]{87}=$/)
    })
    .strict(),
  z
    .object({
      action: z.literal('review'),
      id: uuid,
      record: uuid,
      revision: z.number().int().nonnegative(),
      movement,
      occurredAt: moment,
      reason: z.string().trim().min(3).max(240)
    })
    .strict(),
  z
    .object({
      action: z.literal('manual'),
      id: uuid,
      employee: uuid,
      movement,
      occurredAt: moment,
      reason: z.string().trim().min(3).max(240)
    })
    .strict()
]);
const privateHeaders = {
  'Cache-Control': 'private, no-store',
  'X-Content-Type-Options': 'nosniff',
  'X-Robots-Tag': 'noindex, nofollow',
  'Referrer-Policy': 'no-referrer'
};
const json = (body: unknown, status = 200) => Response.json(body, { status, headers: privateHeaders });
const error = (message: string, status: number) => json({ error: message }, status);
const conflict = () => error('El registro cambió o ya existe. Actualiza los datos antes de continuar.', 409);
type Env = { DB: D1Database; ASSETS: Fetcher };
type Row = Record<string, string | number | null>;

async function bodyOf(request: Request) {
  if (request.headers.get('content-type')?.split(';')[0].trim() !== 'application/json')
    throw new Error('body');
  const reader = request.body?.getReader();
  if (!reader) throw new Error('body');
  const bytes = new Uint8Array(4096);
  let count = 0;
  for (;;) {
    const part = await reader.read();
    if (part.done) break;
    if (count + part.value.length > bytes.length) {
      await reader.cancel();
      throw new Error('body');
    }
    bytes.set(part.value, count);
    count += part.value.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes.subarray(0, count)));
}

const effectiveTime = 'COALESCE(v.occurred_at,r.occurred_at)';
const history = `SELECT r.id,r.employee,p.name AS employeeName,p.code,COALESCE(v.movement,r.movement) AS movement,${effectiveTime} AS occurredAt, r.movement AS originalMovement, r.occurred_at AS originalTime, COALESCE(v.revision,0) AS revision,
 r.received_at AS receivedAt,d.name AS deviceName,u.name AS supervisor,r.reason,r.possible_duplicate AS possibleDuplicate
 FROM jac_attendance_records r JOIN jac_attendance_people p ON p.id=r.employee
 LEFT JOIN jac_attendance_devices d ON d.id=r.device LEFT JOIN payroll_users u ON u.id=r.supervisor
 LEFT JOIN jac_attendance_reviews v ON v.record=r.id AND v.revision=(SELECT max(revision) FROM jac_attendance_reviews WHERE record=r.id)`;
async function adminFeed(db: D1Database, hash: string, params: URLSearchParams) {
  const audit = params.get('record');
  if (audit) {
    if (!uuid.safeParse(audit).success) return error('Registro no válido.', 400);
    const rows = await db
      .prepare(
        'SELECT v.revision,v.movement,v.occurred_at AS occurredAt,v.reason,v.reviewed_at AS reviewedAt,u.name AS reviewer FROM jac_attendance_reviews v JOIN payroll_users u ON u.id=v.supervisor WHERE record=? AND EXISTS(' +
          adminQuery +
          ') ORDER BY revision'
      )
      .bind(audit, hash)
      .all();
    return json({ reviews: rows.results });
  }
  const employee = params.get('employee') || '',
    day = params.get('day') || '',
    cursor = params.get('cursor') || '';
  if ((employee && !uuid.safeParse(employee).success) || (day && !/^\d{4}-\d{2}-\d{2}$/.test(day)))
    return error('Filtro no válido.', 400);
  const where = [`EXISTS(${adminQuery})`],
    args: string[] = [hash];
  if (employee) {
    where.push('r.employee=?');
    args.push(employee);
  }
  if (day) {
    const start = new Date(day + 'T00:00:00-05:00');
    if (!Number.isFinite(+start) || start.toISOString().slice(0, 10) !== day)
      return error('Fecha no válida.', 400);
    where.push(effectiveTime + '>=? AND ' + effectiveTime + '<?');
    args.push(start.toISOString(), new Date(+start + 86400000).toISOString());
  }
  if (cursor) {
    const [time, id] = cursor.split('|');
    if (!moment.safeParse(time).success || !uuid.safeParse(id).success || cursor.split('|').length !== 2)
      return error('Página no válida.', 400);
    where.push('(' + effectiveTime + ',r.id)<(?,?)');
    args.push(time, id);
  }
  const [people, devices, records] = await db.batch<Row>([
    db
      .prepare(
        'SELECT id,code,name,active,face_revision AS revision FROM jac_attendance_people WHERE EXISTS(' +
          adminQuery +
          ') ORDER BY active DESC,name COLLATE NOCASE,code'
      )
      .bind(hash),
    db
      .prepare(
        'SELECT id,name,active FROM jac_attendance_devices WHERE EXISTS(' +
          adminQuery +
          ') ORDER BY active DESC,name COLLATE NOCASE'
      )
      .bind(hash),
    db
      .prepare(
        history + ' WHERE ' + where.join(' AND ') + ' ORDER BY ' + effectiveTime + ' DESC,r.id DESC LIMIT 51'
      )
      .bind(...args)
  ]);
  const rows = records.results.slice(0, 50),
    last = rows.at(-1);
  return json({
    people: people.results,
    devices: devices.results,
    records: rows,
    nextCursor: records.results.length > 50 && last ? last.occurredAt + '|' + last.id : null
  });
}

const duplicate =
  'EXISTS(SELECT 1 FROM jac_attendance_records WHERE employee=? AND movement=? AND ABS(unixepoch(occurred_at)-unixepoch(?))<=90)';
async function adminWrite(db: D1Database, hash: string, input: z.infer<typeof actions>, request: Request) {
  let stmt: D1PreparedStatement;
  switch (input.action) {
    case 'person':
      stmt = db
        .prepare(
          'INSERT INTO jac_attendance_people(id,code,name,created_by) SELECT ?,?,?,a.id FROM (' +
            adminQuery +
            ') a WHERE 1 ON CONFLICT DO NOTHING'
        )
        .bind(input.id, input.code, input.name, hash);
      break;
    case 'archive':
    case 'resetFace':
      stmt = db
        .prepare(
          'UPDATE jac_attendance_people SET face_revision=face_revision+1' +
            (input.action === 'archive' ? ',active=0' : '') +
            ' WHERE id=? AND active=1 AND face_revision=? AND EXISTS(' +
            adminQuery +
            ')'
        )
        .bind(input.employee, input.revision, hash);
      break;
    case 'pair': {
      const [insert, existing] = await db.batch([
        db
          .prepare(
            'INSERT INTO jac_attendance_devices(id,secret_hash,name,created_by) SELECT ?,?,?,a.id FROM (' +
              adminQuery +
              ') a WHERE 1 ON CONFLICT DO NOTHING'
          )
          .bind(input.id, input.hash, input.name, hash),
        db
          .prepare(
            'SELECT id FROM jac_attendance_devices WHERE id=? AND secret_hash=? AND active=1 AND EXISTS(' +
              adminQuery +
              ')'
          )
          .bind(input.id, input.hash, hash)
      ]);
      return insert.meta.changes || existing.results.length ? json({ id: input.id }) : conflict();
    }
    case 'revoke':
      stmt = db
        .prepare(
          'UPDATE jac_attendance_devices SET active=0 WHERE id=? AND active=1 AND EXISTS(' + adminQuery + ')'
        )
        .bind(input.id, hash);
      break;
    case 'enroll': {
      const secret = request.headers.get('x-jac-kiosk-token') || '';
      if (!/^[a-f0-9]{64}$/.test(secret))
        return error('Vincula este kiosco antes de inscribir un rostro.', 403);
      try {
        await enrollmentKey(input.publicKey);
      } catch {
        return error('La clave de inscripción no es válida.', 400);
      }
      const conditions = `EXISTS(${deviceQuery}) AND EXISTS(SELECT 1 FROM jac_attendance_people WHERE id=? AND active=1 AND face_revision=?)`;
      const keys = [input.device, tokenHash(secret), input.employee, input.revision];
      const [, valid] = await db.batch([
        db
          .prepare(
            'INSERT INTO jac_attendance_enrollments(id,employee,device,revision,enrolled_by,public_key,created_at) SELECT ?,?,?,?,a.id,?,? FROM (' +
              adminQuery +
              ') a WHERE ' +
              conditions +
              ' ON CONFLICT DO NOTHING'
          )
          .bind(
            input.id,
            input.employee,
            input.device,
            input.revision,
            input.publicKey,
            new Date().toISOString(),
            hash,
            ...keys
          ),
        db
          .prepare(
            'SELECT id FROM jac_attendance_enrollments WHERE id=? AND employee=? AND device=? AND revision=? AND public_key=? AND EXISTS(' +
              adminQuery +
              ') AND ' +
              conditions
          )
          .bind(input.id, input.employee, input.device, input.revision, input.publicKey, hash, ...keys)
      ]);
      return valid.results.length ? json({ id: input.id }) : conflict();
    }
    case 'review': {
      const [, saved] = await db.batch([
        db
          .prepare(
            `INSERT INTO jac_attendance_reviews(id,record,revision,movement,occurred_at,reason,supervisor,reviewed_at)
          SELECT ?,r.id,?,?,?,?,a.id,? FROM jac_attendance_records r,(${adminQuery}) a
          WHERE r.id=? AND COALESCE((SELECT MAX(revision) FROM jac_attendance_reviews WHERE record=r.id),0)=?
          ON CONFLICT DO NOTHING`
          )
          .bind(
            input.id,
            input.revision + 1,
            input.movement,
            input.occurredAt,
            input.reason,
            new Date().toISOString(),
            hash,
            input.record,
            input.revision
          ),
        db
          .prepare(
            'SELECT id FROM jac_attendance_reviews WHERE id=? AND record=? AND revision=? AND movement=? AND occurred_at=? AND reason=? AND supervisor=(' +
              adminQuery +
              ')'
          )
          .bind(
            input.id,
            input.record,
            input.revision + 1,
            input.movement,
            input.occurredAt,
            input.reason,
            hash
          )
      ]);
      return saved.results.length ? json({ id: input.id }) : conflict();
    }
    case 'manual': {
      const [, saved] = await db.batch([
        db
          .prepare(
            `INSERT INTO jac_attendance_records(id,employee,movement,occurred_at,received_at,supervisor,reason,possible_duplicate)
          SELECT ?,?,?,?,?,a.id,?,${duplicate} FROM (${adminQuery}) a WHERE EXISTS(SELECT 1 FROM jac_attendance_people WHERE id=? AND active=1)
          ON CONFLICT(id) DO NOTHING`
          )
          .bind(
            input.id,
            input.employee,
            input.movement,
            input.occurredAt,
            new Date().toISOString(),
            input.reason,
            input.employee,
            input.movement,
            input.occurredAt,
            hash,
            input.employee
          ),
        db
          .prepare(
            'SELECT id FROM jac_attendance_records WHERE id=? AND employee=? AND movement=? AND occurred_at=? AND reason=? AND supervisor=(' +
              adminQuery +
              ')'
          )
          .bind(input.id, input.employee, input.movement, input.occurredAt, input.reason, hash)
      ]);
      return saved.results.length ? json({ id: input.id }) : conflict();
    }
  }
  const result = await stmt.run();
  return result.meta.changes ? json({ ok: true }) : conflict();
}

const fromBase64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
function enrollmentKey(encoded: string) {
  return crypto.subtle.importKey('raw', fromBase64(encoded), { name: 'ECDSA', namedCurve: 'P-256' }, false, [
    'verify'
  ]);
}
async function kiosk(request: Request, db: D1Database) {
  const device = request.headers.get('x-jac-device') || '',
    authorization = request.headers.get('authorization') || '';
  const token = /^JAC-Kiosk ([a-f0-9]{64})$/.exec(authorization)?.[1];
  if (!token || !uuid.safeParse(device).success) return error('Kiosco sin autorización.', 403);
  const keys = [device, tokenHash(token)];
  if (
    !(await db
      .prepare(deviceQuery)
      .bind(...keys)
      .first())
  )
    return error('La autorización de este kiosco está desactivada.', 403);
  if (request.method === 'GET') {
    const people = await db
      .prepare(
        `SELECT p.id,p.code,p.name,p.face_revision AS revision,e.id AS enrollment FROM jac_attendance_people p
      LEFT JOIN jac_attendance_enrollments e ON e.employee=p.id AND e.device=? AND e.revision=p.face_revision
      WHERE p.active=1 AND EXISTS(${deviceQuery}) ORDER BY p.name COLLATE NOCASE,p.code`
      )
      .bind(device, ...keys)
      .all();
    return json({ people: people.results });
  }
  const input = devicePunch.parse(await bodyOf(request));
  const ref = await db
    .prepare(
      'SELECT public_key FROM jac_attendance_enrollments WHERE id=? AND device=? AND employee=? AND EXISTS(' +
        deviceQuery +
        ')'
    )
    .bind(input.enrollment, device, input.employee, ...keys)
    .first<{ public_key: string }>();
  if (!ref) return conflict();
  const signed = [
    'jac-attendance-v1',
    device,
    input.employee,
    input.enrollment,
    input.id,
    input.movement,
    input.occurredAt
  ].join('\n');
  const verified = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    await enrollmentKey(ref.public_key),
    fromBase64(input.signature),
    new TextEncoder().encode(signed)
  );
  if (!verified) return conflict();
  const now = new Date().toISOString();
  const [, receipt] = await db.batch<Row>([
    db
      .prepare(
        `INSERT INTO jac_attendance_records(id,employee,movement,occurred_at,received_at,device,enrollment,possible_duplicate)
      SELECT ?,e.employee,?,?,?,e.device,e.id,${duplicate} FROM jac_attendance_enrollments e
      JOIN jac_attendance_people p ON e.employee=p.id AND e.revision=p.face_revision AND p.active=1
      WHERE e.employee=? AND e.id=? AND e.device=? AND julianday(e.created_at,'+30 days')>julianday('now') AND EXISTS(${deviceQuery}) ON CONFLICT(id) DO NOTHING`
      )
      .bind(
        input.id,
        input.movement,
        input.occurredAt,
        now,
        input.employee,
        input.movement,
        input.occurredAt,
        input.employee,
        input.enrollment,
        device,
        ...keys
      ),
    db
      .prepare(
        'SELECT id,received_at AS receivedAt FROM jac_attendance_records WHERE id=? AND employee=? AND movement=? AND occurred_at=? AND device=? AND enrollment=? AND EXISTS(' +
          deviceQuery +
          ')'
      )
      .bind(input.id, input.employee, input.movement, input.occurredAt, device, input.enrollment, ...keys)
  ]);
  return receipt.results[0] ? json(receipt.results[0]) : conflict();
}

export async function teamAttendance(request: Request, env: Env): Promise<Response | null> {
  const url = new URL(request.url),
    path = url.pathname;
  const panel = [
    '/asistencia-equipo',
    '/asistencia-equipo/',
    '/asistencia-equipo/team.js',
    '/asistencia-equipo/team.css'
  ].includes(path);
  if (!panel && !path.startsWith(prefix)) return null;
  if (!(panel ? ['GET', 'HEAD'] : ['GET', 'POST']).includes(request.method))
    return error('Método no disponible.', 405);
  try {
    if (path === prefix + 'kiosk') return await kiosk(request, env.DB);
    if (!panel && path !== prefix + 'admin') return error('Ruta no disponible.', 404);
    const bearer = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(request.headers.get('authorization') || '')?.[1];
    const token = bearer || sessionToken(request.headers.get('cookie') || '', url.protocol === 'https:');
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
      if (panel && !path.includes('.'))
        return new Response(null, {
          status: 303,
          headers: { ...privateHeaders, Location: '/acceso?returnTo=%2Fasistencia-equipo%2F' }
        });
      return error('Inicia sesión con tu cuenta administradora.', 401);
    }
    const hash = tokenHash(token);
    if (!(await env.DB.prepare(adminQuery).bind(hash).first()))
      return error('Se requiere una sesión administradora de JAC.', 403);
    if (panel) {
      if (path === '/asistencia-equipo')
        return new Response(null, {
          status: 308,
          headers: { ...privateHeaders, Location: '/asistencia-equipo/' }
        });
      url.pathname = '/attendance/' + (path.split('/').at(-1) || 'team.html');
      let asset = await env.ASSETS.fetch(new Request(url, { method: request.method }));
      if (url.pathname === '/attendance/team.html' && [301, 302, 307, 308].includes(asset.status)) {
        const canonical = new URL(asset.headers.get('location') || url.href, url);
        if (canonical.origin === url.origin && canonical.pathname === '/attendance/team') {
          asset = await env.ASSETS.fetch(new Request(canonical, { method: request.method }));
        }
      }
      const headers = new Headers(asset.headers);
      for (const [key, value] of Object.entries(privateHeaders)) headers.set(key, value);
      headers.set(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'self'; script-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
      );
      return new Response(asset.body, { status: asset.status, headers });
    }
    if (request.method === 'GET') return await adminFeed(env.DB, hash, url.searchParams);
    if (!bearer && request.headers.get('origin') !== url.origin)
      return error('Solicitud de origen no válido.', 403);
    return await adminWrite(env.DB, hash, actions.parse(await bodyOf(request)), request);
  } catch (cause) {
    if (
      cause instanceof z.ZodError ||
      cause instanceof SyntaxError ||
      (cause instanceof Error && cause.message === 'body')
    )
      return error('Revisa los datos enviados.', 400);
    return error('Asistencia no pudo consultar el servidor. Vuelve a intentarlo.', 503);
  }
}
