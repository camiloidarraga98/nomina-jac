CREATE INDEX IF NOT EXISTS payroll_periods_start ON payroll_periods(start,id);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS payroll_mail_queue ON payroll_mail_jobs(status,started_at);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS jac_push_queue ON jac_push_deliveries(status,updated_at);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS jac_slack_queue ON jac_slack_files(status,created_at);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS jac_media_operations_cleanup ON jac_media_operations(connection_version,kind,status,created_at);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS jac_media_r2_entries_gallery ON jac_media_r2_entries(parent_id,(mime_type='application/vnd.google-apps.folder') DESC,created_at DESC,name,id);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS jac_music_cleanup ON jac_music_tracks(status,claim_at,created_at);
