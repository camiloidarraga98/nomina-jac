CREATE TABLE `payroll_calendar` (
	`id` text PRIMARY KEY NOT NULL,
	`credentials` text DEFAULT '' NOT NULL,
	`connected_email` text DEFAULT '' NOT NULL,
	`calendar_id` text DEFAULT '' NOT NULL,
	`calendar_name` text DEFAULT '' NOT NULL,
	`timezone` text DEFAULT 'America/Bogota' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_at` text NOT NULL
);
