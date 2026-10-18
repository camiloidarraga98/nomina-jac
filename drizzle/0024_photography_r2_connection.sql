CREATE TABLE `jac_media_r2_connection` (
	`id` text PRIMARY KEY NOT NULL,
	`credentials` text DEFAULT '' NOT NULL,
	`enabled` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_at` text NOT NULL
);
