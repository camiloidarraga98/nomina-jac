/** Text positions are PDF points, with the origin at the top left of each page. */
export type RutPage = {
  width: number;
  height: number;
  items: { text: string; x: number; y: number; width: number; height: number }[];
};

export type RutRepresentative = {
  name: string;
  identity: string;
  kind: 'principal' | 'suplente' | 'otro';
  documentType: string;
};

export type RutExtraction = {
  company?: string;
  nit?: string;
  representatives: RutRepresentative[];
  warnings: string[];
};

type Item = RutPage['items'][number];
type Line = { y: number; height: number; items: Item[]; text: string; starts: number[] };
type Anchor = { x: number; y: number; height: number };
const plain = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const tidy = (s: string) => s.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();

function pageLines(page: RutPage): Line[] {
  const lines: Line[] = [];
  for (const item of [...page.items].sort((a, b) => a.y - b.y || a.x - b.x)) {
    if (!tidy(item.text)) continue;
    let line = lines.findLast(l => Math.abs(l.y - item.y) <= 3.5);
    if (!line) {
      line = { y: item.y, height: item.height, items: [], text: '', starts: [] };
      lines.push(line);
    }
    line.items.push(item);
    line.height = Math.max(line.height, item.height);
  }
  for (const line of lines) {
    line.items.sort((a, b) => a.x - b.x);
    for (const item of line.items) {
      line.starts.push(line.text.length);
      line.text += `${plain(tidy(item.text))} `;
    }
  }
  return lines;
}

function anchors(lines: Line[], number: number, caption: string): Anchor[] {
  const pattern = new RegExp(`(?:^|\\s)${number}\\s*\\.\\s*${caption}`, 'g');
  const result: Anchor[] = [];
  for (const line of lines) {
    for (const match of line.text.matchAll(pattern)) {
      const at = match.index! + (match[0].startsWith(' ') ? 1 : 0);
      let index = line.starts.findLastIndex(start => start <= at);
      if (index < 0) index = 0;
      const item = line.items[index];
      // A PDF text item can contain several labels; interpolate only within that item.
      const offset = Math.max(0, at - line.starts[index]);
      const length = plain(tidy(item.text)).length;
      result.push({ x: item.x + item.width * Math.min(1, offset / Math.max(1, length)), y: line.y, height: line.height });
    }
  }
  return result;
}

function near(all: Anchor[], y: number, tolerance = 4): Anchor | undefined {
  return all.find(a => Math.abs(a.y - y) <= tolerance);
}

function below(all: Anchor[], start: number, end: number): Anchor | undefined {
  return all.find(a => a.y > start + 4 && a.y < end);
}

function cell(page: RutPage, anchor: Anchor, right: number, bottom: number, left = anchor.x - 3): string {
  const selected = page.items.filter(i => {
    const center = i.x + i.width / 2;
    return center >= left && center < right - 1 && i.y > anchor.y + anchor.height + 0.3 && i.y < bottom - 1;
  });
  return tidy(pageLines({ ...page, items: selected }).map(l => l.items.map(i => i.text).join(' ')).join(' '));
}

function digits(value: string): string | undefined {
  if (!value || !/^[\d.\s]+$/.test(value)) return undefined;
  return value.replace(/[.\s]/g, '');
}

function nitCheckDigit(nit: string): number {
  const weights = [71, 67, 59, 53, 47, 43, 41, 37, 29, 23, 19, 17, 13, 7, 3];
  const value = nit.padStart(weights.length, '0');
  const remainder = [...value].reduce((sum, digit, i) => sum + Number(digit) * weights[i], 0) % 11;
  return remainder > 1 ? 11 - remainder : remainder;
}

