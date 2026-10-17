import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const result = await build({
  entryPoints: ['lib/rut-pdf-client.ts'], bundle: true, platform: 'node', format: 'esm', write: false,
  plugins: [{ name: 'rut-browser-isolation', setup(builder) {
    builder.onResolve({ filter: /pdf\.worker\.min\.mjs\?url$/ }, () => ({ path: 'worker', namespace: 'rut-fixture' }));
    builder.onResolve({ filter: /pdfjs-dist\/legacy\/build\/pdf\.mjs$/ }, () => ({ path: 'pdfjs', namespace: 'rut-fixture' }));
    builder.onResolve({ filter: /rut-extract$/ }, () => ({ path: 'parser', namespace: 'rut-fixture' }));
    builder.onLoad({ filter: /.*/, namespace: 'rut-fixture' }, ({ path }) => ({ contents: path === 'worker'
      ? "export default '/assets/rut-fixture.worker.mjs';"
      : path === 'parser'
        ? 'export function extractRut(pages){const s=globalThis.rutClientFixture;s.parsed.push(pages);return s.result;}'
        : 'export const PDFWorker={create(options){return globalThis.rutClientFixture.createWorker(options);}};export function getDocument(options){return globalThis.rutClientFixture.getDocument(options);}export const Util={transform(a,b){return globalThis.rutClientFixture.transform(a,b);}};', loader: 'js' }));
  } }],
});
const { readRutPDF, RUT_MAX_BYTES } = await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].contents).toString('base64')}`);
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };
const file = () => new File(['%PDF-1.7\nfixture data only'], 'RUT-ficticio.pdf', { type: 'application/pdf' });

function fixture(options = {}) {
  const previous = { Worker: globalThis.Worker, fetch: globalThis.fetch, setTimeout: globalThis.setTimeout, clearTimeout: globalThis.clearTimeout };
  const state = {
    ports: [], workers: [], tasks: [], parsed: [], pageCleanups: 0, requests: [], timers: [],
    result: { company: 'EMPRESA FICTICIA', nit: '900000009-0', representatives: [], warnings: [] },
    createWorker({ port }) { if (options.workerFailure) throw Error('Worker no disponible'); const worker = { port, destroys: 0, destroy() { this.destroys++; } }; state.workers.push(worker); return worker; },
    getDocument(request) {
      state.requests.push(request);
      const text = options.text ?? { items: [{ str: 'EMPRESA FICTICIA', transform: [8, 0, 0, 8, 25, 700], width: 100, fontName: 'fixture' }], styles: { fixture: { ascent: .75 } } };
      const page = { getViewport: () => ({ width: 612, height: 792, transform: [1, 0, 0, -1, 0, 792] }), getTextContent: async () => text, cleanup() { state.pageCleanups++; } };
      const pdf = { numPages: options.numPages ?? 1, getPage: async () => page };
      const task = { destroys: 0, promise: options.documentPromise ?? (options.password ? Promise.reject(Object.assign(Error('locked'), { name: 'PasswordException' })) : Promise.resolve(pdf)), async destroy() { this.destroys++; } };
      state.tasks.push(task); return task;
    },
    transform(a, b) { return [a[0] * b[0], 0, 0, a[3] * b[3], b[4], 792 - b[5]]; },
  };
  globalThis.rutClientFixture = state;
  globalThis.Worker = class {
    constructor(url, config) { this.url = url; this.config = config; this.terminates = 0; state.ports.push(this); }
    terminate() { this.terminates++; }
  };
  globalThis.fetch = () => { throw Error('La prueba no permite tráfico de red.'); };
  globalThis.setTimeout = (callback, milliseconds) => { const timer = { callback, milliseconds, cleared: false }; state.timers.push(timer); return timer; };
  globalThis.clearTimeout = timer => { timer.cleared = true; };
  return { state, restore() { Object.assign(globalThis, previous); delete globalThis.rutClientFixture; } };
}

test('rechaza vacío, tamaño excesivo y firma ajena antes de crear worker', async () => {
  const { state, restore } = fixture();
  try {
    for (const candidate of [new File([], 'empty.pdf'), { size: RUT_MAX_BYTES + 1 }, new File(['No es PDF'], 'not.pdf')]) await assert.rejects(readRutPDF(candidate, new AbortController().signal), /PDF|10 MB/);
    assert.equal(state.ports.length, 0); assert.equal(state.requests.length, 0); assert.equal(state.parsed.length, 0);
  } finally { restore(); }
});

test('lee exclusivamente bytes locales y libera página, tarea y worker al completar', async () => {
  const { state, restore } = fixture();
  try {
    const progress = [];
    assert.deepEqual(await readRutPDF(file(), new AbortController().signal, (p, n) => progress.push([p, n])), state.result);
    assert.deepEqual(progress, [[1, 1]]); assert.equal(state.pageCleanups, 1);
    assert.equal(state.parsed[0][0].items[0].text, 'EMPRESA FICTICIA');
    assert.deepEqual(state.parsed[0][0].items[0], { text: 'EMPRESA FICTICIA', x: 25, y: 86, width: 100, height: 8 });
    const request = state.requests[0]; assert.ok(request.data instanceof Uint8Array); assert.equal(request.url, undefined);
    for (const key of ['useWorkerFetch', 'useWasm', 'enableXfa', 'useSystemFonts']) assert.equal(request[key], false);
    for (const key of ['disableFontFace', 'disableAutoFetch', 'disableRange', 'disableStream', 'stopAtErrors']) assert.equal(request[key], true);
    assert.equal(state.ports[0].url, '/assets/rut-fixture.worker.mjs'); assert.equal(state.ports[0].config.type, 'module');
    assert.equal(state.tasks[0].destroys, 1); assert.equal(state.workers[0].destroys, 1); assert.equal(state.ports[0].terminates, 1); assert.equal(state.timers[0].cleared, true);
  } finally { restore(); }
});

test('aborto previo no crea worker ni procesa contenido', async () => {
  const { state, restore } = fixture();
  try {
    const controller = new AbortController(); controller.abort();
    await assert.rejects(readRutPDF(file(), controller.signal), { name: 'AbortError' });
    assert.equal(state.ports.length, 0); assert.equal(state.parsed.length, 0);
  } finally { restore(); }
});

test('cancela lectura pendiente y retira recursos sin entregar datos tardíos', async () => {
  const pending = deferred(); const { state, restore } = fixture({ documentPromise: pending.promise });
  try {
    const controller = new AbortController(), reading = readRutPDF(file(), controller.signal);
    await tick(); assert.equal(state.tasks.length, 1); controller.abort();
    await assert.rejects(reading, { name: 'AbortError' });
    assert.ok(state.tasks[0].destroys >= 1); assert.ok(state.workers[0].destroys >= 1); assert.ok(state.ports[0].terminates >= 1);
    assert.equal(state.parsed.length, 0); assert.equal(state.timers[0].cleared, true);
    pending.resolve({ numPages: 1, getPage() { throw Error('No debe leer tras cancelar'); } }); await tick();
    assert.equal(state.parsed.length, 0);
  } finally { restore(); }
});

test('contraseña y límites de páginas, elementos y texto siempre liberan recursos', async () => {
  const cases = [
    [{ password: true }, /contraseña/],
    [{ numPages: 21 }, /20 páginas/],
    [{ text: { items: Array.from({ length: 15001 }, () => ({ str: 'x' })), styles: {} } }, /complejo/],
    [{ text: { items: [{ str: 'x'.repeat(200001) }], styles: {} } }, /demasiado texto/],
  ];
  for (const [options, expected] of cases) {
    const { state, restore } = fixture(options);
    try {
      await assert.rejects(readRutPDF(file(), new AbortController().signal), expected);
      assert.equal(state.tasks[0].destroys, 1); assert.equal(state.workers[0].destroys, 1); assert.equal(state.ports[0].terminates, 1); assert.equal(state.parsed.length, 0); assert.equal(state.timers[0].cleared, true);
    } finally { restore(); }
  }
});

test('fallo al inicializar PDFWorker también termina el port ya creado', async () => {
  const { state, restore } = fixture({ workerFailure: true });
  try {
    await assert.rejects(readRutPDF(file(), new AbortController().signal), /Worker no disponible/);
    assert.equal(state.ports[0].terminates, 1);
    assert.equal(state.requests.length, 0);
  } finally { restore(); }
});

test('timeout mientras se leen bytes no permite iniciar una tarea tardía', async () => {
  const pending = deferred(); const { state, restore } = fixture();
  try {
    const candidate = file(); candidate.arrayBuffer = () => pending.promise;
    const reading = readRutPDF(candidate, new AbortController().signal);
    await tick(); assert.equal(state.timers[0].milliseconds, 30000); state.timers[0].callback();
    await assert.rejects(reading, /tardó demasiado/);
    pending.resolve(new Uint8Array([37, 80, 68, 70]).buffer); await tick();
    assert.equal(state.requests.length, 0); assert.equal(state.parsed.length, 0);
    assert.ok(state.ports[0].terminates >= 1); assert.ok(state.workers[0].destroys >= 1);
  } finally { restore(); }
});
