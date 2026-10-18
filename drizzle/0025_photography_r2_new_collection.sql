CREATE TABLE `jac_media_r2_entries` (
	`id` text PRIMARY KEY NOT NULL,
	`parent_id` text NOT NULL,
	`name` text NOT NULL,
	`mime_type` text NOT NULL,
	`size` integer DEFAULT 0 NOT NULL,
	`object_key` text DEFAULT '' NOT NULL,
	`thumbnail_key` text DEFAULT '' NOT NULL,
	`actor_id` text NOT NULL,
	`payload_hash` text NOT NULL,
	`created_at` text NOT NULL,
	`modified_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_media_r2_entries_parent` ON `jac_media_r2_entries` (`parent_id`,`created_at`);