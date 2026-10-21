ALTER TABLE `jac_fan_birthday_jobs` ADD `quota_generation` integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
CREATE INDEX `jac_fan_birthday_quota` ON `jac_fan_birthday_jobs` (`quota_generation`,`created_at`);
--> statement-breakpoint
CREATE TABLE `jac_fan_birthday_quota_resets` (
	`sequence` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`request_id` text NOT NULL,
	`actor_hash` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_fan_birthday_quota_resets_request_id_unique` ON `jac_fan_birthday_quota_resets` (`request_id`);
