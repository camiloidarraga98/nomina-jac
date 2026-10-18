import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const directory = await mkdtemp(resolve('work/rut-extract-tests-'));
const bundle = await build({ entryPoints: ['lib/rut-extract.ts'], bundle: true, platform: 'node', format: 'esm', write: false });
await writeFile(`${directory}/bundle.mjs`, bundle.outputFiles[0].contents);
const { extractRut } = await import(pathToFileURL(`${directory}/bundle.mjs`));
await rm(directory, { recursive: true });

// Entirely fictitious text and identifiers. No source RUT is stored as a fixture.
const item = (text, x, y, width = text.length * 3, height = 6) => ({ text, x, y, width, height });
const page = items => ({ width: 612, height: 792, items });
function header(nit = '900000009', dv = '0') {
  return [item('Espacio reservado para la DIAN', 28, 78), item('5. Número de Identificación Tributaria (NIT)', 27.5, 170.8), item('6. DV', 185.5, 170.8), item('12. Dirección seccional', 205.5, 170.8),
    ...[...nit].map((c, i) => item(c, 86.1 + i * 11.57, 182.1, 4.5, 8)), ...(dv === null ? [] : [item(dv, 192.5, 182.1, 4.5, 8)])];
}
function identification(nit, dv, company = 'FUNDACIÓN ESCENARIO FICTICIO') {
  return page([...header(nit, dv), item('24. Tipo de contribuyente', 27.5, 206), item('Persona jurídica', 27, 216), item('35. Razón social', 27.5, 278.8), ...(company ? [item(company, 27, 288.2)] : []), item('36. Nombre comercial', 27.5, 302.8), item('41. Dirección principal', 27.5, 374.8), item('Responsabilidades, Calidades y Atributos', 27, 488)]);
}
function row(top, { role = 'REPRS LEGAL PRIN', code = '1 8', first = 'MARÍA', other = 'JOSÉ', surname = 'MUÑOZ', second = 'PÉREZ', identity = '1000000000', document = 'Cédula de Ciudadanía 1 3' } = {}) {
  return [item('98. Representación', 38.5, top), item('99. Fecha inicio ejercicio representación', 215.5, top), ...(role ? [item(`${role} ${code}`, 41, top + 10, 165, 8)] : []), item('100. Tipo de documento', 38.5, top + 24), item('101. Número de identificación', 137.5, top + 24), item('102. DV', 406.8, top + 24), item('103. Número de tarjeta profesional', 432.5, top + 24), ...(document ? [item(document, 41, top + 34, 86, 8)] : []),
    ...[...identity].map((c, i) => item(c, 139.5 + i * 14, top + 35, 4.5, 8)),
    item('104. Primer apellido', 38.5, top + 48), item('105. Segundo apellido', 171.5, top + 48), item('106. Primer nombre', 312.5, top + 48), item('107. Otros nombres', 455.5, top + 48),
    ...[[surname, 38], [second, 171], [first, 312], [other, 455]].filter(([s]) => s).map(([s, x]) => item(s, x, top + 58.4, s.length * 5, 8)),
    item('108. Número de Identificación Tributaria (NIT)', 38.5, top + 72), item('109. DV', 189.8, top + 72), item('110. Razón social representante legal', 215.5, top + 72)];
}
const representation = (...rows) => page([...header(), item('Representación', 287, 194), ...rows.flat()]);

test('extrae casillas digitales, ordena nombres y conserva DV cero sin advertencias', () => {
  const result = extractRut([identification(), representation(row(206.8), row(302.8, { role: '', first: '', other: '', surname: '', second: '', identity: '', document: '' }))]);
  assert.equal(result.company, 'FUNDACIÓN ESCENARIO FICTICIO');
  assert.equal(result.nit, '900000009-0');
  assert.deepEqual(result.representatives, [{ name: 'MARÍA JOSÉ MUÑOZ PÉREZ', identity: '1000000000', kind: 'principal', documentType: 'Cédula de ciudadanía' }]);
  assert.deepEqual(result.warnings, []);
});

