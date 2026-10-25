CREATE INDEX `jac_media_r2_entries_recent`
ON `jac_media_r2_entries` (`created_at` DESC,`id` DESC)
WHERE `mime_type` IN ('image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif','image/tiff') AND `object_key`<>'';
