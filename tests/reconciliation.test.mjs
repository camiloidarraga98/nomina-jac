import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { build } from 'esbuild';
import { readFile, readdir, writeFile, mkdtemp, rm, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import {PDFDocument,PDFDict,PDFArray,PDFName,PDFRawStream,decodePDFRawStream} from 'pdf-lib';
import {receiptJPEG} from './helpers/reconciliation-image.mjs';

// These tests use synthetic records, an isolated SQLite database and in-memory
// private objects. No request is allowed to reach a real external service.
const sql = new DatabaseSync(':memory:');
for (const name of (await readdir('drizzle')).filter(name => name.endsWith('.sql')).sort()) sql.exec(await readFile('drizzle/' + name, 'utf8'));
let beforeQuery = null, afterBatch = null;
class Query {
  constructor(text, args = []) { this.text = text; this.args = args; }
  bind(...args) { return new Query(this.text, args); }
  execute() {
    beforeQuery?.(this.text, this.args);
    const prepared = sql.prepare(this.text);
    if (prepared.columns().length) return { success: true, results: prepared.all(...this.args), meta: { changes: Number(sql.prepare('SELECT changes() AS n').get().n) } };
    const result = prepared.run(...this.args);
    return { success: true, results: [], meta: { changes: Number(result.changes) } };
  }
  async run() { return this.execute(); }
  async all() { return this.execute(); }
  async first() { return this.execute().results[0] ?? null; }
}
const objects = new Map();
let beforePut = null, beforeGet = null, beforeDelete = null, failPut = false, failDelete = false, cancelled = 0;
globalThis.__reconciliationTestEnv = {
  DB: { prepare: query => new Query(query), async batch(statements) { sql.exec('BEGIN'); let result; try { result = statements.map(query => query.execute()); sql.exec('COMMIT'); } catch (error) { sql.exec('ROLLBACK'); throw error; } await afterBatch?.(statements);return result; } },
  PAYROLL_AUTH_KEY: 'reconciliation-fixture-auth-secret-without-production-data',
  BUCKET: {
    async put(key, bytes) { await beforePut?.(); if (failPut) throw new Error('Fixture R2 upload failed'); objects.set(key, Uint8Array.from(bytes)); },
    async get(key) {
      const bytes = objects.get(key);
      await beforeGet?.();
      return bytes ? { body: new ReadableStream({ start(controller) { controller.enqueue(bytes); controller.close(); }, cancel() { cancelled++; } }) } : null;
    },
    async delete(key) { await beforeDelete?.(); if (failDelete) throw new Error('Fixture R2 delete failed'); objects.delete(key); },
  },
};
globalThis.fetch = async () => { throw new Error('Reconciliation tests cannot use external services.'); };
const output = await build({ stdin: { resolveDir: process.cwd(), contents: "export * as api from './app/api/reconciliation/[...path]/route';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';" }, bundle: true, platform: 'node', format: 'esm', write: false, plugins: [{ name: 'reconciliation-isolated-platform', setup(build) {
  build.onResolve({ filter: /^(cloudflare:workers|next\/headers)$/ }, args => ({ path: args.path, namespace: 'test-platform' }));
  build.onLoad({ filter: /.*/, namespace: 'test-platform' }, args => ({ loader: 'js', contents: args.path === 'cloudflare:workers' ? 'export const env=globalThis.__reconciliationTestEnv;export const waitUntil=p=>p.catch(()=>{});' : 'export const headers=async()=>globalThis.__reconciliationTestHeaders||new Headers();' }));
} }] });
await mkdir('work', { recursive: true });
const temp = await mkdtemp(resolve('work/reconciliation-tests-'));
await writeFile(temp + '/bundle.mjs', output.outputFiles[0].contents);
const apiModule = await import(pathToFileURL(temp + '/bundle.mjs').href);
await rm(temp, { recursive: true });
const base = 'https://reconciliation.example.invalid';
let sequence = 0;
async function actor({ administrator = true, sections = ['crm'], persistent = false, mediaOnly = false } = {}) {
  const id = 'reconciliation-fixture-' + (++sequence), now = new Date().toISOString();
  sql.prepare('INSERT INTO payroll_users (id,username,email,name,password_hash,permissions,section_access,media_only,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)').run(id, id, id + '@example.invalid', 'Administrador de prueba', 'synthetic-fixture-password-hash', JSON.stringify(administrator ? [apiModule.ADMINISTRATOR_ROLE] : []), JSON.stringify(sections), Number(mediaOnly), now, now);
  return { id, token: await apiModule.makeSession(id, persistent) };
}
function resetHooks() { beforePut = beforeGet = beforeDelete = beforeQuery = afterBatch = null; failPut = failDelete = false; cancelled = 0; }
async function request(account, path = '/state', { method = 'GET', data, headers = {} } = {}) {
  const cookie = account?.token ? '__Host-jac_session=' + account.token : '';
  const h = new Headers({ host: new URL(base).host, ...(cookie ? { cookie } : {}), ...(!['GET', 'HEAD'].includes(method) ? { origin: base } : {}), ...headers });
  const options = { method, headers: h };
  if (data !== undefined) {
    if (data instanceof FormData) options.body = data;
    else { options.body = typeof data === 'string' ? data : JSON.stringify(data); if (!h.has('content-type')) h.set('Content-Type', 'application/json'); }
  }
  const req = new Request(base + '/api/reconciliation' + path, options);
  globalThis.__reconciliationTestHeaders = h;
  return apiModule.api[method](req, { params: Promise.resolve({ path: path.split('/').filter(Boolean) }) });
}
async function state(account) { const response = await request(account); assert.equal(response.status, 200, await response.clone().text()); return response.json(); }
const row = (sourceRow = 5, extra = {}) => ({ sheet: 'BANCO FICTICIO', sourceRow, date: '2026-11-10', amount: 1250000.5, description: 'Consignación de prueba', reference: '0000123', thirdParty: 'Tercero de origen', receipt: 'RC-TEST-01', invoice: '', original: { FECHA: '10/11/2026', 'VALOR [D]': 1250000.5, 'TERCERO [H]': 'Tercero de origen', NIT: '001234' }, ...extra });
function importPayload(rows = [row()]) { return { name: 'fixture-' + (++sequence) + '.xlsx', fileHash: crypto.randomUUID().replaceAll('-', '').repeat(2), rows }; }
async function seed(account, rows = [row()]) {
  const payload = importPayload(rows), response = await request(account, '/import', { method: 'POST', data: payload });
  assert.equal(response.status, 200, await response.clone().text());
  const ids = sql.prepare('SELECT p.id FROM jac_reconciliation_payments p JOIN jac_reconciliation_imports i ON i.id=p.import_id WHERE i.hash=? ORDER BY p.source_key').all(payload.fileHash).map(row => row.id);
  const out = await state(account);
  return { payload, payments: ids.map(id => out.payments.find(payment => payment.id === id)) };
}
async function manualShow(account) { const response = await request(account, '/shows', { method: 'POST', data: { name: 'Show histórico ficticio ' + (++sequence), date: '2027-01-02', city: 'Pereira', entrepreneur: 'Empresario de prueba' } }); assert.ok([200, 201].includes(response.status), await response.clone().text()); return response.json(); }
function crmShow() {
  const id = crypto.randomUUID(), now = new Date().toISOString();
  sql.prepare('INSERT INTO jac_crm_shows (id,calendar_id,event_id,title,municipality,show_date,sale_cents,paid_cents,entrepreneur,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)').run(id, 'calendar.example.invalid', id, 'Show existente ficticio', 'Pereira', '2026-01-01', 10000000000, 1250000000, 'Empresario CRM', now, now);
  return id;
}
const pdf = label => new TextEncoder().encode('%PDF-1.4\nSYNTHETIC ' + label + '\n%%EOF');
function uploadForm(label = crypto.randomUUID(), name = 'comprobante-ficticio.pdf') { const form = new FormData(); form.set('file', new File([pdf(label)], name, { type: 'application/pdf' })); return form; }
async function upload(account, id, label = crypto.randomUUID()) { const response = await request(account, '/payments/' + id + '/files', { method: 'POST', data: uploadForm(label) }); assert.equal(response.status, 201, await response.clone().text()); return response.json(); }
const revoke = account => sql.prepare('UPDATE payroll_users SET version=version+1 WHERE id=?').run(account.id);
const expire = account => sql.prepare('UPDATE payroll_sessions SET expires_at=? WHERE id=?').run(new Date(Date.now() - 1).toISOString(), apiModule.tokenHash(account.token));

const receiptPNG=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=','base64'));
function receiptForm(){const form=new FormData();form.set('file',new File([receiptPNG],'comprobante-ficticio.png',{type:'image/png'}));return form;}
const receiptReading={document:'single_payment',amountText:'$ 33.555.123,45',dateText:'10/11/2026',currency:'COP',transactionStatus:'completed',legible:true};
const receiptResponse=()=>Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify(receiptReading)}]}]});

