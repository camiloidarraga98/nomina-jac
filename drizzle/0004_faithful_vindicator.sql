CREATE TABLE `payroll_gmail` (
	`id` text PRIMARY KEY NOT NULL,
	`credentials` text NOT NULL,
	`connected_email` text DEFAULT '' NOT NULL,
	`enabled` integer DEFAULT 0 NOT NULL,
	`error` text DEFAULT '' NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `payroll_mail_batches` (
	`id` text PRIMARY KEY NOT NULL,
	`period_id` text NOT NULL,
	`data` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `payroll_mail_jobs` (
	`id` text PRIMARY KEY NOT NULL,
	`batch_id` text NOT NULL,
	`employee_id` text NOT NULL,
	`name` text NOT NULL,
	`email` text NOT NULL,
	`status` text NOT NULL,
	`attempts` integer DEFAULT 0 NOT NULL,
	`error` text DEFAULT '' NOT NULL,
	`sent_at` text,
	`message_id` text,
	`claim` text DEFAULT '' NOT NULL,
	`started_at` text
);
--> statement-breakpoint
CREATE INDEX `payroll_mail_jobs_batch` ON `payroll_mail_jobs` (`batch_id`,`status`);--> statement-breakpoint
CREATE TABLE `payroll_oauth` (
	`id` text PRIMARY KEY NOT NULL,
	`payload` text NOT NULL,
	`expires_at` text NOT NULL
);
