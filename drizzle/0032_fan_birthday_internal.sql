ALTER TABLE `jac_fan_birthday_jobs` ADD `internal_mode` integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
CREATE TABLE `jac_fan_birthday_internal_limits` (
	`ip_hash` text PRIMARY KEY NOT NULL,
	`attempts` integer NOT NULL,
	`expires_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_fan_birthday_internal_expiry` ON `jac_fan_birthday_internal_limits` (`expires_at`);