test('OCR locates an existing payment without storing the receipt, identifying it or changing accounting data',async()=>{
 resetHooks();const account=await actor(),{payments:[p]}=await seed(account,[row(901,{amount:33555123.45,description:'ORIGINAL-ONLY-NOT-FOR-PROVIDER'})]);
 const originalPayments=sql.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all(),originalObjects=objects.size,originalAudit=sql.prepare('SELECT count(*) n FROM jac_reconciliation_audit').get().n;
 globalThis.__reconciliationTestEnv.OPENAI_API_KEY='synthetic-provider-credential';const savedFetch=globalThis.fetch;let calls=0;
 try{
  globalThis.fetch=async(url,options)=>{calls++;assert.equal(url,'https://api.openai.com/v1/responses');assert.equal(options.redirect,'manual');assert(!options.body.includes('ORIGINAL-ONLY-NOT-FOR-PROVIDER'));return receiptResponse();};
  const response=await request(account,'/scan',{method:'POST',data:receiptForm()});assert.equal(response.status,200,await response.clone().text());assert.match(response.headers.get('cache-control'),/no-store/);
  const result=await response.json();assert.equal(result.autoMatchId,p.id);assert.equal(result.reading.amount,33555123.45);assert.equal(result.matches[0].version,p.version);
  assert.equal(objects.size,originalObjects);assert.deepEqual(sql.prepare('SELECT * FROM jac_reconciliation_payments ORDER BY id').all(),originalPayments);assert.equal(sql.prepare('SELECT count(*) n FROM jac_reconciliation_audit').get().n,originalAudit);
  const manual=await request(account,'/scan/matches',{method:'POST',data:{amount:33555123.45,date:null}});assert.equal(manual.status,200);assert.equal((await manual.json()).autoMatchId,null);assert.equal(calls,2);
  for(const data of [{amount:null,date:null},{amount:33555123.45,date:'2026-11-10',autoEligible:true},{amount:0,date:'2026-11-10'},{amount:33555123.45,date:'2026-02-30'}])assert.equal((await request(account,'/scan/matches',{method:'POST',data})).status,400);
 }finally{globalThis.fetch=savedFetch;}
});

