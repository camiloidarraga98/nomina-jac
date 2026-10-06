CREATE TABLE `payroll_periods` (
	`id` text PRIMARY KEY NOT NULL,
	`data` text NOT NULL,
	`start` text NOT NULL
);
--> statement-breakpoint
ALTER TABLE `payroll_state` ADD `write_nonce` text DEFAULT '' NOT NULL;