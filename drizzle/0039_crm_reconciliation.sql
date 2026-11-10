CREATE TABLE `jac_reconciliation_attachments` (
	`id` text PRIMARY KEY NOT NULL,
	`payment_id` text NOT NULL,
	`object_key` text NOT NULL,
	`hash` text NOT NULL,
	`name` text NOT NULL,
	`type` text NOT NULL,
	`size` integer NOT NULL,
	`state` text DEFAULT 'ready' NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_reconciliation_attachments_payment` ON `jac_reconciliation_attachments` (`payment_id`,`state`);--> statement-breakpoint
CREATE UNIQUE INDEX `jac_reconciliation_attachments_hash` ON `jac_reconciliation_attachments` (`hash`) WHERE "jac_reconciliation_attachments"."state"='ready';--> statement-breakpoint
CREATE TABLE `jac_reconciliation_audit` (
	`id` text PRIMARY KEY NOT NULL,
	`payment_id` text NOT NULL,
	`actor_id` text NOT NULL,
	`action` text NOT NULL,
	`data` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_reconciliation_audit_payment` ON `jac_reconciliation_audit` (`payment_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `jac_reconciliation_imports` (
	`id` text PRIMARY KEY NOT NULL,
	`hash` text NOT NULL,
	`manifest_hash` text DEFAULT '' NOT NULL,
	`name` text NOT NULL,
	`count` integer NOT NULL,
	`completed` integer DEFAULT 0 NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_reconciliation_imports_hash` ON `jac_reconciliation_imports` (`hash`);--> statement-breakpoint
CREATE TABLE `jac_reconciliation_payments` (
	`id` text PRIMARY KEY NOT NULL,
	`import_id` text NOT NULL,
	`source_key` text NOT NULL,
	`original` text NOT NULL,
	`annotation` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_reconciliation_payments_source` ON `jac_reconciliation_payments` (`import_id`,`source_key`);--> statement-breakpoint
CREATE TABLE `jac_reconciliation_shows` (
	`id` text PRIMARY KEY NOT NULL,
	`data` text NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL
);
