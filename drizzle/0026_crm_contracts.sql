CREATE TABLE jac_crm_contracts (
 id TEXT PRIMARY KEY NOT NULL,
 actor_id TEXT NOT NULL,
 request_hash TEXT NOT NULL,
 input_json TEXT NOT NULL,
 filename TEXT NOT NULL,
 company TEXT NOT NULL,
 municipality TEXT NOT NULL,
 event_date TEXT NOT NULL,
 price REAL NOT NULL,
 show_id TEXT,
 state TEXT NOT NULL DEFAULT 'pending',
 file_key TEXT NOT NULL,
 write_nonce TEXT NOT NULL,
 lease_until TEXT NOT NULL,
 version INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL,
 updated_at TEXT NOT NULL
);
--> statement-breakpoint
CREATE INDEX jac_crm_contracts_archive ON jac_crm_contracts(state,created_at DESC,id DESC);
--> statement-breakpoint
CREATE INDEX jac_crm_contracts_show ON jac_crm_contracts(show_id,state);
