-- Only future folder inserts create candidates. Existing photography is never
-- backfilled or announced by installing this migration.
CREATE TABLE jac_media_folder_notifications (
 id TEXT PRIMARY KEY NOT NULL,
 folder_id TEXT NOT NULL,
 connection_version INTEGER NOT NULL,
 status TEXT NOT NULL DEFAULT 'waiting',
 created_at TEXT NOT NULL,
 published_at TEXT NOT NULL DEFAULT ''
);
--> statement-breakpoint
CREATE INDEX jac_media_folder_notifications_queue ON jac_media_folder_notifications(status,created_at);
--> statement-breakpoint
CREATE UNIQUE INDEX jac_media_folder_notifications_folder_id_unique ON jac_media_folder_notifications(folder_id);
--> statement-breakpoint
CREATE TABLE jac_media_folder_push_deliveries (
 id TEXT PRIMARY KEY NOT NULL,
 event_id TEXT NOT NULL,
 device_id TEXT NOT NULL,
 user_id TEXT NOT NULL,
 user_version INTEGER NOT NULL,
 session_id TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending',
 updated_at TEXT NOT NULL
);
--> statement-breakpoint
CREATE INDEX jac_media_folder_push_queue ON jac_media_folder_push_deliveries(status,updated_at);
--> statement-breakpoint
CREATE INDEX jac_media_folder_push_event ON jac_media_folder_push_deliveries(event_id,device_id);
--> statement-breakpoint
CREATE INDEX jac_media_operations_media_notify ON jac_media_operations(connection_version,kind,parent_id,status,drive_id);
--> statement-breakpoint
-- The durable candidate shares the folder transaction. No network call,
-- credential decryption, thumbnail work, or client batch API is required.
CREATE TRIGGER jac_media_folder_notification_created
AFTER INSERT ON jac_media_r2_entries
WHEN NEW.mime_type='application/vnd.google-apps.folder' AND NEW.id GLOB 'r2_*' AND length(NEW.id)=39
BEGIN
 INSERT OR IGNORE INTO jac_media_folder_notifications(id,folder_id,connection_version,created_at)
 SELECT substr(NEW.id,4),NEW.id,version,NEW.created_at
 FROM jac_media_r2_connection WHERE id='jac' AND enabled=1;
END;
