CREATE TABLE `jac_boarding_channels` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`enabled` integer DEFAULT 1 NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
ALTER TABLE `jac_notices` ADD `travel_date` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_slack_files` ADD `channel_id` text DEFAULT 'C0C6V85SRL6' NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_slack_files` ADD `recipient_id` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_slack_files` ADD `mapping_version` integer DEFAULT 0 NOT NULL;