test('OCR requires the CRM session and same-origin request; permission revocation prevents returning the reading',async()=>{
 resetHooks();const account=await actor(),viewer=await actor({administrator:false,sections:['calendar']}),savedFetch=globalThis.fetch;let calls=0;
 try{
  globalThis.fetch=async()=>{calls++;return receiptResponse();};
  for(const who of [null,viewer])for(const [path,data]of [['/scan',receiptForm()],['/scan/matches',{amount:33555123.45,date:null}]])assert.ok([401,403].includes((await request(who,path,{method:'POST',data})).status));
  for(const headers of [{origin:''},{origin:'https://foreign.example.invalid'},{'sec-fetch-site':'cross-site'}])assert.equal((await request(account,'/scan',{method:'POST',data:receiptForm(),headers})).status,403);
  assert.equal(calls,0);
  globalThis.fetch=async()=>{calls++;revoke(account);return receiptResponse();};
  const response=await request(account,'/scan',{method:'POST',data:receiptForm()});assert.equal(response.status,403);assert(!JSON.stringify(await response.json()).includes('33.555.123'));assert.equal(calls,1);
 }finally{globalThis.fetch=savedFetch;}
});

test('OCR reports an already attached receipt without paying for another reading or creating a second attachment',async()=>{
 resetHooks();const account=await actor(),{payments:[p]}=await seed(account,[row(902,{amount:33777123.45})]);
 const label='already-saved-for-ocr-'+crypto.randomUUID(),saved=await upload(account,p.id,label),count=objects.size,savedFetch=globalThis.fetch;
 try{
  globalThis.fetch=async()=>{throw Error('Duplicate must not reach provider');};
  const response=await request(account,'/scan',{method:'POST',data:uploadForm(label)});assert.equal(response.status,200,await response.clone().text());const result=await response.json();assert.equal(result.existingPaymentId,p.id);assert.equal(result.reading,null);assert.equal(objects.size,count);assert.equal((await state(account)).payments.find(x=>x.id===p.id).attachments[0].id,saved.id);
 }finally{globalThis.fetch=savedFetch;}
});

test('a receipt selected from OCR cannot attach over a stale or concurrently changed payment version',async()=>{
 resetHooks();const account=await actor(),{payments:[p]}=await seed(account,[row(903,{amount:33999123.45})]);
 const stale=uploadForm();stale.set('paymentVersion','2');assert.equal((await request(account,'/payments/'+p.id+'/files',{method:'POST',data:stale})).status,409);
 const form=uploadForm();form.set('paymentVersion',String(p.version));const count=objects.size;
 beforePut=()=>{sql.prepare('UPDATE jac_reconciliation_payments SET version=version+1 WHERE id=?').run(p.id);};
 const response=await request(account,'/payments/'+p.id+'/files',{method:'POST',data:form});assert.equal(response.status,409);assert.equal(objects.size,count);assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE payment_id=? AND state='ready'").get(p.id).n,0);resetHooks();
});

