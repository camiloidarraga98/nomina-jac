CREATE TABLE `jac_fan_birthday_jobs` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_hash` text NOT NULL,
	`ip_hash` text NOT NULL,
	`payload_hash` text NOT NULL,
	`status` text NOT NULL,
	`source_key` text DEFAULT '' NOT NULL,
	`source_mime` text DEFAULT '' NOT NULL,
	`result_key` text DEFAULT '' NOT NULL,
	`claim` text DEFAULT '' NOT NULL,
	`started_at` text DEFAULT '' NOT NULL,
	`message` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`expires_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_fan_birthday_queue` ON `jac_fan_birthday_jobs` (`status`,`created_at`);--> statement-breakpoint
CREATE INDEX `jac_fan_birthday_owner` ON `jac_fan_birthday_jobs` (`owner_hash`,`created_at`);--> statement-breakpoint
CREATE INDEX `jac_fan_birthday_ip` ON `jac_fan_birthday_jobs` (`ip_hash`,`created_at`);--> statement-breakpoint
CREATE INDEX `jac_fan_birthday_created` ON `jac_fan_birthday_jobs` (`created_at`);