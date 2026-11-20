CREATE TABLE jac_attendance_people (
  id TEXT PRIMARY KEY NOT NULL,
  code TEXT NOT NULL COLLATE NOCASE UNIQUE,
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  face_revision INTEGER NOT NULL DEFAULT 1,
  created_by TEXT NOT NULL
);
--> statement-breakpoint
CREATE TABLE jac_attendance_devices (
  id TEXT PRIMARY KEY NOT NULL,
  secret_hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  created_by TEXT NOT NULL
);
--> statement-breakpoint
CREATE TABLE jac_attendance_enrollments (
  id TEXT PRIMARY KEY NOT NULL,
  employee TEXT NOT NULL REFERENCES jac_attendance_people(id),
  device TEXT NOT NULL REFERENCES jac_attendance_devices(id),
  revision INTEGER NOT NULL,
  enrolled_by TEXT NOT NULL,
  public_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(employee, device, revision)
);
--> statement-breakpoint
CREATE TABLE jac_attendance_records (
  id TEXT PRIMARY KEY NOT NULL,
  employee TEXT NOT NULL REFERENCES jac_attendance_people(id),
  movement TEXT NOT NULL CHECK(movement IN ('entry','exit')),
  occurred_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  device TEXT REFERENCES jac_attendance_devices(id),
  enrollment TEXT REFERENCES jac_attendance_enrollments(id),
  supervisor TEXT,
  reason TEXT,
  possible_duplicate INTEGER NOT NULL DEFAULT 0,
  CHECK ((device IS NOT NULL AND enrollment IS NOT NULL AND supervisor IS NULL) OR
         (device IS NULL AND enrollment IS NULL AND supervisor IS NOT NULL AND reason IS NOT NULL))
);
--> statement-breakpoint
CREATE INDEX jac_attendance_history ON jac_attendance_records(occurred_at DESC, id DESC);
--> statement-breakpoint
CREATE INDEX jac_attendance_by_employee ON jac_attendance_records(employee, occurred_at DESC);
--> statement-breakpoint
CREATE TABLE jac_attendance_reviews (
  id TEXT PRIMARY KEY NOT NULL,
  record TEXT NOT NULL REFERENCES jac_attendance_records(id),
  revision INTEGER NOT NULL,
  movement TEXT NOT NULL CHECK(movement IN ('entry','exit')),
  occurred_at TEXT NOT NULL,
  reason TEXT NOT NULL,
  supervisor TEXT NOT NULL,
  reviewed_at TEXT NOT NULL,
  UNIQUE(record,revision)
);