test('only a current JAC CRM administrator can read or mutate; Sites headers cannot authenticate', async () => {
  resetHooks();
  const admin = await actor(), viewer = await actor({ administrator: false, sections: ['calendar'] }), media = await actor({ mediaOnly: true });
  const { payments: [payment] } = await seed(admin);
  const file = await upload(admin, payment.id);
  for (const account of [null, viewer, media]) {
    for (const [path, method, data] of [['/state', 'GET'], ['/import', 'POST', importPayload()], ['/payments/' + payment.id, 'PATCH', { version: 1, notes: 'blocked' }], ['/payments/' + payment.id + '/history', 'GET'], [file.url.replace('/api/reconciliation', ''), 'GET'], [file.url.replace('/api/reconciliation', ''), 'DELETE']]) {
      assert.ok([401, 403].includes((await request(account, path, { method, data })).status));
    }
  }
  assert.equal((await request(null, '/state', { headers: { 'oai-authenticated-user-id': admin.id, 'oai-authenticated-user-email': 'owner@example.invalid' } })).status, 401);
  const response = await request(admin); assert.match(response.headers.get('cache-control'), /private, no-store/);
  revoke(admin); assert.equal((await request(admin)).status, 401);
});

test('mutations require exact Origin and reject cross-site requests before any write', async () => {
  resetHooks(); const account = await actor(), count = sql.prepare('SELECT count(*) n FROM jac_reconciliation_imports').get().n;
  for (const headers of [{ origin: '' }, { origin: 'https://other.example.invalid' }, { 'sec-fetch-site': 'cross-site' }]) assert.equal((await request(account, '/import', { method: 'POST', data: importPayload(), headers })).status, 403);
  assert.equal(sql.prepare('SELECT count(*) n FROM jac_reconciliation_imports').get().n, count);
});

test('invalid import rows fail before writes and all valid repeated source rows survive reimport', async () => {
  resetHooks(); const account = await actor(), before = sql.prepare('SELECT count(*) n FROM jac_reconciliation_imports').get().n;
  for (const bad of [row(6, { date: '2026-02-31' }), row(6, { amount: -2 }), row(6, { original: [] }), null, row(5)]) assert.equal((await request(account, '/import', { method: 'POST', data: importPayload([row(), bad]) })).status, 400);
  assert.equal(sql.prepare('SELECT count(*) n FROM jac_reconciliation_imports').get().n, before);
  const { payload, payments } = await seed(account, [row(5), row(6)]);
  assert.equal(payments.length, 2); assert.notEqual(payments[0].id, payments[1].id);
  assert.equal((await request(account, '/payments/' + payments[0].id, { method: 'PATCH', data: { version: 1, notes: 'Conservar trabajo' } })).status, 200);
  const response = await request(account, '/import', { method: 'POST', data: payload }), again = await response.json();
  assert.equal(response.status, 200); assert.equal(again.imported, 0); assert.equal(again.skipped, 2);
  assert.equal((await state(account)).payments.find(p => p.id === payments[0].id).notes, 'Conservar trabajo');
});

test('imported facts are immutable, versions reject stale writes and audit names the actor', async () => {
  resetHooks(); const account = await actor(), { payments: [original] } = await seed(account), path = '/payments/' + original.id;
  const saved = await request(account, path, { method: 'PATCH', data: { version: 1, status: 'review', notes: 'Revisar', amount: 1, date: '2000-01-01', thirdParty: 'Alterado', receipt: 'RC-X', invoice: 'FV-X', original: {} } });
  assert.equal(saved.status, 200); const payment = await saved.json();
  for (const field of ['amount', 'date', 'thirdParty', 'receipt', 'invoice', 'sourceRow']) assert.equal(payment[field], original[field]);
  assert.deepEqual(payment.original, original.original); assert.equal(payment.version, 2);
  assert.equal((await request(account, path, { method: 'PATCH', data: { version: 1, notes: 'Cambio obsoleto' } })).status, 409);
  assert.equal((await state(account)).payments.find(p => p.id === original.id).notes, 'Revisar');
  const audit = sql.prepare("SELECT * FROM jac_reconciliation_audit WHERE payment_id=? AND action='edit'").all(original.id);
  assert.equal(audit.length, 1); assert.equal(audit[0].actor_id, account.id);
  assert.equal((await request(account, path + '/history')).status, 200);
});

