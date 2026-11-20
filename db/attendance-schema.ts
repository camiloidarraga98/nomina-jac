import { sql } from 'drizzle-orm';
import { blob, check, customType, index, integer, sqliteTable, text, unique } from 'drizzle-orm/sqlite-core';

const employeeCode = customType<{ data: string }>({ dataType: () => 'text COLLATE NOCASE' });

export const attendancePeople = sqliteTable('jac_attendance_people', {
  id: text('id').primaryKey().notNull(),
  code: employeeCode('code').notNull().unique(),
  removedCode: text('removed_code'),
  name: text('name').notNull(),
  active: integer('active').notNull().default(1),
  faceRevision: integer('face_revision').notNull().default(1),
  createdBy: text('created_by').notNull(),
});

export const attendanceDevices = sqliteTable('jac_attendance_devices', {
  id: text('id').primaryKey().notNull(),
  secretHash: text('secret_hash').notNull().unique(),
  name: text('name').notNull(),
  active: integer('active').notNull().default(1),
  createdBy: text('created_by').notNull(),
});

export const attendanceEnrollments = sqliteTable('jac_attendance_enrollments', {
  id: text('id').primaryKey().notNull(),
  employee: text('employee').notNull().references(() => attendancePeople.id),
  device: text('device').notNull().references(() => attendanceDevices.id),
  revision: integer('revision').notNull(),
  enrolledBy: text('enrolled_by').notNull(),
  publicKey: text('public_key').notNull(),
  createdAt: text('created_at').notNull(),
}, (t) => [unique().on(t.employee, t.device, t.revision)]);

export const attendanceRecords = sqliteTable('jac_attendance_records', {
  id: text('id').primaryKey().notNull(),
  employee: text('employee').notNull().references(() => attendancePeople.id),
  movement: text('movement').notNull(),
  occurredAt: text('occurred_at').notNull(),
  receivedAt: text('received_at').notNull(),
  device: text('device').references(() => attendanceDevices.id),
  enrollment: text('enrollment').references(() => attendanceEnrollments.id),
  supervisor: text('supervisor'),
  reason: text('reason'),
  possibleDuplicate: integer('possible_duplicate').notNull().default(0),
  photoJpeg: blob('photo_jpeg', { mode: 'buffer' }),
  noticeId: text('notice_id'),
}, (t) => [
  check('attendance_record_movement', sql`movement IN ('entry','exit')`),
  check('attendance_record_source', sql`(device IS NOT NULL AND enrollment IS NOT NULL AND supervisor IS NULL)
    OR (device IS NULL AND enrollment IS NULL AND supervisor IS NOT NULL AND reason IS NOT NULL)`),
  index('jac_attendance_history').on(sql`"occurred_at" DESC`, sql`"id" DESC`),
  index('jac_attendance_by_employee').on(t.employee, sql`"occurred_at" DESC`),
]);

export const attendanceReviews = sqliteTable('jac_attendance_reviews', {
  id: text('id').primaryKey().notNull(),
  record: text('record').notNull().references(() => attendanceRecords.id),
  revision: integer('revision').notNull(),
  movement: text('movement').notNull(),
  occurredAt: text('occurred_at').notNull(),
  reason: text('reason').notNull(),
  supervisor: text('supervisor').notNull(),
  reviewedAt: text('reviewed_at').notNull(),
}, (t) => [
  unique().on(t.record, t.revision),
  check('attendance_review_movement', sql`movement IN ('entry','exit')`),
]);