test('no toma solicitante, socios, miembros de junta ni contador como representante', () => {
  const main = identification();
  main.items.push(item('984. Nombre', 306, 733), item('PERSONA DEL PIE SIN REPRESENTACIÓN', 350, 743));
  const other = page([...header(), item('Socios y/o Miembros de Juntas Directivas', 28, 194), item('115. Primer apellido', 38, 254), item('JUNTA', 38, 265), item('117. Primer nombre', 312, 254), item('PERSONA', 312, 265), item('128. Primer apellido', 38, 350), item('CONTADOR', 38, 360)]);
  const result = extractRut([main, other]);
  assert.deepEqual(result.representatives, []);
  assert.match(result.warnings.join(' '), /No se encontró un representante legal principal/);
});

test('devuelve suplentes y varios principales, sin elegir al firmante ni confundir filas', () => {
  const result = extractRut([identification(), representation(row(206.8), row(302.8, { role: 'REPRS LEGAL SUPL', code: '1 9', first: 'JUAN', other: '', identity: '1000000001' }), row(398.8, { first: 'ELENA', other: '', identity: '1000000002' }))]);
  assert.deepEqual(result.representatives.map(r => [r.kind, r.name, r.identity]), [['principal', 'MARÍA JOSÉ MUÑOZ PÉREZ', '1000000000'], ['suplente', 'JUAN MUÑOZ PÉREZ', '1000000001'], ['principal', 'ELENA MUÑOZ PÉREZ', '1000000002']]);
  assert.match(result.warnings.join(' '), /varios representantes principales/);
});

test('advierte NIT discordante y DV ausente sin inventar ni reparar dígitos', () => {
  const invalid = extractRut([identification('900000009', '1')]);
  assert.equal(invalid.nit, '900000009-1');
  assert.match(invalid.warnings.join(' '), /no coincide/);
  const missing = extractRut([identification('900000009', null)]);
  assert.equal(missing.nit, '900000009');
  assert.match(missing.warnings.join(' '), /Falta el dígito/);
  assert.equal(extractRut([identification('900000000', '5')]).nit, '900000000-5');
});

test('acepta datos parciales y documento no ciudadano con advertencias explícitas', () => {
  const result = extractRut([identification(undefined, undefined, ''), representation(row(206.8, { first: '', identity: '', document: 'Pasaporte 4 1' }))]);
  assert.equal(result.company, undefined);
  assert.equal(result.representatives[0].identity, '');
  assert.equal(result.representatives[0].documentType, 'Pasaporte');
  assert.match(result.warnings.join(' '), /razón social/);
  assert.match(result.warnings.join(' '), /incompletos/);
  assert.match(result.warnings.join(' '), /distinto/);
});

test('rechaza escaneados, documentos ajenos y un PDF que mezcla dos contribuyentes', () => {
  for (const pages of [[], [page([])], [page([item('DIAN', 20, 20), item('Factura con NIT 900000009-0 y FUNDACIÓN FICTICIA', 20, 40)])]]) assert.throws(() => extractRut(pages), /RUT/);
  assert.throws(() => extractRut([identification(), identification('900000000', '5')]), /NIT distintos/);
  assert.throws(() => extractRut([identification(), identification(undefined, undefined, 'OTRA EMPRESA FICTICIA')]), /razones sociales distintas/);
});

test('mantiene extracción al cambiar escala y orden de elementos', () => {
  const pages = [identification(), representation(row(206.8))].map(p => ({ width: p.width * 1.5, height: p.height * 1.5, items: p.items.map(i => ({ text: i.text, x: i.x * 1.5, y: i.y * 1.5, width: i.width * 1.5, height: i.height * 1.5 })).reverse() }));
  const result = extractRut(pages);
  assert.equal(result.nit, '900000009-0');
  assert.equal(result.representatives[0].name, 'MARÍA JOSÉ MUÑOZ PÉREZ');
  assert.deepEqual(result.warnings, []);
});

test('no confunde el último dígito NIT con DV si cambian levemente las celdas entre hojas', () => {
  const shifted = representation(row(206.8));
  const last = shifted.items.find(i => i.y === 182.1 && Math.abs(i.x - (86.1 + 8 * 11.57)) < 0.01);
  last.x = 182.57;
  shifted.items.find(i => i.y === 182.1 && i.x === 192.5).x = 194.5;
  const result = extractRut([identification(), shifted]);
  assert.equal(result.nit, '900000009-0');
  assert.deepEqual(result.warnings, []);
});