test('administrators share records and link existing CRM shows without touching sales, payments or Calendar', async () => {
  resetHooks(); const a = await actor(), b = await actor(), showId = crmShow(), before = sql.prepare('SELECT * FROM jac_crm_shows WHERE id=?').get(showId), paymentsBefore = sql.prepare('SELECT * FROM jac_crm_payments').all();
  const { payments: [payment] } = await seed(a), path = '/payments/' + payment.id;
  const catalog = await state(b), show = catalog.shows.find(s => s.id === showId);
  assert.equal(show.source, 'crm'); assert.equal(show.name, before.title); assert.equal(show.date, before.show_date);
  assert.equal((await request(b, path, { method: 'PATCH', data: { version: 1, status: 'identified', showId } })).status, 400);
  assert.equal((await request(b, path, { method: 'PATCH', data: { version: 1, status: 'identified', showId, entrepreneur: 'Empresario revisado' } })).status, 200);
  assert.deepEqual(sql.prepare('SELECT * FROM jac_crm_shows WHERE id=?').get(showId), before); assert.deepEqual(sql.prepare('SELECT * FROM jac_crm_payments').all(), paymentsBefore);
  const local = await manualShow(a); assert.equal(local.source, 'reconciliation'); assert.equal(sql.prepare('SELECT id FROM jac_crm_shows WHERE id=?').get(local.id), undefined);
  assert.ok((await state(b)).shows.some(s => s.id === local.id));
});

test('private attachments keep exact bytes and identical concurrent uploads create one reference', async () => {
  resetHooks(); const account = await actor(), { payments } = await seed(account, [row(5), row(6)]), label = crypto.randomUUID();
  const replies = await Promise.all(payments.map(p => request(account, '/payments/' + p.id + '/files', { method: 'POST', data: uploadForm(label) })));
  assert.deepEqual(replies.map(r => r.status).sort(), [201, 409]);
  const file = await replies.find(r => r.status === 201).json(), response = await request(account, file.url.replace('/api/reconciliation', ''));
  assert.equal(response.status, 200); assert.equal(response.headers.get('Content-Type'), 'application/pdf'); assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), pdf(label));
  assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE payment_id IN (?,?) AND state='ready'").get(payments[0].id, payments[1].id).n, 1);
  const stored = sql.prepare('SELECT * FROM jac_reconciliation_attachments WHERE id=?').get(file.id);
  assert.equal([...objects.keys()].filter(key => key.includes(payments[0].id) || key.includes(payments[1].id)).length, 1);
  assert.ok(stored.object_key); assert.equal(file.object_key, undefined);
});

test('revocation or expiry during R2 upload cannot publish a support record', async () => {
  resetHooks();
  for (const change of [revoke, expire]) {
    const account = await actor(), { payments: [payment] } = await seed(account);
    beforePut = () => change(account);
    try { assert.equal((await request(account, '/payments/' + payment.id + '/files', { method: 'POST', data: uploadForm() })).status, 403); } finally { beforePut = null; }
    assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE payment_id=? AND state='ready'").get(payment.id).n, 0);
    assert.equal([...objects.keys()].some(key => key.includes(payment.id)), false);
  }
});

test('revocation during R2 read withholds bytes and deleted records cannot be delivered by an older read', async () => {
  resetHooks(); const account = await actor(), { payments: [payment] } = await seed(account), file = await upload(account, payment.id), path = file.url.replace('/api/reconciliation', '');
  beforeGet = () => revoke(account);
  try { assert.equal((await request(account, path)).status, 403); } finally { beforeGet = null; }
  const replacement = await actor();
  beforeGet = async () => { beforeGet = null; assert.equal((await request(replacement, path, { method: 'DELETE' })).status, 200); };
  try { assert.equal((await request(replacement, path)).status, 404); } finally { beforeGet = null; }
  assert.equal((await request(replacement, path)).status, 404);
});

test('deletion retires access before R2 and failed cleanup is retryable without affecting payments', async () => {
  resetHooks(); const account = await actor(), { payments: [payment] } = await seed(account), file = await upload(account, payment.id), path = file.url.replace('/api/reconciliation', '');
  const key = sql.prepare('SELECT object_key FROM jac_reconciliation_attachments WHERE id=?').get(file.id).object_key;
  failDelete = true;
  try { assert.equal((await request(account, path, { method: 'DELETE' })).status, 200); assert.equal((await request(account, path)).status, 404); assert.equal(objects.has(key), true); } finally { failDelete = false; }
  assert.equal(sql.prepare('SELECT state FROM jac_reconciliation_attachments WHERE id=?').get(file.id).state, 'deleted');
  await state(account);
  assert.equal(objects.has(key), false); assert.equal((await state(account)).payments.find(p => p.id === payment.id).amount, payment.amount);
  assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_audit WHERE payment_id=? AND action='remove_attachment'").get(payment.id).n, 1);
});

