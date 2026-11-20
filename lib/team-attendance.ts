import { z } from 'zod';
import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
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
const maxPhotoBytes = 96 * 1024;
const devicePunch = z
  .object({
    id: uuid,
    employee: uuid,
    enrollment: uuid,
    movement,
    occurredAt: moment,
    photo: z.string().min(8).max(4 * Math.ceil(maxPhotoBytes / 3)).optional(),
    signature: z.string().regex(/^[A-Za-z0-9+/]{86}==$/)
  })
  .strict();
const actions = z.discriminatedUnion('action', [
  z.object({ action: z.literal('person'), id: uuid, code: z.string().trim().min(1).max(32), name }).strict(),
  z.object({ action: z.literal('archive'), employee: uuid, revision: z.number().int().positive() }).strict(),
  z.object({ action: z.literal('removePerson'), employee: uuid, revision: z.number().int().positive() }).strict(),
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

async function bodyOf(request: Request, maxBytes = 4096) {
  if (request.headers.get('content-type')?.split(';')[0].trim() !== 'application/json')
    throw new Error('body');
  const reader = request.body?.getReader();
  if (!reader) throw new Error('body');
  const bytes = new Uint8Array(maxBytes);
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
const history = `SELECT r.id,r.employee,p.name AS employeeName,COALESCE(p.removed_code,p.code) AS code,COALESCE(v.movement,r.movement) AS movement,${effectiveTime} AS occurredAt, r.movement AS originalMovement, r.occurred_at AS originalTime, COALESCE(v.revision,0) AS revision,
 r.received_at AS receivedAt,d.name AS deviceName,u.name AS supervisor,r.reason,r.possible_duplicate AS possibleDuplicate,r.photo_jpeg IS NOT NULL AS hasPhoto
 FROM jac_attendance_records r JOIN jac_attendance_people p ON p.id=r.employee
 LEFT JOIN jac_attendance_devices d ON d.id=r.device LEFT JOIN payroll_users u ON u.id=r.supervisor
 LEFT JOIN jac_attendance_reviews v ON v.record=r.id AND v.revision=(SELECT max(revision) FROM jac_attendance_reviews WHERE record=r.id)`;
async function adminFeed(db: D1Database, hash: string, params: URLSearchParams) {
  if (params.has('photo')) {
    const record = uuid.safeParse(params.get('photo'));
    if (!record.success) return error('Registro no válido.', 400);
    const row = await db.prepare('SELECT photo_jpeg AS jpeg FROM jac_attendance_records WHERE id=? AND photo_jpeg IS NOT NULL AND EXISTS(' + adminQuery + ')')
      .bind(record.data, hash).first<{ jpeg: number[] | ArrayBuffer }>();
    if (!row) return error('Esta marcación no tiene foto disponible.', 404);
    return json({ jpeg: Buffer.from(new Uint8Array(row.jpeg)).toString('base64') });
  }
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
        'SELECT id,COALESCE(removed_code,code) AS code,name,active,face_revision AS revision,removed_code IS NOT NULL AS removed FROM jac_attendance_people WHERE EXISTS(' +
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
    people: people.results.filter((person) => !person.removed),
    formerPeople: people.results.filter((person) => person.removed).map(({ id, code, name }) => ({ id, code, name })),
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
    case 'removePerson': {
      const target = `id=? AND face_revision=? AND removed_code IS NULL AND EXISTS(${adminQuery})`;
      const unused = target +
        ' AND NOT EXISTS(SELECT 1 FROM jac_attendance_records r WHERE r.employee=jac_attendance_people.id)';
      const keys = [input.employee, input.revision, hash];
      // D1 commits the roster change together with any cleanup. A simultaneous punch either
      // creates history first or sees an ineligible enrollment.
      const [, , , state] = await db.batch<{ outcome: 'deleted' | 'history' | null }>([
        db.prepare(`DELETE FROM jac_attendance_enrollments WHERE employee IN
          (SELECT id FROM jac_attendance_people WHERE ${unused})`).bind(...keys),
        db.prepare('DELETE FROM jac_attendance_people WHERE ' + unused).bind(...keys),
        // Keep the original code for history and free the unique roster code. UUIDs are 36
        // characters; a user-supplied employee code has at most 32.
        db.prepare(`UPDATE jac_attendance_people SET removed_code=code,code=id,active=0,
          face_revision=face_revision+1 WHERE ${target}`).bind(...keys),
        db.prepare(`SELECT CASE WHEN p.id IS NULL THEN 'deleted' WHEN p.removed_code IS NOT NULL THEN 'history' END AS outcome
          FROM (${adminQuery}) a LEFT JOIN jac_attendance_people p ON p.id=?`).bind(hash, input.employee)
      ]);
      const receipt = state.results[0];
      if (!receipt) return error('Se requiere acceso de administración.', 403);
      return receipt.outcome ? json({ outcome: receipt.outcome }) : conflict();
    }
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
// The native camera produces a cropped JPEG with a longest side of at most 360 px.
function checkedPortrait(encoded: string): Buffer | null {
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.length < 12 || bytes.length > maxPhotoBytes || bytes.toString('base64') !== encoded ||
      bytes.readUInt16BE(0) !== 0xffd8 || bytes.readUInt16BE(bytes.length - 2) !== 0xffd9) return null;
  for (let i = 2; i + 9 < bytes.length && bytes[i] === 0xff;) {
    const marker = bytes[i + 1], length = bytes.readUInt16BE(i + 2);
    if (length < 2 || i + 2 + length > bytes.length || marker === 0xda) return null;
    if ([0xc0, 0xc1, 0xc2].includes(marker)) {
      const height = bytes.readUInt16BE(i + 5), width = bytes.readUInt16BE(i + 7);
      return length >= 8 && height > 0 && width > 0 && Math.max(height, width) <= 512 ? bytes : null;
    }
    i += 2 + length;
  }
  return null;
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
  const input = devicePunch.parse(await bodyOf(request, 4 * Math.ceil(maxPhotoBytes / 3) + 4096));
  const photo = input.photo ? checkedPortrait(input.photo) : null;
  if (input.photo && !photo) return error('La foto de la marcación no es un JPEG válido.', 400);
  const photoHash = photo ? createHash('sha256').update(photo).digest('hex') : null;
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
    photo ? 'jac-attendance-v2' : 'jac-attendance-v1',
    device,
    input.employee,
    input.enrollment,
    input.id,
    input.movement,
    input.occurredAt,
    ...(photoHash ? [photoHash] : [])
  ].join('\n');
  const verified = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    await enrollmentKey(ref.public_key),
    fromBase64(input.signature),
    new TextEncoder().encode(signed)
  );
  if (!verified) return conflict();
  const now = new Date().toISOString();
  const jpeg = photo ? Uint8Array.from(photo).buffer : null;
  const [, receipt] = await db.batch<Row>([
    db
      .prepare(
        `INSERT INTO jac_attendance_records(id,employee,movement,occurred_at,received_at,device,enrollment,photo_jpeg,possible_duplicate)
      SELECT ?,e.employee,?,?,?,e.device,e.id,?,${duplicate} FROM jac_attendance_enrollments e
      JOIN jac_attendance_people p ON e.employee=p.id AND e.revision=p.face_revision AND p.active=1
      WHERE e.employee=? AND e.id=? AND e.device=? AND julianday(e.created_at,'+30 days')>julianday('now') AND EXISTS(${deviceQuery}) ON CONFLICT(id) DO NOTHING`
      )
      .bind(
        input.id,
        input.movement,
        input.occurredAt,
        now,
        jpeg,
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
        'SELECT id,received_at AS receivedAt FROM jac_attendance_records WHERE id=? AND employee=? AND movement=? AND occurred_at=? AND device=? AND enrollment=? AND photo_jpeg IS ? AND EXISTS(' +
          deviceQuery +
          ')'
      )
      .bind(input.id, input.employee, input.movement, input.occurredAt, device, input.enrollment, jpeg, ...keys)
  ]);
  return receipt.results[0] ? json({ ...receipt.results[0], ...(photoHash ? { photoHash } : {}) }) : conflict();
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
        "default-src 'none'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src blob:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
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
