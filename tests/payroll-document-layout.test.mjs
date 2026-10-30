import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {build} from 'esbuild';
import {getDocument, OPS} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {unzipSync, strFromU8} from 'fflate';

const bundle = await build({stdin: {contents: "export * from './lib/payroll';export * from './lib/payroll-seed';export * from './lib/payroll-export';", resolveDir: process.cwd()}, bundle: true, platform: 'node', format: 'esm', write: false});
const m = await import('data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
const directory = 'work/local/document-brand';
await mkdir(directory, {recursive: true});

function fixture(count = 24) {
  const seed = m.initialPayroll(), prototype = seed.employees[0];
  const employees = Array.from({length: count}, (_, i) => ({...prototype, id: 'fixture-' + i,
    name: 'PERSONA DE EJEMPLO ' + String(i + 1).padStart(2, '0') + (i % 2 ? ' APELLIDO COMPUESTO DE PRUEBA' : ' GARCÍA MARTÍNEZ'),
    document: 'TEST-' + i, email: 'persona-' + i + '@example.invalid', role: 'Músico de prueba', category: 'musicos', active: true,
    showRate: 750000, salary: 0, fixedService: 0, pension: false, health: false, withholding: .05, ica: 0}));
  const period = m.newPeriod('2026-10-16', '2026-10-31');
  period.shows = ['Presentación de ejemplo', 'Show promocional de prueba'].map((name, i) => ({id: 'show-' + i, date: period.start, name, sale: 50000000,
    promotional: i === 1, halfPay: i === 1, participants: employees.map(e => ({employeeId: e.id, amount: e.showRate}))}));
  period.movements = [{id: 'movement', employeeId: employees[0].id, concept: 'Reintegro de transporte de prueba', kind: 'reintegro', amount: 45000.25, quantity: 2, note: 'Observación de prueba '.repeat(20)}];
  const state = {employees, settings: seed.settings, concepts: [], periods: [period]};
  return {state, period};
}
function close(state, period) {
  period.status = 'cerrada'; period.snapshot = {...m.calculate(state, period), employees: structuredClone(state.employees), closedAt: '2026-10-30T18:00:00Z', closedBy: 'revision@example.invalid'};
}
async function inspectPdf(bytes) {
  const task = getDocument({data: Uint8Array.from(bytes), isEvalSupported: false, disableFontFace: true, useSystemFonts: false, standardFontDataUrl: resolve('node_modules/pdfjs-dist/standard_fonts') + '/'});
  try {
    const document = await task.promise, pages = [];
    for (let n = 1; n <= document.numPages; n++) {
      const page = await document.getPage(n), content = await page.getTextContent(), operators = await page.getOperatorList();
      const boxes = content.items.filter(item => item.str?.trim()).map(item => {
        const size = item.height, font = content.styles[item.fontName];
        return {text: item.str, x: item.transform[4], endX: item.transform[4] + item.width,
          // Reserve the complete Helvetica font box used by print renderers too.
          top: 792 - item.transform[5] - size * Math.max(font.ascent ?? 0, 1.075), bottom: 792 - item.transform[5] - size * Math.min(font.descent ?? 0, -.307)};
      });
      for (const box of boxes) {
        assert.ok(box.x >= 47.9 && box.endX <= 564.1, `p${n}: texto fuera del margen: ${box.text}`);
        assert.ok(box.top >= 20 && box.bottom <= 780, `p${n}: texto fuera de página: ${box.text}`);
        assert.ok(box.bottom <= 706 || box.top >= 732, `p${n}: cuerpo invade el pie: ${box.text}`);
      }
      for (let a = 0; a < boxes.length; a++) for (let b = a+1; b < boxes.length; b++) {
        const one = boxes[a], two = boxes[b];
        const overlapX = Math.min(one.endX,two.endX) - Math.max(one.x,two.x), overlapY = Math.min(one.bottom,two.bottom) - Math.max(one.top,two.top);
        assert.ok(overlapX < .6 || overlapY < .6, `p${n}: superposición: ${one.text} / ${two.text}`);
      }
      // Regression for the original bug: a row separator crossed the next name.
      operators.fnArray.forEach((operation, i) => {
        if (operation !== OPS.constructPath) return;
        const [paint, , bounds] = operators.argsArray[i];
        if (paint !== OPS.stroke || !bounds || Math.abs(bounds[3] - bounds[1]) > .1) return;
        const y = 792 - bounds[1];
        for (const box of boxes) assert.ok(!(box.top + .4 < y && box.bottom - .4 > y && Math.min(bounds[2], box.endX) - Math.max(bounds[0], box.x) > 1), `p${n}: línea atraviesa ${box.text}`);
      });
      assert.ok(operators.fnArray.some(value => [OPS.paintImageXObject, OPS.paintInlineImageXObject].includes(value)), `p${n}: falta logo`);
      const text = boxes.map(box => box.text).join(' ');
      assert.match(text, /jacmusicestudios@gmail.com/);
      assert.match(text, new RegExp(`${String(n).padStart(2,'0')} / ${String(document.numPages).padStart(2,'0')}`));
      pages.push({text, boxes});
    }
    return pages;
  } finally { await task.destroy(); }
}

test('preliquidación de varias páginas: nombres completos, columnas sin superposición y cabecera/pie en todas las páginas', async () => {
  const {state, period} = fixture(), before = structuredClone(state), {review} = m.payrollReview(state, period, 270, '2026-10-30T18:00:00Z');
  const bytes = await m.payrollPdf(period, undefined, false, review), pages = await inspectPdf(bytes);
  assert.ok(pages.length >= 3);
  for (const page of pages) assert.match(page.text, /PRELIQUIDACIÓN · PARA REVISIÓN/);
  for (const row of review.calculation.rows) assert.ok(pages.some(page => page.text.includes(row.name)), row.name);
  for (const page of pages.filter(page => page.text.includes('PERSONA DE EJEMPLO'))) assert.match(page.text, /DEVENGADO.*ADICIONES.*DESCUENTOS.*NETO/);
  const camiloPage = pages.find(page => page.boxes.some(box => box.text === 'Camilo Idarraga'));
  assert.ok(camiloPage); assert.match(camiloPage.text, /PERSONA.*DEVENGADO.*ADICIONES.*DESCUENTOS.*NETO/);
  const name = camiloPage.boxes.find(box => box.text === 'Camilo Idarraga');
  assert.equal(name.x, camiloPage.boxes.find(box => box.text === 'PERSONA').x);
  assert.ok(camiloPage.boxes.some(box => box.x > 480 && Math.abs(box.top-name.top) < 1), 'El neto de Camilo comparte la fila del nombre');
  assert.deepEqual(state, before);
  await writeFile(directory + '/preliquidacion.pdf', bytes);
  await writeFile(directory + '/preliquidacion.xlsx', m.payrollXlsx(period, review));
  await writeFile(directory + '/print-fixture.json', JSON.stringify({period: {...period, status: 'cerrada', snapshot: {...review.calculation, closedAt: review.generatedAt, closedBy: 'revision@example.invalid'}}, employee: state.employees[0].id}));
  close(state, period);
  const finalBytes = await m.payrollPdf(period), finalPages = await inspectPdf(finalBytes);
  const finalPage = finalPages.find(page => page.boxes.some(box => box.text === 'Camilo Idarraga'));
  assert.ok(finalPage); assert.match(finalPage.text, /PERSONA.*GRUPO.*NETO A PAGAR/);
  const finalName = finalPage.boxes.find(box => box.text === 'Camilo Idarraga'), group = finalPage.boxes.find(box => box.text === 'Comisión del 5%');
  assert.equal(finalName.x, finalPage.boxes.find(box => box.text === 'PERSONA').x);
  assert.ok(Math.abs(finalName.top-group.top)<1, 'Nombre y grupo de Camilo quedan en la misma fila');
  assert.ok(finalPage.boxes.some(box => box.x>440&&Math.abs(box.top-finalName.top)<1), 'Importe alineado en la fila de Camilo');
  await writeFile(directory + '/resumen-camilo-listado.pdf', finalBytes);
});

test('desprendible multipágina y resumen: conceptos, referencias, identificación y valores completos incluso con importes grandes', async () => {
  const {state, period} = fixture(1), person = state.employees[0];
  person.name = 'N'.repeat(180); person.document = 'D'.repeat(180); person.role = 'Cargo de prueba '.repeat(12);
  period.shows = Array.from({length: 35}, (_, i) => ({id: 'long-' + i, date: period.start, name: 'Referencia de presentación '.repeat(6) + i,
    sale: 1e12, participants: [{employeeId: person.id, amount: 1e12}]}));
  state.settings.company = 'EMPRESA DE PRUEBA '.repeat(10); state.settings.nit = 'T'.repeat(180);
  close(state, period);
  const before = structuredClone(period), bytes = await m.payrollPdf(period, person.id), pages = await inspectPdf(bytes);
  assert.ok(pages.length >= 4);
  const text = pages.map(page => page.text).join(' ');
  assert.match(text, /TOTAL A PAGAR/); assert.match(text, /33\.250\.000\.090\.000,50/);
  assert.equal((text.match(/Referencia de presentación/g) ?? []).length, 35*6);
  await inspectPdf(await m.payrollPdf(period)); assert.deepEqual(period, before);
  await writeFile(directory + '/desprendible-extenso.pdf', bytes);
});

test('PDF combinado y ZIP usan la misma plantilla y conservan cada destinatario y total', async () => {
  const {state, period} = fixture(2);
  state.employees[1].category = 'conductores'; state.employees[1].salary = 2000000;
  close(state, period);
  const before = structuredClone(period), combined = await inspectPdf(await m.payrollPdf(period, undefined, true));
  assert.equal(combined.filter(page => page.text.includes('TOTAL A PAGAR')).length, 2);
  const zip = unzipSync(await m.payrollSlipZip(period)); assert.equal(Object.keys(zip).length, 2);
  let pageCount = 0;
  for (const [index, person] of state.employees.entries()) {
    assert.ok(combined.some(page => page.text.includes(person.name)));
    const entry = Object.entries(zip).find(([name]) => name.endsWith('_' + person.id + '.pdf'));
    assert.ok(entry); const pages = await inspectPdf(entry[1]);
    pageCount += pages.length;
    const text = pages.map(page => page.text).join(' ');
    assert.ok(text.includes(person.name)); assert.ok(!text.includes(state.employees[1-index].name));
    assert.equal((text.match(/TOTAL A PAGAR/g) ?? []).length, 1);
    if (index === 1) { assert.match(text, /CONDUCTORES/); assert.match(text, /DEPENDIENTES/); }
    await writeFile(directory + '/desprendible-' + index + '.pdf', entry[1]);
  }
  assert.equal(combined.length, pageCount);
  await writeFile(directory + '/resumen.pdf', await m.payrollPdf(period));
  assert.deepEqual(period, before);
});

test('Excel incluye logo y títulos en todas las hojas; fórmulas, filtros, filas altas y configuración de impresión conservan los datos', async () => {
  const {state, period} = fixture(3);
  state.employees[0].name = 'TOTAL GENERAL'; // A name is still data, never a reconciliation row.
  const {review} = m.payrollReview(state, period, 270, '2026-10-30T18:00:00Z');
  const files = unzipSync(m.payrollXlsx(period, review));
  assert.deepEqual(Buffer.from(files['xl/media/jac-logo.png']), await readFile('public/document-jac-logo.png'));
  const workbook = strFromU8(files['xl/workbook.xml']); assert.equal((workbook.match(/_xlnm.Print_Titles/g) ?? []).length, 8);
  for (let i = 1; i <= 8; i++) {
    const sheet = strFromU8(files[`xl/worksheets/sheet${i}.xml`]);
    assert.match(sheet, /PRELIQUIDACIÓN · PARA REVISIÓN/); assert.match(sheet, /<pane ySplit="5"/);
    assert.match(sheet, /<drawing r:id="rIdDrawing"/); assert.match(sheet, /fitToWidth="1" fitToHeight="0"/);
    assert.match(strFromU8(files[`xl/drawings/_rels/drawing${i}.xml.rels`]), /jac-logo.png/);
  }
  const summary = strFromU8(files['xl/worksheets/sheet1.xml']);
  assert.match(summary, /<autoFilter ref="A5:H9"/); // Includes Camilo as a payable row; excludes both totals.
  assert.match(summary, /<f>SUM\(H6:H8\)<\/f>/); assert.match(summary, /<f>H10\+H9<\/f>/);
  const shows = strFromU8(files['xl/worksheets/sheet3.xml']); assert.match(shows, /<f>ROUND\(E9\*0.5,2\)<\/f><v>375000<\/v>/);
  const movements = strFromU8(files['xl/worksheets/sheet4.xml']);
  assert.match(movements, /<f>D6\*E6<\/f><v>90000.5<\/v>/);
  assert.ok(Number(movements.match(/<row r="6" ht="([\d.]+)"/)[1]) > 100);
});
