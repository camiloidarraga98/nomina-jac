import {PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage, type RGB} from 'pdf-lib';
import {documentBrand} from './document-brand';
import logo from './document-logo.json';

const color = (hex: string) => rgb(...[0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16) / 255) as [number, number, number]);
const palette = Object.fromEntries(['navy', 'ink', 'cyan', 'pale', 'line', 'muted', 'canvas'].map(key => [key, color(documentBrand[key as 'navy'])])) as Record<'navy'|'ink'|'cyan'|'pale'|'line'|'muted'|'canvas', RGB>;
const safe = (value: unknown) => String(value ?? '').replace(/[\u2010-\u2015\u2212]/g, '-').replace(/[\u00a0\u202f]/g, ' ').replace(/[^\u000a\u0020-\u00ff\u20ac]/g, '');

type TextOptions = {size?: number; bold?: boolean; muted?: boolean; align?: 'left'|'right'; width?: number};
type Line = {text: string; size: number; bold?: boolean; muted?: boolean};
export type DocumentCell = {text: unknown; detail?: string; bold?: boolean; muted?: boolean};
export type DocumentColumn = {label: string; width: number; align?: 'left'|'right'};
type DocumentOptions = {title: string; period: string; company: string; nit: string; status: string; footer: string};

/** All coordinates are top-down. A row owns its padding and separator; no shared text baseline. */
export async function createDocumentPdf(options: DocumentOptions) {
  const doc = await PDFDocument.create();
  const regular = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const mark = await doc.embedPng(logo.base64);
  const left = 48, width = 516, pageHeight = 792, bottom = 705;
  let page: PDFPage, y = 0, bodyStart = 0;

  const font = (strong?: boolean) => strong ? bold : regular;
  const wrap = (value: unknown, maxWidth: number, size: number, face: PDFFont = regular): string[] => {
    const lines: string[] = [];
    for (const paragraph of safe(value).split('\n')) {
      let line = '';
      for (const word of paragraph.split(/\s+/).filter(Boolean)) {
        const combined = line ? line + ' ' + word : word;
        if (face.widthOfTextAtSize(combined, size) <= maxWidth) { line = combined; continue; }
        if (line) { lines.push(line); line = ''; }
        // IDs, URLs and names without spaces also stay inside their column.
        for (const character of word) {
          if (line && face.widthOfTextAtSize(line + character, size) > maxWidth) { lines.push(line); line = ''; }
          line += character;
        }
      }
      lines.push(line);
    }
    return lines.length ? lines : [''];
  };
  const put = (value: unknown, x: number, baseline: number, opt: TextOptions = {}) => {
    const text = safe(value), size = opt.size ?? 9, face = font(opt.bold);
    page.drawText(text, {x: opt.align === 'right' ? x - face.widthOfTextAtSize(text, size) : x,
      y: pageHeight - baseline, size, font: face, color: opt.muted ? palette.muted : palette.ink});
  };
  const line = (top: number) => page.drawLine({start: {x: left, y: pageHeight - top}, end: {x: left + width, y: pageHeight - top}, thickness: .5, color: palette.line});
  const rectangle = (top: number, height: number, fill: RGB, x = left, w = width) => page.drawRectangle({x, y: pageHeight - top - height, width: w, height, color: fill});

  function addPage(context?: string) {
    page = doc.addPage([612, pageHeight]);
    rectangle(0, 7, palette.navy, 0, 612);
    rectangle(0, 7, palette.cyan, 0, 144);
    page.drawImage(mark, {x: left, y: pageHeight - 80, width: 116, height: 116 * mark.height / mark.width});
    let headingY = 47;
    for (const text of wrap(options.title, 348, 18, bold)) { put(text, 216, headingY, {size: 18, bold: true}); headingY += 26; }
    put(options.period, 216, headingY + 1, {size: 10, muted: true});
    for (const text of wrap(options.status, 348, 7.5, bold)) { headingY += 15; put(text, 216, headingY, {size: 7.5, bold: true, muted: true}); }
    const divider = Math.max(105, headingY + 14);
    line(divider); rectangle(divider - 1, 2, palette.cyan, left, 38);
    y = divider + 19;
    for (const text of wrap(options.company + ' · NIT ' + options.nit, width, 8, bold)) { put(text, left, y, {size: 8, bold: true, muted: true}); y += 11; }
    if (context) for (const text of wrap(context, width, 8)) { put(text, left, y + 2, {size: 8, muted: true}); y += 12; }
    y += 12; bodyStart = y;
  }
  const ensure = (height: number, context?: string) => { if (y + height > bottom) addPage(context ?? 'Continuación'); };
  const gap = (height = 16) => { y += height; };
  function paragraph(value: unknown, opt: TextOptions = {}) {
    const size = opt.size ?? 9, leading = size * 1.4;
    for (const text of wrap(value, opt.width ?? width, size, font(opt.bold))) {
      ensure(leading); put(text, left, y + size, opt); y += leading;
    }
  }
  function section(title: string, minimumAfter = 0) {
    ensure(34 + minimumAfter);
    rectangle(y, 25, palette.pale); put(title, left + 10, y + 16, {size: 8.5, bold: true}); y += 34;
  }
  function keyValue(label: string, value: string, strong = false) {
    const labels = wrap(label, 290, 9, font(strong)), values = wrap(value, 196, 10, font(strong));
    const height = Math.max(labels.length, values.length) * 14 + 9;
    ensure(height);
    labels.forEach((text, i) => put(text, left, y + 10 + i * 14, {size: 9, bold: strong, muted: !strong}));
    values.forEach((text, i) => put(text, left + width, y + 10 + i * 14, {size: 10, bold: strong, align: 'right'}));
    y += height;
  }
  function total(label: string, value: string, note?: string) {
    let size = 25;
    while (bold.widthOfTextAtSize(safe(value), size) > width - 32 && size > 12) size -= .5;
    const values = wrap(value, width - 32, size, bold), notes = note ? wrap(note, width - 32, 8) : [];
    const firstValueBaseline = 36 + size, valueLeading = size * 1.4;
    const lastValueBaseline = firstValueBaseline + (values.length - 1) * valueLeading;
    const noteBaseline = lastValueBaseline + size * .32 + 14;
    const height = notes.length ? noteBaseline + (notes.length - 1) * 12 + 17 : lastValueBaseline + size * .32 + 14;
    ensure(height);
    rectangle(y, height, palette.canvas); rectangle(y, height, palette.cyan, left, 3);
    put(label, left + 16, y + 21, {size: 8, bold: true, muted: true});
    values.forEach((text, i) => put(text, left + 16, y + firstValueBaseline + i * valueLeading, {size, bold: true}));
    notes.forEach((text, i) => put(text, left + 16, y + noteBaseline + i * 12, {size: 8, muted: true}));
    y += height;
  }

  function table(columns: DocumentColumn[], rows: DocumentCell[][], context?: string, title?: string) {
    if (Math.abs(columns.reduce((n, column) => n + column.width, 0) - width) > .01) throw Error('Las columnas deben ocupar el ancho del documento.');
    const padding = 9, leading = 12;
    const headings = columns.map(column => wrap(column.label, column.width - padding * 2, 7.5, bold));
    const headerHeight = Math.max(...headings.map(lines => lines.length)) * 10 + 18;
    const prepared = rows.map(cells => columns.map((column, index): Line[] => {
      const cell = cells[index] ?? {text: ''}; let size = 8.7;
      if (column.align === 'right') while (font(cell.bold).widthOfTextAtSize(safe(cell.text), size) > column.width - padding * 2 && size > 6.2) size -= .2;
      return [...wrap(cell.text, column.width - padding * 2, size, font(cell.bold)).map(text => ({text, size, bold: cell.bold, muted: cell.muted})),
        ...(cell.detail ? wrap(cell.detail, column.width - padding * 2, 7).map(text => ({text, size: 7, muted: true})) : [])];
    }));
    const rowHeight = (row: Line[][]) => Math.max(...row.map(lines => lines.length)) * leading + padding * 2;
    const drawHeader = () => {
      rectangle(y, headerHeight, palette.pale); let x = left;
      columns.forEach((column, i) => {
        headings[i].forEach((text, j) => put(text, column.align === 'right' ? x + column.width - padding : x + padding, y + 14 + j * 10, {size: 7.5, bold: true, align: column.align}));
        x += column.width;
      }); y += headerHeight;
    };
    const titleHeight = title ? 34 : 0;
    ensure(titleHeight + headerHeight + (prepared.length ? Math.min(rowHeight(prepared[0]), bottom - bodyStart - headerHeight - titleHeight) : 30), context);
    if (title) section(title);
    drawHeader();
    if (!rows.length) { paragraph('No hay registros en este periodo.', {muted: true}); gap(); return; }
    for (const row of prepared) {
      const height = rowHeight(row);
      if (y + height > bottom && height <= bottom - bodyStart - headerHeight) { addPage(context ?? 'Continuación'); drawHeader(); }
      // Normally a complete row fits on one page. Exceptionally long content can span pages.
      const count = Math.max(...row.map(lines => lines.length)); let offset = 0;
      while (offset < count) {
        const capacity = Math.floor((bottom - y - padding * 2) / leading);
        if (capacity < 1) { addPage(context ?? 'Continuación'); drawHeader(); continue; }
        const length = Math.min(capacity, count - offset), height = length * leading + padding * 2;
        let x = left;
        columns.forEach((column, c) => {
          row[c].slice(offset, offset + length).forEach((text, i) => put(text.text, column.align === 'right' ? x + column.width - padding : x + padding, y + padding + 9 + i * leading, {...text, align: column.align}));
          x += column.width;
        });
        y += height; line(y); offset += length;
        if (offset < count) { addPage(context ?? 'Continuación'); drawHeader(); }
      }
    }
  }

  function finish() {
    const current = page;
    doc.getPages().forEach((item, index) => {
      page = item; line(727);
      put('E-mail: ' + documentBrand.email, left, 742, {size: 6.4, muted: true});
      put('Tel: ' + documentBrand.phone, left, 753, {size: 6.4, muted: true});
      put(documentBrand.address, 260, 742, {size: 6.2, muted: true});
      put(documentBrand.social, 260, 753, {size: 6.4, muted: true});
      put(options.footer, left, 773, {size: 6.8, muted: true});
      put(`${String(index + 1).padStart(2, '0')} / ${String(doc.getPageCount()).padStart(2, '0')}`, left + width, 773, {size: 7, bold: true, align: 'right'});
    });
    page = current; doc.setTitle(options.title + ' · JAC Music'); doc.setAuthor(options.company);
    return doc.save();
  }
  return {addPage, ensure, gap, paragraph, section, keyValue, total, table, finish, get remaining() { return bottom - y; }, get bodyHeight() { return bottom - bodyStart; }};
}
