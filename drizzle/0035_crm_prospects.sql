CREATE TABLE `jac_crm_prospect_batches` (
	`id` text PRIMARY KEY NOT NULL,
	`actor_id` text NOT NULL,
	`session_id` text NOT NULL,
	`request_hash` text NOT NULL,
	`write_nonce` text NOT NULL,
	`brochure_id` text NOT NULL,
	`state` text DEFAULT 'pending' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_crm_prospect_brochures` (
	`id` text PRIMARY KEY NOT NULL,
	`file_key` text NOT NULL,
	`filename` text NOT NULL,
	`size` integer NOT NULL,
	`sha256` text NOT NULL,
	`state` text DEFAULT 'ready' NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_crm_prospect_brochures_sha256_unique` ON `jac_crm_prospect_brochures` (`sha256`);--> statement-breakpoint
CREATE TABLE `jac_crm_prospect_deliveries` (
	`id` text PRIMARY KEY NOT NULL,
	`batch_id` text NOT NULL,
	`prospect_id` text NOT NULL,
	`prospect_version` integer NOT NULL,
	`year` integer NOT NULL,
	`email` text NOT NULL,
	`email_key` text NOT NULL,
	`subject` text NOT NULL,
	`body` text NOT NULL,
	`brochure_id` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`reply_status` text DEFAULT 'none' NOT NULL,
	`claim` text DEFAULT '' NOT NULL,
	`started_at` text DEFAULT '' NOT NULL,
	`attempts` integer DEFAULT 0 NOT NULL,
	`sent_at` text DEFAULT '' NOT NULL,
	`message_id` text DEFAULT '' NOT NULL,
	`thread_id` text DEFAULT '' NOT NULL,
	`rfc_message_id` text NOT NULL,
	`error` text DEFAULT '' NOT NULL,
	`replied_at` text DEFAULT '' NOT NULL,
	`checked_at` text DEFAULT '' NOT NULL,
	`check_claim` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `jac_crm_prospect_delivery_queue` ON `jac_crm_prospect_deliveries` (`status`,`created_at`);--> statement-breakpoint
CREATE INDEX `jac_crm_prospect_delivery_batch` ON `jac_crm_prospect_deliveries` (`batch_id`,`created_at`);--> statement-breakpoint
CREATE INDEX `jac_crm_prospect_delivery_prospect` ON `jac_crm_prospect_deliveries` (`prospect_id`,`created_at`);--> statement-breakpoint
CREATE INDEX `jac_crm_prospect_reply_queue` ON `jac_crm_prospect_deliveries` (`status`,`checked_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `jac_crm_prospect_delivery_reservation` ON `jac_crm_prospect_deliveries` (`year`,`email_key`) WHERE "jac_crm_prospect_deliveries"."status" IN ('pending','sending','sent','uncertain');--> statement-breakpoint
CREATE TABLE `jac_crm_prospect_mail` (
	`id` text PRIMARY KEY NOT NULL,
	`credentials` text DEFAULT '' NOT NULL,
	`connected_email` text DEFAULT '' NOT NULL,
	`enabled` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`error` text DEFAULT '' NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_crm_prospect_runner` (
	`id` text PRIMARY KEY NOT NULL,
	`claim` text DEFAULT '' NOT NULL,
	`started_at` text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_crm_prospects` (
	`id` text PRIMARY KEY NOT NULL,
	`source_id` text NOT NULL,
	`year` integer DEFAULT 2027 NOT NULL,
	`department` text NOT NULL,
	`municipality` text NOT NULL,
	`festival` text NOT NULL,
	`period` text DEFAULT '' NOT NULL,
	`month` integer DEFAULT 0 NOT NULL,
	`projected_date` text DEFAULT '' NOT NULL,
	`mayor_name` text DEFAULT '' NOT NULL,
	`email` text DEFAULT '' NOT NULL,
	`emails_json` text DEFAULT '[]' NOT NULL,
	`date_status` text DEFAULT 'projected' NOT NULL,
	`stage` text DEFAULT 'new' NOT NULL,
	`notes` text DEFAULT '' NOT NULL,
	`next_follow_up` text DEFAULT '' NOT NULL,
	`source_json` text DEFAULT '{}' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_crm_prospects_source_id_unique` ON `jac_crm_prospects` (`source_id`);--> statement-breakpoint
CREATE INDEX `jac_crm_prospects_list` ON `jac_crm_prospects` (`year`,`month`,`department`,`municipality`);--> statement-breakpoint
CREATE INDEX `jac_crm_prospects_stage` ON `jac_crm_prospects` (`stage`,`next_follow_up`);