test('session expiry during physical delete never reports success or exposes retired file', async () => {
  resetHooks(); const account = await actor(), { payments: [payment] } = await seed(account), file = await upload(account, payment.id), path = file.url.replace('/api/reconciliation', '');
  beforeDelete = () => expire(account);
  try { assert.equal((await request(account, path, { method: 'DELETE' })).status, 403); } finally { beforeDelete = null; }
  const other = await actor(); assert.equal((await request(other, path)).status, 404);
  assert.equal(sql.prepare('SELECT state FROM jac_reconciliation_attachments WHERE id=?').get(file.id).state, 'deleted');
});

test('mutation SQL checks the live session even if revoked after an earlier authorization query', async () => {
  resetHooks(); const account = await actor(), { payments: [payment] } = await seed(account), before = sql.prepare('SELECT * FROM jac_reconciliation_payments WHERE id=?').get(payment.id);
  beforeQuery = query => { if (/UPDATE\s+jac_reconciliation_payments\s+SET/i.test(query)) { beforeQuery = null; revoke(account); } };
  try { assert.equal((await request(account, '/payments/' + payment.id, { method: 'PATCH', data: { version: 1, notes: 'Must not save' } })).status, 403); } finally { beforeQuery = null; }
  assert.deepEqual(sql.prepare('SELECT * FROM jac_reconciliation_payments WHERE id=?').get(payment.id), before);
});

test('partial import resumes the exact manifest and keeps annotations and source columns intact', async () => {
  resetHooks();const account=await actor(),payload=importPayload(Array.from({length:61},(_,i)=>row(i+2)));
  let inserts=0;
  beforeQuery=query=>{if(query.includes('INSERT OR IGNORE INTO jac_reconciliation_payments')&&++inserts===51)throw new Error('Synthetic interrupted second batch');};
  assert.equal((await request(account,'/import',{method:'POST',data:payload})).status,503);
  beforeQuery=null;
  const imp=sql.prepare('SELECT * FROM jac_reconciliation_imports WHERE hash=?').get(payload.fileHash);
  assert.equal(imp.completed,0);
  const existing=sql.prepare('SELECT * FROM jac_reconciliation_payments WHERE import_id=?').all(imp.id);
  assert.equal(existing.length,50);
  assert.equal((await request(account,'/payments/'+existing[0].id,{method:'PATCH',data:{version:1,notes:'No borrar mi avance'}})).status,200);
  for(const changed of [{...payload,rows:payload.rows.slice(1)},{...payload,rows:payload.rows.map((r,i)=>i? r:{...r,amount:1})}])assert.equal((await request(account,'/import',{method:'POST',data:changed})).status,409);
  const resumed=await request(account,'/import',{method:'POST',data:{...payload,name:'renamed.xlsx'}});
  assert.equal(resumed.status,200);assert.equal((await resumed.json()).imported,11);
  const final=sql.prepare('SELECT * FROM jac_reconciliation_payments WHERE import_id=?').all(imp.id);
  assert.equal(final.length,61);assert.equal(JSON.parse(final.find(p=>p.id===existing[0].id).annotation).notes,'No borrar mi avance');
  for(const p of final){assert.equal(JSON.parse(p.original).importName,payload.name);assert.deepEqual(JSON.parse(p.original).original,payload.rows[0].original);}
  assert.equal(sql.prepare('SELECT completed FROM jac_reconciliation_imports WHERE id=?').get(imp.id).completed,1);
});

test('initial import without a manifest can be claimed only by identical original data',async()=>{
 resetHooks();const account=await actor(),{payload,payments}=await seed(account);
 sql.prepare("UPDATE jac_reconciliation_imports SET manifest_hash='' WHERE hash=?").run(payload.fileHash);
 assert.equal((await request(account,'/import',{method:'POST',data:{...payload,rows:[row(5,{original:{altered:'value'}})]}})).status,409);
 assert.equal((await request(account,'/import',{method:'POST',data:payload})).status,200);
 assert.equal((await state(account)).payments.find(p=>p.id===payments[0].id).version,1);
});

test('historical show retries and simultaneous requests use one reference without new CRM income',async()=>{
 resetHooks();const account=await actor(),data={name:'Referencia histórica simultánea',date:'2024-05-01',city:'Pereira',entrepreneur:'Ejemplo'};
 const responses=await Promise.all([request(account,'/shows',{method:'POST',data}),request(account,'/shows',{method:'POST',data})]);
 const saved=await Promise.all(responses.map(r=>r.json()));assert.equal(saved[0].id,saved[1].id);
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_reconciliation_shows WHERE id=?').get(saved[0].id).n,1);
 assert.equal(sql.prepare('SELECT count(*) n FROM jac_crm_shows WHERE id=?').get(saved[0].id).n,0);
});

