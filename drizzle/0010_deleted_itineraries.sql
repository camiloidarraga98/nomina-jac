CREATE TABLE `jac_deleted_itineraries` (
	`id` text PRIMARY KEY NOT NULL,
	`source` text,
	`file_key` text DEFAULT '' NOT NULL,
	`file_deleted` integer DEFAULT 0 NOT NULL,
	`cleanup_version` integer DEFAULT 0 NOT NULL,
	`deleted_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_deleted_itineraries_source_unique` ON `jac_deleted_itineraries` (`source`);--> statement-breakpoint
CREATE INDEX `jac_deleted_itineraries_cleanup` ON `jac_deleted_itineraries` (`file_deleted`);