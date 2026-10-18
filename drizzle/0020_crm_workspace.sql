CREATE TABLE `jac_crm_contact_uploads` (
	`id` text PRIMARY KEY NOT NULL,
	`contact_id` text NOT NULL,
	`hash` text NOT NULL,
	`actor_id` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_crm_contacts` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`company` text DEFAULT '' NOT NULL,
	`phone` text DEFAULT '' NOT NULL,
	`email` text DEFAULT '' NOT NULL,
	`city` text DEFAULT '' NOT NULL,
	`note` text DEFAULT '' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`write_nonce` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jac_crm_payroll_links` (
	`show_id` text PRIMARY KEY NOT NULL,
	`period_id` text NOT NULL,
	`payroll_show_id` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_crm_payroll_links_unique` ON `jac_crm_payroll_links` (`period_id`,`payroll_show_id`);--> statement-breakpoint
CREATE TABLE `jac_crm_plans` (
	`show_id` text PRIMARY KEY NOT NULL,
	`budget` text DEFAULT '{}' NOT NULL,
	`tasks` text DEFAULT '[]' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`write_nonce` text DEFAULT '' NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
ALTER TABLE `jac_crm_shows` ADD `contact_id` text DEFAULT '' NOT NULL;
--> statement-breakpoint
INSERT INTO jac_crm_contacts(id,name,created_at,updated_at) SELECT min(id),trim(entrepreneur),min(created_at),max(updated_at) FROM jac_crm_shows WHERE trim(entrepreneur)<>'' GROUP BY lower(trim(entrepreneur));
--> statement-breakpoint
UPDATE jac_crm_shows SET contact_id=COALESCE((SELECT c.id FROM jac_crm_contacts c WHERE lower(trim(c.name))=lower(trim(jac_crm_shows.entrepreneur)) LIMIT 1),'');
