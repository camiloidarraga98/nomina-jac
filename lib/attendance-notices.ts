import { createHmac, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { sectionSql } from './payroll-permissions';

const localTime = new Intl.DateTimeFormat('es-CO', {
  dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/Bogota'
});
export const attendancePhotoName = 'Foto de la marcación.jpg';
export const attendanceSource = "COALESCE(n.source,'') GLOB 'attendance:*'";
export const attendanceRecipient = (user: string) =>
  `${user}.email IN ('camilo@mac2you.co','jhonalexcastano@gmail.com')`;
const currentSession = `s.user_id=d.user_id AND s.user_version=d.user_version AND
  (s.persistent=1 OR s.expires_at>strftime('%Y-%m-%dT%H:%M:%fZ','now'))`;
const deliveryId = "n.id||'|'||d.id||'|'||d.session_id";
// An installation can be registered again under another account or session.
export const attendanceDelivery = `p.id=(${deliveryId}) AND EXISTS(
  SELECT 1 FROM payroll_sessions s WHERE s.id=d.session_id AND ${currentSession})`;

// These statements run in the same batch as the signed punch. Only a newly
// inserted record owns this fresh notice ID, including after a lost response.
export function attendanceNoticeStatements(db: D1Database, record: string, notice: string,
                                          movement: 'entry' | 'exit', occurredAt: string) {
  const entry = movement === 'entry';
  const message = entry ? ' acaba de registrar su ingreso a laborar.' : ' acaba de registrar su salida de JAC Music.';
  const detail = message + '\n' + localTime.format(new Date(occurredAt)) + ' · Hora de Colombia';
  return [
    db.prepare(`INSERT INTO jac_notices(id,kind,title,body,source,created_at,filename,size)
      SELECT r.notice_id,'alert',?,e.name||?,'attendance:'||r.id,r.received_at,
        CASE WHEN r.photo_jpeg IS NOT NULL THEN ? ELSE '' END,coalesce(length(r.photo_jpeg),0)
      FROM jac_attendance_records r JOIN jac_attendance_people e ON e.id=r.employee
      WHERE r.id=? AND r.notice_id=? AND r.device IS NOT NULL`)
      .bind(entry ? 'JAC Music · Entrada' : 'JAC Music · Salida', detail, attendancePhotoName, record, notice),
    db.prepare(`INSERT INTO jac_notice_recipients(id,notice_id,user_id)
      SELECT n.id||'|'||u.id,n.id,u.id FROM jac_notices n CROSS JOIN payroll_users u
      WHERE n.id=? AND n.source=? AND ${attendanceRecipient('u')}
        AND u.active=1 AND u.password_hash<>'' AND ${sectionSql('u','alerts')}`).bind(notice,'attendance:'+record),
    db.prepare(`INSERT INTO jac_push_deliveries(id,notice_id,device_id,updated_at)
      SELECT ${deliveryId},n.id,d.id,n.created_at FROM jac_notices n
      JOIN jac_notice_recipients r ON r.notice_id=n.id AND r.push_target=1
      JOIN payroll_users u ON u.id=r.user_id
      JOIN jac_push_devices d ON d.user_id=u.id AND d.user_version=u.version AND d.enabled=1
      JOIN payroll_sessions s ON s.id=d.session_id AND ${currentSession}
      WHERE n.id=? AND n.source=?`).bind(notice,'attendance:'+record)
  ];
}

type PreviewDevice = { device: string; session: string; user: string };
const uuid = z.string().uuid();
const previewLifetime = 24 * 60 * 60;
function previewMac(key: string, notice: string, device: PreviewDevice, expires: number) {
  return createHmac('sha256',key).update(
    ['jac-attendance-photo-v1',notice,device.device,device.user,device.session,expires].join('\n')
  ).digest();
}
export function attendancePhotoGrant(key: string, notice: string, device: PreviewDevice) {
  const expires = Math.floor(Date.now()/1000) + previewLifetime;
  return [device.device,expires,previewMac(key,notice,device,expires).toString('base64url')].join('.');
}

// The notification extension can fetch one portrait without sharing a payroll login.
// Recheck the current device session and recipient before returning any JPEG bytes.
export async function attendancePushPhoto(db: D1Database, key: string, notice: string, header: string) {
  const match = /^JAC-Photo ([a-fA-F0-9-]{36})\.(\d{10})\.([\w-]{43})$/.exec(header);
  if (!match || !uuid.safeParse(notice).success || !uuid.safeParse(match[1]).success) return null;
  const now = Math.floor(Date.now()/1000), expires = Number(match[2]);
  if (expires <= now || expires > now + previewLifetime) return null;
  const gate = `FROM jac_notices n JOIN jac_push_deliveries p ON p.notice_id=n.id
    JOIN jac_push_devices d ON d.id=p.device_id AND d.enabled=1 AND d.platform='ios'
    JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version
    JOIN jac_notice_recipients a ON a.notice_id=n.id AND a.user_id=u.id AND a.push_target=1
    JOIN jac_attendance_records r ON r.id=substr(n.source,length('attendance:')+1) AND r.notice_id=n.id
    WHERE n.id=? AND d.id=? AND ${attendanceSource} AND n.kind='alert'
      AND p.status IN ('sending','sent','uncertain') AND ${attendanceDelivery}
      AND ${attendanceRecipient('u')} AND u.active=1 AND u.password_hash<>'' AND ${sectionSql('u','alerts')}`;
  const device = await db.prepare('SELECT d.id AS device,d.session_id AS session,u.id AS user '+gate)
    .bind(notice,match[1]).first<PreviewDevice>();
  if (!device || !timingSafeEqual(previewMac(key,notice,device,expires),Buffer.from(match[3],'base64url'))) return null;
  const row = await db.prepare('SELECT r.photo_jpeg AS jpeg '+gate+' AND d.session_id=? AND u.id=? AND r.photo_jpeg IS NOT NULL')
    .bind(notice,device.device,device.session,device.user).first<{ jpeg: number[] | ArrayBuffer }>();
  return row ? new Uint8Array(row.jpeg) : null;
}
