CREATE TABLE `jac_crm_creations` (
	`id` text PRIMARY KEY NOT NULL,
	`actor_id` text NOT NULL,
	`calendar_id` text NOT NULL,
	`event_hash` text NOT NULL,
	`payload_hash` text NOT NULL,
	`show_id` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jac_crm_creations_event` ON `jac_crm_creations` (`calendar_id`,`event_hash`);