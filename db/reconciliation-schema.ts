import {sql} from 'drizzle-orm';
import {sqliteTable,text,integer,index,uniqueIndex} from 'drizzle-orm/sqlite-core';

export const reconciliationImports=sqliteTable('jac_reconciliation_imports',{
 id:text('id').primaryKey().notNull(),hash:text('hash').notNull(),manifestHash:text('manifest_hash').notNull().default(''),name:text('name').notNull(),count:integer('count').notNull(),completed:integer('completed').notNull().default(0),createdBy:text('created_by').notNull(),createdAt:text('created_at').notNull(),
},t=>[uniqueIndex('jac_reconciliation_imports_hash').on(t.hash)]);

export const reconciliationShows=sqliteTable('jac_reconciliation_shows',{
 id:text('id').primaryKey().notNull(),data:text('data').notNull(),createdBy:text('created_by').notNull(),createdAt:text('created_at').notNull(),
});

export const reconciliationPayments=sqliteTable('jac_reconciliation_payments',{
 id:text('id').primaryKey().notNull(),importId:text('import_id').notNull(),sourceKey:text('source_key').notNull(),original:text('original').notNull(),annotation:text('annotation').notNull(),version:integer('version').notNull().default(1),createdAt:text('created_at').notNull(),updatedAt:text('updated_at').notNull(),
},t=>[uniqueIndex('jac_reconciliation_payments_source').on(t.importId,t.sourceKey)]);

export const reconciliationAttachments=sqliteTable('jac_reconciliation_attachments',{
 id:text('id').primaryKey().notNull(),paymentId:text('payment_id').notNull(),objectKey:text('object_key').notNull(),hash:text('hash').notNull(),name:text('name').notNull(),type:text('type').notNull(),size:integer('size').notNull(),state:text('state').notNull().default('ready'),createdBy:text('created_by').notNull(),createdAt:text('created_at').notNull(),
},t=>[index('jac_reconciliation_attachments_payment').on(t.paymentId,t.state),uniqueIndex('jac_reconciliation_attachments_hash').on(t.hash).where(sql`${t.state}='ready'`)]);

export const reconciliationAudit=sqliteTable('jac_reconciliation_audit',{
 id:text('id').primaryKey().notNull(),paymentId:text('payment_id').notNull(),actorId:text('actor_id').notNull(),action:text('action').notNull(),data:text('data').notNull(),createdAt:text('created_at').notNull(),
},t=>[index('jac_reconciliation_audit_payment').on(t.paymentId,t.createdAt)]);
