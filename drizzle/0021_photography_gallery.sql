CREATE TABLE `jac_media_connection` (
	`id` text PRIMARY KEY NOT NULL,
	`credentials` text DEFAULT '' NOT NULL,
	`email` text DEFAULT '' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_media_operations` (
	`id` text PRIMARY KEY NOT NULL,
	`actor_id` text NOT NULL,
	`parent_id` text NOT NULL,
	`payload_hash` text NOT NULL,
	`kind` text NOT NULL,
	`drive_id` text DEFAULT '' NOT NULL,
	`name` text NOT NULL,
	`mime_type` text NOT NULL,
	`size` integer DEFAULT 0 NOT NULL,
	`offset` integer DEFAULT 0 NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`session_payload` text DEFAULT '' NOT NULL,
	`connection_version` integer NOT NULL,
	`claim` text DEFAULT '' NOT NULL,
	`claim_at` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`expires_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_media_operations_actor` ON `jac_media_operations` (`actor_id`,`created_at`);--> statement-breakpoint
ALTER TABLE `payroll_users` ADD `media_only` integer DEFAULT 0 NOT NULL;