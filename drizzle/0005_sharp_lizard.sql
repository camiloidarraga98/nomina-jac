CREATE TABLE `payroll_invitations` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`user_version` integer NOT NULL,
	`expires_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `payroll_invitations_user_id_unique` ON `payroll_invitations` (`user_id`);--> statement-breakpoint
CREATE TABLE `payroll_login_limits` (
	`id` text PRIMARY KEY NOT NULL,
	`count` integer NOT NULL,
	`expires_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `payroll_sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`user_version` integer NOT NULL,
	`expires_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `payroll_sessions_user` ON `payroll_sessions` (`user_id`);--> statement-breakpoint
CREATE TABLE `payroll_users` (
	`id` text PRIMARY KEY NOT NULL,
	`username` text NOT NULL,
	`email` text NOT NULL,
	`name` text NOT NULL,
	`password_hash` text DEFAULT '' NOT NULL,
	`owner` integer DEFAULT 0 NOT NULL,
	`active` integer DEFAULT 1 NOT NULL,
	`permissions` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `payroll_users_username_unique` ON `payroll_users` (`username`);--> statement-breakpoint
CREATE UNIQUE INDEX `payroll_users_email_unique` ON `payroll_users` (`email`);