/** Reads labelled DIAN RUT cells only. It never chooses a representative for the caller. */
export function extractRut(input: RutPage[]): RutExtraction {
  if (!Array.isArray(input) || !input.length || input.length > 50) throw new Error('Selecciona un RUT DIAN válido.');
  const pages = input.map(page => {
    if (!Number.isFinite(page.width) || !Number.isFinite(page.height) || page.width <= 0 || page.height <= 0 || !Array.isArray(page.items) || page.items.length > 30000) throw new Error('No se pudo leer la estructura del RUT.');
    // Normalize standard DIAN page geometry while retaining relative text positions.
    const sx = 612 / page.width, sy = 792 / page.height;
    return {
      width: 612, height: 792,
      items: page.items.filter(i => typeof i.text === 'string' && i.text.length <= 5000 && [i.x, i.y, i.width, i.height].every(Number.isFinite) && i.width >= 0 && i.height > 0)
        .map(i => ({ text: tidy(i.text), x: i.x * sx, y: i.y * sy, width: i.width * sx, height: i.height * sy })),
    };
  });
  const layouts = pages.map(page => ({ page, lines: pageLines(page) }));
  const identification = layouts.filter(({ lines }) => {
    const text = lines.map(l => l.text).join(' ');
    return /\bdian\b/.test(text) && anchors(lines, 5, 'numero de identificacion tributaria').length > 0
      && anchors(lines, 6, 'dv\\b').length > 0 && anchors(lines, 24, 'tipo de contribuyente').length > 0
      && anchors(lines, 35, 'razon social').length > 0
      && (anchors(lines, 41, 'direccion principal').length > 0 || /responsabilidades,? calidades/.test(text));
  });
  if (!identification.length) throw new Error('No se reconoce un RUT DIAN con texto seleccionable. Revisa el archivo o completa los datos manualmente.');
  const result: RutExtraction = { representatives: [], warnings: [] };
  const companies = new Set<string>();
  for (const { page, lines } of identification) {
    const label = anchors(lines, 35, 'razon social')[0];
    const next = below(anchors(lines, 36, 'nombre comercial'), label.y, label.y + 35);
    const company = cell(page, label, 590, next?.y ?? label.y + 24);
    if (company) companies.add(company);
  }
  if (companies.size > 1) throw new Error('El archivo contiene razones sociales distintas. Selecciona un solo RUT.');
  result.company = [...companies][0];
  if (!result.company) result.warnings.push('No se encontró la razón social en la casilla 35. Complétala manualmente.');

  const nits = new Set<string>();
  const completeNits = new Set<string>();
  for (const { page, lines } of layouts) {
    const label = anchors(lines, 5, 'numero de identificacion tributaria')[0];
    if (!label) continue;
    const dv = near(anchors(lines, 6, 'dv\\b'), label.y);
    if (!dv || dv.x <= label.x) continue;
    const end = near(anchors(lines, 12, 'direccion seccional'), label.y)?.x ?? dv.x + 20;
    // Printed labels are inset differently from digit cells on some RUT sheets.
    // Use one shared boundary, so the last NIT digit can never enter the DV too.
    const divider = dv.x + 3;
    const base = digits(cell(page, label, divider + 1, label.y + 24));
    const check = digits(cell(page, dv, end, label.y + 24, divider));
    if (base && base.length >= 5 && base.length <= 15) {
      nits.add(base);
      if (check?.length === 1) completeNits.add(`${base}-${check}`);
    }
  }
  if (nits.size > 1 || completeNits.size > 1) throw new Error('El archivo contiene NIT distintos. Selecciona un solo RUT.');
  result.nit = [...completeNits][0] ?? [...nits][0];
  if (!result.nit) result.warnings.push('No se pudo leer el NIT de las casillas 5 y 6. Complétalo manualmente.');
  else {
    const [base, dv] = result.nit.split('-');
    if (dv === undefined) result.warnings.push('Falta el dígito de verificación del NIT. Revísalo antes de generar el contrato.');
    else if (Number(dv) !== nitCheckDigit(base)) result.warnings.push('El dígito de verificación no coincide con el NIT leído. Revisa ambos datos; no se han corregido automáticamente.');
  }

  for (const { page, lines } of layouts) {
    // These numbered labels occur in the Representation sheet, not in partners/accountant sheets.
    const rows = anchors(lines, 98, 'representacion');
    for (let index = 0; index < rows.length; index++) {
      const row = rows[index], end = rows[index + 1]?.y ?? row.y + 96;
      const date = near(anchors(lines, 99, 'fecha inicio ejercicio representacion'), row.y);
      const type = below(anchors(lines, 100, 'tipo de documento'), row.y, end);
      const identity = type && near(anchors(lines, 101, 'numero de identificacion'), type.y);
      const firstSurname = below(anchors(lines, 104, 'primer apellido'), row.y, end);
      const secondSurname = firstSurname && near(anchors(lines, 105, 'segundo apellido'), firstSurname.y);
      const firstName = firstSurname && near(anchors(lines, 106, 'primer nombre'), firstSurname.y);
      const otherNames = firstSurname && near(anchors(lines, 107, 'otros nombres'), firstSurname.y);
      if (!date || !type || !identity || !firstSurname || !secondSurname || !firstName || !otherNames) {
        result.warnings.push('Una fila de representación tiene una estructura incompleta; revisa sus datos manualmente.');
        continue;
      }
      const role = cell(page, row, date.x, type.y);
      const documentRaw = cell(page, type, identity.x, firstSurname.y);
      const identityRight = near(anchors(lines, 102, 'dv\\b'), type.y)?.x ?? identity.x + 260;
      const identityRaw = cell(page, identity, identityRight, firstSurname.y);
      const nameBottom = below(anchors(lines, 108, 'numero de identificacion tributaria'), firstSurname.y, end)?.y ?? firstSurname.y + 24;
      const surnames = [cell(page, firstSurname, secondSurname.x, nameBottom), cell(page, secondSurname, firstName.x, nameBottom)];
      const names = [cell(page, firstName, otherNames.x, nameBottom), cell(page, otherNames, 590, nameBottom)];
      if (![role, documentRaw, identityRaw, ...names, ...surnames].some(Boolean)) continue;
      const name = tidy([...names, ...surnames].filter(Boolean).join(' '));
      const documentCode = documentRaw.match(/(?:^|\s)((?:\d\s*){2})$/)?.[1].replace(/\s/g, '');
      const documentLabel = tidy(documentRaw.replace(/(?:^|\s)(?:\d\s*){2}$/, ''));
      const citizen = /cedula de ciudadan/.test(plain(documentLabel)) && (!documentCode || documentCode === '13');
      const documentType = citizen ? 'Cédula de ciudadanía' : documentLabel || (documentCode ? `Documento tipo ${documentCode}` : 'No identificado');
      const normalizedRole = plain(role).replace(/\s+/g, ' ');
      const kind: RutRepresentative['kind'] = /legal\s+(?:prin(?:cipal)?)(?:\b|\s)/.test(normalizedRole) ? 'principal'
        : /legal\s+supl(?:ente)?(?:\b|\s)/.test(normalizedRole) ? 'suplente' : 'otro';
      const id = digits(identityRaw) ?? (/^[a-z\d .-]+$/i.test(identityRaw) ? identityRaw.replace(/\s/g, '') : '');
      const representative = { name, identity: id, kind, documentType };
      if (!result.representatives.some(r => r.name === name && r.identity === id && r.kind === kind && r.documentType === documentType)) result.representatives.push(representative);
      if (!names[0] || !surnames[0] || !id) result.warnings.push('Un representante tiene nombre o identificación incompletos. Revisa esa fila del RUT.');
      if (!citizen) result.warnings.push('Un representante usa un documento distinto o no identificable como cédula de ciudadanía. Revisa su tipo antes de usar la plantilla.');
    }
  }
  const principals = result.representatives.filter(r => r.kind === 'principal');
  if (principals.length > 1) result.warnings.push('El RUT contiene varios representantes principales. Selecciona quién firmará; no se ha elegido automáticamente.');
  if (!principals.length) result.warnings.push('No se encontró un representante legal principal. Selecciona o completa los datos manualmente.');
  result.warnings = [...new Set(result.warnings)];
  return result;
}