test('lost attachment acknowledgement preserves committed bytes and an identical retry succeeds once',async()=>{
 resetHooks();const account=await actor(),{payments:[p]}=await seed(account),label=crypto.randomUUID();
 afterBatch=queries=>{if(queries.some(q=>q.text.includes("SET state='ready'"))){afterBatch=null;throw new Error('Lost acknowledgement after committed transaction');}};
 const first=await request(account,'/payments/'+p.id+'/files',{method:'POST',data:uploadForm(label)});
 assert.equal(first.status,201);const f=await first.json();
 const repeated=await request(account,'/payments/'+p.id+'/files',{method:'POST',data:uploadForm(label)});
 assert.equal(repeated.status,200);assert.equal((await repeated.json()).id,f.id);
 assert.deepEqual(new Uint8Array(await (await request(account,f.url.replace('/api/reconciliation',''))).arrayBuffer()),pdf(label));
 assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_audit WHERE payment_id=? AND action='attach'").get(p.id).n,1);
});

test('unfinished upload cleanup is durable even when both storage calls fail',async()=>{
 resetHooks();const account=await actor(),{payments:[p]}=await seed(account);
 failPut=failDelete=true;
 assert.equal((await request(account,'/payments/'+p.id+'/files',{method:'POST',data:uploadForm()})).status,503);
 const reserved=sql.prepare('SELECT * FROM jac_reconciliation_attachments WHERE payment_id=?').get(p.id);
 assert.equal(reserved.state,'deleted');assert.ok(reserved.object_key);
 resetHooks();await state(account);
 assert.equal(sql.prepare('SELECT object_key FROM jac_reconciliation_attachments WHERE id=?').get(reserved.id).object_key,'');
});

function batchForm(payments,showId,{operationId=crypto.randomUUID(),label=crypto.randomUUID(),parts,entrepreneur='Empresario del grupo ficticio'}={}){
 const form=new FormData(),source=new Uint8Array([...receiptJPEG,...new TextEncoder().encode(label)]);
 const selection=parts||payments.map((p,i)=>({paymentId:p.id,version:p.version,index:i,bounds:{x:i%4*250,y:Math.floor(i/4)*200,width:240,height:190}}));
 form.set('file',new File([source],'grupo-ficticio.jpg',{type:'image/jpeg'}));form.set('preview',new File([receiptJPEG],'vista.jpg',{type:'image/jpeg'}));form.set('plan',JSON.stringify({operationId,showId,entrepreneur,parts:selection}));return {form,source,operationId,selection};
}
async function batchFixture(count=2){resetHooks();const account=await actor(),{payments}=await seed(account,Array.from({length:count},(_,i)=>row(1000+i,{amount:1980000.5+i}))),showId=crmShow();return {account,payments,showId};}

test('group identifies eight separate existing movements with private individual PDFs, exact source attachment, and one shared show; retry is idempotent',async()=>{
 const {account,payments,showId}=await batchFixture(8),before=sql.prepare('SELECT * FROM jac_crm_shows ORDER BY id').all(),originals=payments.map(p=>sql.prepare('SELECT original FROM jac_reconciliation_payments WHERE id=?').get(p.id).original);
 const batch=batchForm(payments,showId),response=await request(account,'/batch',{method:'POST',data:batch.form});assert.equal(response.status,200,await response.clone().text());const result=await response.json();assert.equal(result.saved,8);assert.equal(result.files.length,8);
 const out=await state(account);for(const [i,p] of payments.entries()){const saved=out.payments.find(r=>r.id===p.id);assert.equal(saved.status,'identified');assert.equal(saved.showId,showId);assert.equal(saved.entrepreneur,'Empresario del grupo ficticio');assert.equal(saved.version,2);assert.equal(saved.attachments.length,1);assert.equal(sql.prepare('SELECT original FROM jac_reconciliation_payments WHERE id=?').get(p.id).original,originals[i]);}
 const download=await request(account,result.files[0].url.replace('/api/reconciliation',''));assert.equal(download.status,200);assert.match(download.headers.get('cache-control'),/no-store/);
 const pdf=await PDFDocument.load(await download.arrayBuffer());assert.equal(pdf.getPageCount(),2);
 const names=pdf.catalog.lookup(PDFName.of('Names'),PDFDict).lookup(PDFName.of('EmbeddedFiles'),PDFDict).lookup(PDFName.of('Names'),PDFArray),attached=names.lookup(1,PDFDict).lookup(PDFName.of('EF'),PDFDict).lookup(PDFName.of('F'),PDFRawStream);
 assert.deepEqual(new Uint8Array(decodePDFRawStream(attached).decode()),batch.source);
 const retried=await request(account,'/batch',{method:'POST',data:batch.form});assert.equal(retried.status,200);assert.equal((await retried.json()).alreadySaved,true);
 assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_audit WHERE id=? AND action='identify-receipt-batch'").get(batch.operationId).n,1);
 const conflict=new FormData();for(const [key,value]of batch.form)conflict.set(key,value);conflict.set('plan',JSON.stringify({...JSON.parse(conflict.get('plan')),entrepreneur:'Otro'}));assert.equal((await request(account,'/batch',{method:'POST',data:conflict})).status,409);
 assert.deepEqual(sql.prepare('SELECT * FROM jac_crm_shows ORDER BY id').all(),before);
 assert.equal((await request(null,result.files[0].url.replace('/api/reconciliation',''))).status,401);
});

