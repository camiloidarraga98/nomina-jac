CREATE TABLE `jac_notice_attachments` (
	`id` text PRIMARY KEY NOT NULL,
	`notice_id` text DEFAULT '' NOT NULL,
	`file_key` text NOT NULL,
	`filename` text NOT NULL,
	`mime_type` text NOT NULL,
	`size` integer NOT NULL,
	`state` text DEFAULT 'staged' NOT NULL,
	`expires_at` text NOT NULL,
	`cleanup_version` integer DEFAULT 0 NOT NULL,
	`cleaned` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_notice_attachments_notice` ON `jac_notice_attachments` (`notice_id`,`state`);--> statement-breakpoint
CREATE INDEX `jac_notice_attachments_cleanup` ON `jac_notice_attachments` (`state`,`cleaned`,`expires_at`);--> statement-breakpoint
ALTER TABLE `jac_notices` ADD `manual_hash` text DEFAULT '' NOT NULL;