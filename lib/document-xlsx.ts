import {zipSync, strToU8} from 'fflate';
import {documentBrand as brand} from './document-brand';
import logo from './document-logo.json';

export type DocumentExcelCell = string|number|{formula: string; value: number; style?: number};
export type DocumentExcelSheet = {
  name: string; rows: DocumentExcelCell[][]; widths: number[]; header: number; moneyCols: number[];
  sectionHeaders?: number[]; filter?: boolean;
  rowStyles?: Record<number, 'team'|'commission'|'total'>;
};
type Options = {title: string; company: string; nit: string; context: string; review: boolean};
const xml = (value: unknown) => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
const col = (index: number) => { let value = ''; for (index++; index; index = Math.floor((index - 1) / 26)) value = String.fromCharCode(65 + (index - 1) % 26) + value; return value; };
const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const relNs = 'http://schemas.openxmlformats.org/package/2006/relationships';

// A conservative Arial width estimate, including long words and explicit newlines.
function lineCount(text: string, columns: number) {
  const limit = Math.max(1, columns - 3);
  return text.split('\n').reduce((count, paragraph) => {
    let lines = 1, used = 0;
    for (const word of paragraph.split(/\s+/)) {
      const width = [...word].reduce((n, character) => n + (/[MW@ÁÉÓÚ]/.test(character) ? 1.45 : /[il.,' ]/.test(character) ? .5 : 1), 0);
      if (used && used + width + 1 > limit) { lines++; used = 0; }
      if (width > limit) { lines += Math.ceil(width / limit) - 1; used = width % limit || limit; }
      else used += (used ? 1 : 0) + width;
    }
    return count + lines;
  }, 0);
}

/** Adds one reusable letterhead; shifts only formulas authored by the exporter, never cell text. */
export function documentWorkbook(sheets: DocumentExcelSheet[], options: Options) {
  const files: Record<string, Uint8Array> = {}, add = (path: string, text: string) => { files[path] = strToU8(text); };
  const relationships = (body: string) => `<?xml version="1.0"?><Relationships xmlns="${relNs}">${body}</Relationships>`;
  const relationship = (id: string, type: string, target: string) => `<Relationship Id="${id}" Type="${rel}/${type}" Target="${target}"/>`;
  const prefixRows = 4;
  const styles = {
    text: 0, number: 1, money: 2, header: 3, rightHeader: 4, title: 5, meta: 6, company: 7,
    team: 8, teamMoney: 9, total: 10, totalMoney: 11, commission: 12, commissionMoney: 13, empty: 14, rightText: 15,
  };
  const xf = (fontId: number, fillId: number, borderId: number, format = 0, alignment = 'horizontal="left" vertical="top" wrapText="1"') =>
    `<xf numFmtId="${format}" fontId="${fontId}" fillId="${fillId}" borderId="${borderId}" xfId="0" applyAlignment="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"><alignment ${alignment}/></xf>`;
  const numeric = 'horizontal="right" vertical="top" shrinkToFit="1"', rightWrap = 'horizontal="right" vertical="top" wrapText="1"';
  const formats = [xf(0,0,1), xf(0,0,1,0,numeric), xf(0,0,1,164,numeric), xf(1,2,0), xf(1,2,0,0,rightWrap),
    xf(2,0,0), xf(3,0,0), xf(1,0,2,0,rightWrap), xf(1,3,1), xf(1,3,1,164,numeric), xf(4,4,0), xf(4,4,0,164,numeric),
    xf(0,3,1), xf(0,3,1,164,numeric), xf(0,0,0), xf(0,0,1,0,rightWrap)];
  const font = (size: number, hex: string, bold = false) => `<font>${bold ? '<b/>' : ''}<sz val="${size}"/><name val="Arial"/><color rgb="FF${hex}"/></font>`;
  const fill = (hex: string) => `<fill><patternFill patternType="solid"><fgColor rgb="FF${hex}"/><bgColor indexed="64"/></patternFill></fill>`;
  add('xl/styles.xml', `<?xml version="1.0"?><styleSheet xmlns="${ns}"><numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;$&quot; #,##0.00;[Red]-&quot;$&quot; #,##0.00"/></numFmts><fonts count="5">${font(10,brand.ink)}${font(10,brand.navy,true)}${font(18,brand.navy,true)}${font(9,brand.muted)}${font(10,'FFFFFF',true)}</fonts><fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>${fill(brand.pale)}${fill(brand.canvas)}${fill(brand.navy)}</fills><borders count="3"><border/><border><bottom style="hair"><color rgb="FF${brand.line}"/></bottom></border><border><bottom style="medium"><color rgb="FF${brand.cyan}"/></bottom></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="${formats.length}">${formats.join('')}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`);
  files['xl/media/jac-logo.png'] = Uint8Array.from(atob(logo.base64), character => character.charCodeAt(0));
  add('[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/drawings/drawing${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>`).join('')}</Types>`);
  add('_rels/.rels', relationships(relationship('rId1', 'officeDocument', 'xl/workbook.xml')));
  add('xl/_rels/workbook.xml.rels', relationships(sheets.map((_, i) => relationship('rId'+(i+1), 'worksheet', `worksheets/sheet${i+1}.xml`)).join('') + relationship('rIdStyles', 'styles', 'styles.xml')));
  const printNames: string[] = [];

  sheets.forEach((sheet, index) => {
    const count = sheet.widths.length, lastColumn = col(count - 1), skip = sheet.header - 1, offset = prefixRows - skip;
    const header = prefixRows + 1, data = sheet.rows.slice(skip), end = prefixRows + data.length;
    const sectionHeaders = new Set([header, ...(sheet.sectionHeaders ?? []).map(row => row + offset)]);
    const merges = [`B1:${lastColumn}1`, `A2:${lastColumn}2`, `A3:${lastColumn}3`].filter(range => range.split(':')[0] !== range.split(':')[1]);
    const cell = (value: DocumentExcelCell, row: number, column: number, style: number) => {
      const ref = col(column) + row;
      if (typeof value === 'object') {
        const formula = value.formula.replace(/(\$?[A-Z]+\$?)(\d+)/g, (_, letter: string, n: string) => letter + (Number(n) + offset));
        return `<c r="${ref}" s="${style}"><f>${xml(formula)}</f><v>${value.value}</v></c>`;
      }
      if (typeof value === 'number') return `<c r="${ref}" s="${style}"><v>${value}</v></c>`;
      return `<c r="${ref}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>`;
    };
    const company = options.company + '\nNIT ' + options.nit, totalWidth = sheet.widths.reduce((a, b) => a + b, 0);
    const prefix = [
      {value: company, column: 1, height: Math.max(52, lineCount(company, totalWidth-sheet.widths[0]) * 14 + 12), style: styles.company},
      {value: sheet.name === 'Resumen' ? options.title : options.title + ' · ' + sheet.name, column: 0, height: 35, style: styles.title},
      {value: options.context, column: 0, height: Math.max(27, lineCount(options.context, totalWidth) * 13 + 10), style: styles.meta},
      {value: '', column: 0, height: 10, style: styles.empty},
    ].map((row, i) => `<row r="${i+1}" ht="${row.height}" customHeight="1">${Array.from({length: count}, (_, c) => cell(c === row.column ? row.value : '', i+1, c, row.style)).join('')}</row>`).join('');
    let lastDataRow = end;
    const rows = data.map((row, r) => {
      const number = r + prefixRows + 1, isHeader = sectionHeaders.has(number);
      const kind = sheet.rowStyles?.[number - offset], total = kind === 'total', team = kind === 'team', commission = kind === 'commission';
      if ((total || team || commission) && lastDataRow === end) lastDataRow = number - 1;
      const lines = Math.max(1, ...row.map((value, c) => typeof value === 'string' ? lineCount(value, sheet.widths[c]) : 1));
      const height = Math.max(isHeader ? 33 : 29, lines * 14 + 14);
      const cells = Array.from({length: count}, (_, c) => {
        const value = row[c] ?? '', numericValue = typeof value !== 'string';
        const monetary = sheet.moneyCols.includes(c), right = monetary || numericValue;
        const style = isHeader ? (monetary ? styles.rightHeader : styles.header)
          : total ? (monetary && numericValue ? styles.totalMoney : styles.total)
          : team ? (monetary && numericValue ? styles.teamMoney : styles.team)
          : commission ? (monetary && numericValue ? styles.commissionMoney : styles.commission)
          : monetary && numericValue ? styles.money : numericValue ? styles.number : right ? styles.rightText : styles.text;
        return cell(value, number, c, style);
      }).join('');
      return `<row r="${number}" ht="${height}" customHeight="1">${cells}</row>`;
    }).join('');
    const sheetQuoted = "'" + sheet.name.replaceAll("'", "''") + "'";
    printNames.push(`<definedName name="_xlnm.Print_Titles" localSheetId="${index}">${xml(sheetQuoted)}!$1:$${header}</definedName>`,
      `<definedName name="_xlnm.Print_Area" localSheetId="${index}">${xml(sheetQuoted)}!$A$1:$${lastColumn}$${end}</definedName>`);
    const footer = '&LJAC MUSIC · ' + (options.review ? 'PRELIQUIDACIÓN · PARA REVISIÓN' : brand.email) + '&RPágina &P de &N';
    add(`xl/worksheets/sheet${index+1}.xml`, `<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="${ns}" xmlns:r="${rel}"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:${lastColumn}${end}"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="${header}" topLeftCell="A${header+1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="29"/><cols>${sheet.widths.map((w, c) => `<col min="${c+1}" max="${c+1}" width="${w}" customWidth="1"/>`).join('')}</cols><sheetData>${prefix}${rows}</sheetData>${sheet.filter !== false && lastDataRow > header ? `<autoFilter ref="A${header}:${lastColumn}${lastDataRow}"/>` : ''}<mergeCells count="${merges.length}">${merges.map(ref => `<mergeCell ref="${ref}"/>`).join('')}</mergeCells><printOptions horizontalCentered="1"/><pageMargins left="0.35" right="0.35" top="0.4" bottom="0.55" header="0.15" footer="0.25"/><pageSetup paperSize="${totalWidth > 205 ? 8 : 9}" orientation="landscape" fitToWidth="1" fitToHeight="0"/><headerFooter><oddFooter>${xml(footer)}</oddFooter></headerFooter><drawing r:id="rIdDrawing"/></worksheet>`);
    add(`xl/worksheets/_rels/sheet${index+1}.xml.rels`, relationships(relationship('rIdDrawing', 'drawing', `../drawings/drawing${index+1}.xml`)));
    add(`xl/drawings/_rels/drawing${index+1}.xml.rels`, relationships(relationship('rIdLogo', 'image', '../media/jac-logo.png')));
    const imageWidth = Math.min(128, sheet.widths[0] * 7 - 16), imageHeight = imageWidth * logo.height / logo.width;
    add(`xl/drawings/drawing${index+1}.xml`, `<?xml version="1.0" encoding="UTF-8"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>76200</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>76200</xdr:rowOff></xdr:from><xdr:ext cx="${Math.round(imageWidth*9525)}" cy="${Math.round(imageHeight*9525)}"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="1" name="JAC Music" descr="Logo oficial JAC Music"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip xmlns:r="${rel}" r:embed="rIdLogo"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>`);
  });
  add('xl/workbook.xml', `<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="${ns}" xmlns:r="${rel}"><sheets>${sheets.map((sheet, i) => `<sheet name="${xml(sheet.name)}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join('')}</sheets><definedNames>${printNames.join('')}</definedNames><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>`);
  return zipSync(files, {level: 6});
}
