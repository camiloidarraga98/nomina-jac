CREATE TABLE IF NOT EXISTS jac_media_presentations (
 file_id TEXT PRIMARY KEY NOT NULL,
 source_key TEXT NOT NULL,
 connection_version INTEGER NOT NULL,
 preview_key TEXT NOT NULL DEFAULT '',
 stream_uid TEXT NOT NULL DEFAULT '',
 stream_host TEXT NOT NULL DEFAULT 'videodelivery.net',
 stream_status TEXT NOT NULL DEFAULT '',
 claim TEXT NOT NULL DEFAULT '',
 claim_at TEXT NOT NULL DEFAULT '',
 updated_at TEXT NOT NULL
);
