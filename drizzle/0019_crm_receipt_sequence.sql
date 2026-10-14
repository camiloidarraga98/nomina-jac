ALTER TABLE `jac_crm_shows` ADD `receipt_sequence` integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
UPDATE jac_crm_shows SET receipt_sequence=(SELECT count(*) FROM jac_notice_attachments a JOIN jac_crm_payments p ON a.notice_id='crm-payment:'||p.id WHERE p.show_id=jac_crm_shows.id AND a.state='ready');

--> statement-breakpoint
UPDATE jac_crm_exports SET version=version+1,error='';