test('group rejects repeated movements and overlapping crops before any attachment; stale member prevents the entire group',async()=>{
 const {account,payments,showId}=await batchFixture(),objectsBefore=objects.size;
 for(const parts of [payments.map((p,i)=>({paymentId:payments[0].id,version:1,index:i,bounds:{x:i*500,y:0,width:400,height:900}})),payments.map((p,i)=>({paymentId:p.id,version:1,index:i,bounds:{x:0,y:0,width:500,height:900}}))]){
  assert.equal((await request(account,'/batch',{method:'POST',data:batchForm(payments,showId,{parts}).form})).status,400);
 }
 assert.equal(objects.size,objectsBefore);
 const stale=batchForm(payments,showId);sql.prepare('UPDATE jac_reconciliation_payments SET version=version+1 WHERE id=?').run(payments[1].id);
 assert.equal((await request(account,'/batch',{method:'POST',data:stale.form})).status,409);assert.equal(objects.size,objectsBefore);
 assert.equal((await state(account)).payments.find(p=>p.id===payments[0].id).status,'pending');
});

test('interrupted group storage and commit races leave no partial identification or ready supports; exact retry can complete',async()=>{
 const {account,payments,showId}=await batchFixture(),batch=batchForm(payments,showId),objectsBefore=objects.size;let puts=0;
 beforePut=()=>{if(++puts===2)throw Error('Synthetic second upload failure');};
 assert.equal((await request(account,'/batch',{method:'POST',data:batch.form})).status,502);resetHooks();assert.equal(objects.size,objectsBefore);
 for(const p of payments)assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE payment_id=? AND state='ready'").get(p.id).n,0);
 // A record changes after all staging, immediately before the transaction gate.
 beforeQuery=query=>{if(query.includes("SELECT ?,'',?,'identify-receipt-batch'")){beforeQuery=null;sql.prepare('UPDATE jac_reconciliation_payments SET version=version+1 WHERE id=?').run(payments[1].id);}};
 assert.equal((await request(account,'/batch',{method:'POST',data:batch.form})).status,409);resetHooks();assert.equal(objects.size,objectsBefore);
 for(const p of payments)assert.equal(JSON.parse(sql.prepare('SELECT annotation FROM jac_reconciliation_payments WHERE id=?').get(p.id).annotation).status,'pending');
 const plan=JSON.parse(batch.form.get('plan'));plan.parts[1].version=2;batch.form.set('plan',JSON.stringify(plan));
 assert.equal((await request(account,'/batch',{method:'POST',data:batch.form})).status,200);
});

test('lost group acknowledgement preserves committed supports; a committed crop cannot be assigned to another movement even with a new operation',async()=>{
 const {account,payments,showId}=await batchFixture(3),batch=batchForm(payments.slice(0,2),showId);
 afterBatch=queries=>{if(queries.some(q=>q.text.includes("'identify-receipt-batch'"))){afterBatch=null;throw Error('Synthetic lost acknowledgement');}};
 const response=await request(account,'/batch',{method:'POST',data:batch.form});assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).alreadySaved,true);
 const plan=JSON.parse(batch.form.get('plan'));plan.operationId=crypto.randomUUID();plan.parts=[{...plan.parts[0],paymentId:payments[2].id}];batch.form.set('plan',JSON.stringify(plan));assert.equal((await request(account,'/batch',{method:'POST',data:batch.form})).status,409);
 assert.equal((await state(account)).payments.find(p=>p.id===payments[2].id).version,1);
});

test('session revocation during group staging retires only unfinished private files and identifies nothing',async()=>{
 const {account,payments,showId}=await batchFixture(),batch=batchForm(payments,showId),size=objects.size;
 beforePut=()=>revoke(account);const response=await request(account,'/batch',{method:'POST',data:batch.form});resetHooks();assert.equal(response.status,403);assert.equal(objects.size,size);
 for(const p of payments){assert.equal(sql.prepare('SELECT version FROM jac_reconciliation_payments WHERE id=?').get(p.id).version,1);assert.equal(sql.prepare("SELECT count(*) n FROM jac_reconciliation_attachments WHERE payment_id=? AND state='ready'").get(p.id).n,0);}
});
