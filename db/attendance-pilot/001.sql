-- The pilot runner provisions synthetic accounts separately in an isolated database.
ALTER TABLE payroll_users ADD COLUMN attendance_role TEXT CHECK(attendance_role IN ('kiosk','operator'));
--> statement-breakpoint
CREATE TABLE attendance_people (
 id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE COLLATE NOCASE, name TEXT NOT NULL,
 active INTEGER NOT NULL DEFAULT 1, revision INTEGER NOT NULL DEFAULT 1
);
--> statement-breakpoint
CREATE TABLE attendance_punches (
 id TEXT PRIMARY KEY, employee TEXT NOT NULL REFERENCES attendance_people(id),
 actor TEXT NOT NULL, device TEXT NOT NULL, movement TEXT NOT NULL CHECK(movement IN ('entry','exit')),
 device_time TEXT NOT NULL, received_at TEXT NOT NULL, method TEXT NOT NULL CHECK(method IN ('supervised','simulation','simulation_failed')),
 possible_duplicate INTEGER NOT NULL, clock_difference INTEGER NOT NULL
);
--> statement-breakpoint
CREATE INDEX attendance_punches_employee_time ON attendance_punches(employee, movement, device_time);
--> statement-breakpoint
CREATE TABLE attendance_reviews (
 id TEXT PRIMARY KEY, punch TEXT NOT NULL REFERENCES attendance_punches(id), revision INTEGER NOT NULL,
 action TEXT NOT NULL CHECK(action IN ('approve','correct')), reason TEXT NOT NULL, operator TEXT NOT NULL,
 recorded_at TEXT NOT NULL, movement TEXT NOT NULL, device_time TEXT NOT NULL,
 UNIQUE(punch, revision)
);
--> statement-breakpoint
CREATE TABLE attendance_operator_grants (
 id TEXT PRIMARY KEY, session TEXT NOT NULL REFERENCES payroll_sessions(id) ON DELETE CASCADE,
 operator TEXT NOT NULL REFERENCES payroll_users(id), operator_version INTEGER NOT NULL, expires_at TEXT NOT NULL
);
--> statement-breakpoint
CREATE TRIGGER attendance_punch_no_update BEFORE UPDATE ON attendance_punches BEGIN SELECT RAISE(ABORT,'immutable punch'); END;
--> statement-breakpoint
CREATE TRIGGER attendance_punch_no_delete BEFORE DELETE ON attendance_punches BEGIN SELECT RAISE(ABORT,'immutable punch'); END;
--> statement-breakpoint
CREATE TRIGGER attendance_review_no_update BEFORE UPDATE ON attendance_reviews BEGIN SELECT RAISE(ABORT,'immutable review'); END;
--> statement-breakpoint
CREATE TRIGGER attendance_review_no_delete BEFORE DELETE ON attendance_reviews BEGIN SELECT RAISE(ABORT,'immutable review'); END;
