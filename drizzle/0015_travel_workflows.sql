CREATE TABLE `jac_itinerary_updates` (
	`id` text PRIMARY KEY NOT NULL,
	`notice_id` text NOT NULL,
	`revision` integer NOT NULL,
	`hash` text NOT NULL,
	`summary` text NOT NULL,
	`actor_id` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_travel_expenses` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`concept` text NOT NULL,
	`amount` integer NOT NULL,
	`expense_date` text NOT NULL,
	`note` text DEFAULT '' NOT NULL,
	`hash` text NOT NULL,
	`upload_token` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`review_note` text DEFAULT '' NOT NULL,
	`reviewer_id` text DEFAULT '' NOT NULL,
	`period_id` text DEFAULT '' NOT NULL,
	`employee_id` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`reviewed_at` text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_travel_expenses_user` ON `jac_travel_expenses` (`user_id`,`created_at`);--> statement-breakpoint
ALTER TABLE `jac_notice_recipients` ADD `confirmed_revision` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_notice_recipients` ADD `confirmed_at` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_notices` ADD `revision` integer DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_notices` ADD `updated_at` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_notices` ADD `change_summary` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `jac_push_deliveries` ADD `notice_revision` integer DEFAULT 1 NOT NULL;