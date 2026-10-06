CREATE TABLE `registrations` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`birth` text NOT NULL,
	`section` text NOT NULL,
	`row` text NOT NULL,
	`seat` text NOT NULL,
	`photo_key` text NOT NULL,
	`consent` text NOT NULL,
	`created_at` text NOT NULL
);
