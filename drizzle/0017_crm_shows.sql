CREATE TABLE `jac_crm_audit` (
	`id` text PRIMARY KEY NOT NULL,
	`show_id` text NOT NULL,
	`actor_id` text NOT NULL,
	`action` text NOT NULL,
	`data` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_crm_exports` (
	`sequence` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`payment_id` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`synced_version` integer DEFAULT 0 NOT NULL,
	`connection_version` integer DEFAULT 0 NOT NULL,
	`error` text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_crm_exports_payment_id_unique` ON `jac_crm_exports` (`payment_id`);--> statement-breakpoint
CREATE TABLE `jac_crm_payments` (
	`id` text PRIMARY KEY NOT NULL,
	`show_id` text NOT NULL,
	`amount_cents` integer NOT NULL,
	`payment_date` text NOT NULL,
	`note` text DEFAULT '' NOT NULL,
	`hash` text NOT NULL,
	`actor_id` text NOT NULL,
	`upload_token` text NOT NULL,
	`status` text DEFAULT 'recorded' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`created_at` text NOT NULL,
	`voided_at` text DEFAULT '' NOT NULL,
	`voided_by` text DEFAULT '' NOT NULL,
	`void_reason` text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_crm_payments_show` ON `jac_crm_payments` (`show_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `jac_crm_sheets` (
	`id` text PRIMARY KEY NOT NULL,
	`credentials` text DEFAULT '' NOT NULL,
	`email` text DEFAULT '' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`file_request_id` text NOT NULL,
	`spreadsheet_id` text DEFAULT '' NOT NULL,
	`spreadsheet_url` text DEFAULT '' NOT NULL,
	`sheet_id` integer DEFAULT 0 NOT NULL,
	`creation_state` text DEFAULT 'idle' NOT NULL,
	`claim` text DEFAULT '' NOT NULL,
	`claim_at` text DEFAULT '' NOT NULL,
	`error` text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_crm_shows` (
	`id` text PRIMARY KEY NOT NULL,
	`calendar_id` text NOT NULL,
	`event_id` text NOT NULL,
	`title` text NOT NULL,
	`municipality` text NOT NULL,
	`show_date` text NOT NULL,
	`source_state` text DEFAULT 'present' NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`sale_cents` integer,
	`paid_cents` integer DEFAULT 0 NOT NULL,
	`entrepreneur` text DEFAULT '' NOT NULL,
	`note` text DEFAULT '' NOT NULL,
	`promotional` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`write_nonce` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_crm_shows_date` ON `jac_crm_shows` (`show_date`,`status`);