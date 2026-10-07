CREATE TABLE `jac_notice_recipients` (
	`id` text PRIMARY KEY NOT NULL,
	`notice_id` text NOT NULL,
	`user_id` text NOT NULL,
	`read_at` text DEFAULT '' NOT NULL,
	`push_target` integer DEFAULT 1 NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_notice_recipients_pair` ON `jac_notice_recipients` (`notice_id`,`user_id`);--> statement-breakpoint
CREATE TABLE `jac_notice_settings` (
	`id` text PRIMARY KEY NOT NULL,
	`credentials` text DEFAULT '' NOT NULL,
	`version` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_notices` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`title` text NOT NULL,
	`body` text DEFAULT '' NOT NULL,
	`file_key` text DEFAULT '' NOT NULL,
	`filename` text DEFAULT '' NOT NULL,
	`size` integer DEFAULT 0 NOT NULL,
	`source` text,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_notices_source_unique` ON `jac_notices` (`source`);--> statement-breakpoint
CREATE TABLE `jac_push_deliveries` (
	`id` text PRIMARY KEY NOT NULL,
	`notice_id` text NOT NULL,
	`device_id` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_push_deliveries_pair` ON `jac_push_deliveries` (`notice_id`,`device_id`);--> statement-breakpoint
CREATE TABLE `jac_push_devices` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`user_version` integer NOT NULL,
	`platform` text NOT NULL,
	`data` text NOT NULL,
	`session_id` text NOT NULL,
	`enabled` integer DEFAULT 1 NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_push_devices_user` ON `jac_push_devices` (`user_id`,`enabled`);--> statement-breakpoint
CREATE TABLE `jac_slack_files` (
	`id` text PRIMARY KEY NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`started_at` text DEFAULT '' NOT NULL,
	`error` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL
);
