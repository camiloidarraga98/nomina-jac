CREATE TABLE IF NOT EXISTS jac_media_folder_shares (
 id TEXT PRIMARY KEY NOT NULL,
 folder_id TEXT NOT NULL,
 token_hash TEXT NOT NULL UNIQUE,
 token_cipher TEXT NOT NULL,
 actor_id TEXT NOT NULL,
 actor_version INTEGER NOT NULL,
 connection_version INTEGER NOT NULL,
 expires_at TEXT NOT NULL,
 revoked_at TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS jac_media_folder_shares_folder ON jac_media_folder_shares(folder_id,created_at);
