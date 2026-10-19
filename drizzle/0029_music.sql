CREATE TABLE IF NOT EXISTS jac_music_tracks (
 id TEXT PRIMARY KEY NOT NULL, actor_id TEXT NOT NULL, section TEXT NOT NULL,
 title TEXT NOT NULL, filename TEXT NOT NULL, mime_type TEXT NOT NULL, size INTEGER NOT NULL,
 revision TEXT NOT NULL, created_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'uploading',
 upload_id TEXT NOT NULL DEFAULT '', offset INTEGER NOT NULL DEFAULT 0,
 parts TEXT NOT NULL DEFAULT '[]', claim TEXT NOT NULL DEFAULT '', claim_at TEXT NOT NULL DEFAULT ''
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS jac_music_section ON jac_music_tracks(status,section,title);
