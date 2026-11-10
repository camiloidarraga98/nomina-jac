(function () {
  'use strict';

  const normalize = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
  const limits = { bytes: 30 * 1024 * 1024, sheets: 100, rows: 30000, columns: 200 };

  function normalizeAmount(value) {
    if (typeof value === 'number') return Number.isFinite(value) ? Math.round(value * 100) / 100 : null;
    let text = String(value ?? '').trim();
    if (!text) return null;
    const negative = /^\(.*\)$/.test(text);
    if (negative) text = text.slice(1, -1);
    text = text.replace(/\bCOP\b/gi, '').replace(/[$\s\u00a0]/g, '');
    if (!/^[+-]?(?:\d[\d.,]*|[.,]\d+)$/.test(text)) return null;
    const dot = text.lastIndexOf('.');
    const comma = text.lastIndexOf(',');
    if (dot >= 0 && comma >= 0) {
      const decimal = dot > comma ? '.' : ',';
      const thousands = decimal === '.' ? ',' : '.';
      const pieces = text.split(decimal);
      if (pieces.length !== 2 || !/^\d{1,2}$/.test(pieces[1])) return null;
      const integer = pieces[0].replace(/^[+-]/, '');
      if (!new RegExp('^\\d{1,3}(?:\\' + thousands + '\\d{3})+$').test(integer)) return null;
      text = pieces[0].split(thousands).join('') + '.' + pieces[1];
    } else if (dot >= 0 || comma >= 0) {
      const separator = dot >= 0 ? '.' : ',';
      const signless = text.replace(/^[+-]/, '');
      const pieces = signless.split(separator);
      if (pieces.length === 2 && pieces[1].length <= 2 && pieces[1].length > 0) {
        text = text.replace(separator, '.');
      } else if (/^\d{1,3}$/.test(pieces[0]) && pieces.slice(1).every(piece => /^\d{3}$/.test(piece))) {
        text = text.split(separator).join('');
      } else return null;
    }
    const amount = Number(text) * (negative ? -1 : 1);
    return Number.isFinite(amount) && Math.abs(amount) <= Number.MAX_SAFE_INTEGER / 100 ? Math.round(amount * 100) / 100 : null;
  }

  function isoDate(year, month, day) {
    if (year < 1900 || year > 2400 || month < 1 || month > 12 || day < 1 || day > 31) return '';
    const date = new Date(Date.UTC(year, month - 1, day));
    return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
      ? `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}` : '';
  }

  function excelDate(value, date1904 = false) {
    const serial = Math.floor(Number(value));
    if (!Number.isFinite(serial) || serial < (date1904 ? 0 : 1) || serial > 150000) return '';
    if (!date1904 && serial === 60) return ''; // Excel's fictitious 29 February 1900.
    const base = date1904 ? Date.UTC(1904, 0, 1) : Date.UTC(1899, 11, 31);
    return new Date(base + (date1904 ? serial : serial > 60 ? serial - 1 : serial) * 86400000).toISOString().slice(0, 10);
  }

  function normalizeDate(value) {
    if (value instanceof Date) return Number.isNaN(value.getTime()) ? '' : value.toISOString().slice(0, 10);
    if (typeof value === 'number') return excelDate(value);
    const text = String(value ?? '').trim();
    if (!text) return '';
    let match = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T]00:00(?::00(?:\.0+)?)?(?:Z)?)?$/);
    if (match) return isoDate(Number(match[1]), Number(match[2]), Number(match[3]));
    match = text.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4}|\d{2})(?:\s+00:00(?::00)?)?$/);
    if (match) {
      let year = Number(match[3]);
      if (match[3].length === 2) year += year >= 70 ? 1900 : 2000;
      return isoDate(year, Number(match[2]), Number(match[1]));
    }
    if (/^\d{5,6}(?:\.\d+)?$/.test(text)) return excelDate(Number(text));
    return '';
  }

  function parseCsv(text) {
    text = String(text ?? '').replace(/^\uFEFF/, '');
    const counts = { ';': 0, ',': 0, '\t': 0 };
    let quoted = false;
    for (let i = 0; i < text.length; i++) {
      const character = text[i];
      if (character === '"') {
        if (quoted && text[i + 1] === '"') i++;
        else quoted = !quoted;
      } else if (!quoted && (character === '\n' || character === '\r')) break;
      else if (!quoted && Object.prototype.hasOwnProperty.call(counts, character)) counts[character]++;
    }
    const delimiter = Object.keys(counts).sort((a, b) => counts[b] - counts[a])[0];
    const rows = [];
    let row = [], cell = '', inQuotes = false, closedQuote = false;
    function pushCell() { row.push(cell); cell = ''; closedQuote = false; }
    function pushRow() {
      pushCell();
      if (row.length > limits.columns) throw new Error('El archivo supera 200 columnas. Divide el archivo antes de importarlo.');
      rows.push(row); row = [];
      if (rows.length > limits.rows) throw new Error('El archivo supera 30.000 filas. Divide el archivo antes de importarlo.');
    }
    for (let i = 0; i < text.length; i++) {
      const character = text[i];
      if (inQuotes) {
        if (character === '"') {
          if (text[i + 1] === '"') { cell += '"'; i++; }
          else { inQuotes = false; closedQuote = true; }
        } else cell += character;
      } else if (character === '"' && cell === '' && !closedQuote) inQuotes = true;
      else if (character === delimiter) pushCell();
      else if (character === '\n' || character === '\r') {
        if (character === '\r' && text[i + 1] === '\n') i++;
        pushRow();
      } else {
        if (closedQuote && !/\s/.test(character)) throw new Error('El CSV contiene comillas mal cerradas. Revisa el archivo.');
        if (!closedQuote) cell += character;
      }
    }
    if (inQuotes) throw new Error('El CSV tiene una celda con comillas sin cerrar.');
    if (cell !== '' || row.length || closedQuote) pushRow();
    return rows;
  }

  function elements(parent, localName) {
    return Array.from(parent.getElementsByTagNameNS('*', localName));
  }
  function xmlDocument(text) {
    const document = new DOMParser().parseFromString(text, 'application/xml');
    if (elements(document, 'parsererror').length) throw new Error('El Excel contiene XML inválido. Vuelve a guardarlo como .xlsx.');
    return document;
  }
  function columnNumber(reference) {
    const letters = String(reference).match(/^[A-Z]+/i)?.[0];
    if (!letters) return -1;
    let number = 0;
    for (const letter of letters.toUpperCase()) number = number * 26 + letter.charCodeAt(0) - 64;
    return number - 1;
  }
  function resolvePart(base, target) {
    const parts = target.startsWith('/') ? [] : base.split('/').slice(0, -1);
    for (const part of target.split('/')) {
      if (part === '..') parts.pop();
      else if (part && part !== '.') parts.push(part);
    }
    return parts.join('/');
  }

  async function parseXlsx(file) {
    if (!globalThis.JSZip) throw new Error('No se pudo cargar el lector de Excel. Recarga la página.');
    if (file.size > limits.bytes) throw new Error('El Excel supera 30 MB. Divide el archivo antes de importarlo.');
    let zip;
    try { zip = await JSZip.loadAsync(await file.arrayBuffer()); }
    catch { throw new Error('No se pudo abrir el Excel. Usa un archivo .xlsx sin contraseña o un CSV.'); }
    async function readPart(path, required = true) {
      const part = zip.file(path);
      if (!part && required) throw new Error(`Falta una parte necesaria del Excel: ${path}.`);
      return part ? xmlDocument(await part.async('string')) : null;
    }
    const workbookPath = 'xl/workbook.xml';
    const workbook = await readPart(workbookPath);
    const relationships = await readPart('xl/_rels/workbook.xml.rels');
    const relationById = new Map(elements(relationships, 'Relationship').filter(item => item.getAttribute('TargetMode') !== 'External').map(item => [item.getAttribute('Id'), resolvePart(workbookPath, item.getAttribute('Target'))]));
    const sharedPart = await readPart('xl/sharedStrings.xml', false);
    const strings = sharedPart ? elements(sharedPart, 'si').map(item => elements(item, 't').map(node => node.textContent).join('')) : [];
    const styles = await readPart('xl/styles.xml', false);
    const formats = new Map(styles ? elements(styles, 'numFmt').map(item => [Number(item.getAttribute('numFmtId')), item.getAttribute('formatCode')]) : []);
    const formatIds = styles ? Array.from(elements(styles, 'cellXfs')[0]?.children || []).filter(item => item.localName === 'xf').map(item => Number(item.getAttribute('numFmtId'))) : [];
    function isDateStyle(style) {
      const id = formatIds[style];
      if ((id >= 14 && id <= 22) || (id >= 27 && id <= 36) || (id >= 45 && id <= 47) || (id >= 50 && id <= 58)) return true;
      const format = String(formats.get(id) || '').replace(/"[^"]*"|\\.|\[[^\]]*\]/g, '');
      return /[yd]/i.test(format) && /[md]/i.test(format);
    }
    const date1904 = ['1', 'true'].includes(elements(workbook, 'workbookPr')[0]?.getAttribute('date1904'));
    const sheetEntries = elements(workbook, 'sheet');
    if (sheetEntries.length > limits.sheets) throw new Error('El Excel supera 100 hojas. Divide el archivo antes de importarlo.');
    const sheets = [];
    for (const sheet of sheetEntries) {
      const relation = sheet.getAttribute('r:id') || sheet.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id');
      const target = relationById.get(relation);
      if (!target) throw new Error(`No se pudo localizar la hoja ${sheet.getAttribute('name')}.`);
      if (!/worksheets\//.test(target)) continue; // Charts are not importable worksheets.
      const document = await readPart(target);
      const rows = [];
      let materializedRows = 0;
      for (const row of elements(document, 'row')) {
        const rowIndex = Number(row.getAttribute('r')) - 1;
        if (!Number.isInteger(rowIndex) || rowIndex < 0 || rowIndex > 1048575) throw new Error('Una hoja contiene números de fila inválidos. Vuelve a guardarla como Excel .xlsx.');
        const values = [];
        for (const cell of elements(row, 'c')) {
          const type = cell.getAttribute('t');
          const raw = elements(cell, 'v')[0]?.textContent ?? '';
          const inlineText = type === 'inlineStr' ? elements(cell, 't').map(node => node.textContent).join('') : '';
          if (raw === '' && inlineText === '') continue; // Formatting alone does not materialize a row or column.
          const index = columnNumber(cell.getAttribute('r'));
          if (index < 0 || index >= limits.columns) throw new Error('Una hoja supera 200 columnas o tiene referencias inválidas.');
          while (values.length <= index) values.push('');
          if (type === 's') values[index] = strings[Number(raw)] ?? '';
          else if (type === 'inlineStr') values[index] = inlineText;
          else if (type === 'b') values[index] = raw === '1' ? 'VERDADERO' : 'FALSO';
          else if (type === 'e') values[index] = raw; // Preserve errors for the user's import preview.
          else if (type === 'str' || type === 'd') values[index] = raw;
          else if (raw !== '' && Number.isFinite(Number(raw))) {
            const number = Number(raw);
            const style = Number(cell.getAttribute('s') || 0);
            if (isDateStyle(style)) values[index] = excelDate(number, date1904) || raw;
            else {
              const format = formats.get(formatIds[style]) || '';
              if (/^0{2,}$/.test(format) && Number.isInteger(number) && number >= 0) values[index] = raw.padStart(format.length, '0');
              else values[index] = Number.isSafeInteger(number) || !Number.isInteger(number) ? number : raw;
            }
          } else values[index] = raw;
        }
        if (!values.some(value => value !== '' && value !== null && value !== undefined)) continue;
        if (Object.prototype.hasOwnProperty.call(rows, rowIndex)) throw new Error('La hoja contiene una fila repetida. Vuelve a guardarla como Excel .xlsx.');
        materializedRows++;
        if (materializedRows > limits.rows) throw new Error('Una hoja supera 30.000 filas con datos. Divide el Excel antes de importarlo.');
        // Sparse indices preserve the exact Excel row without allocating a million empty rows.
        rows[rowIndex] = values;
      }
      sheets.push({ name: sheet.getAttribute('name') || `Hoja ${sheets.length + 1}`, rows });
    }
    if (!sheets.length) throw new Error('No se encontraron hojas con datos en el Excel.');
    return { sheets };
  }

  function safeCsvValue(value) {
    if (value === null || value === undefined) return '""';
    if (typeof value === 'number' && Number.isFinite(value)) return String(value).replace('.', ',');
    let text = typeof value === 'object' ? JSON.stringify(value) : String(value);
    if (/^[\s\u0000-\u001f]*[=+\-@]/.test(text) || /^[\t\r\n]/.test(text)) text = "'" + text;
    return '"' + text.replace(/"/g, '""') + '"';
  }

  const statusLabels = { pending: 'Pendiente', review: 'En revisión', identified: 'Identificado' };
  const billingLabels = { unknown: 'Por confirmar', required: 'Requiere factura', not_required: 'No requiere factura' };
  function csvForPayments(payments) {
    const originalKeys = Array.from(new Set(payments.flatMap(payment => Object.keys(payment.original || {}))));
    const columns = [
      ['ID abono', p => p.id], ['Archivo de origen', p => p.importName], ['Hoja original', p => p.sheet], ['Fila original', p => p.sourceRow],
      ['Fecha consignación', p => p.date], ['Valor COP', p => p.amount], ['Descripción bancaria', p => p.description], ['Referencia bancaria', p => p.reference],
      ['Tercero original', p => p.thirdParty], ['Recibo de caja original', p => p.receipt], ['Factura original', p => p.invoice],
      ['Estado conciliación', p => statusLabels[p.status] || p.status], ['Listo para contabilidad', p => p.status === 'identified' && p.attachments?.length ? 'Sí' : 'No'],
      ['ID show', p => p.showId], ['Show', p => p.showName || p.show?.name], ['Fecha show', p => p.showDate || p.show?.date], ['Ciudad show', p => p.showCity || p.show?.city],
      ['Empresario', p => p.entrepreneur], ['Titular que consignó', p => p.payer], ['Facturación', p => billingLabels[p.billingStatus] || p.billingStatus],
      ['NIT', p => p.nit], ['Razón social', p => p.businessName], ['Observaciones', p => p.notes],
      ['Cantidad de soportes', p => p.attachments?.length || 0], ['Soportes', p => (p.attachments || []).map(a => attachmentPath(p, a)).join(' | ')],
      ['Última modificación', p => p.updatedAt], ['Versión', p => p.version],
      ...originalKeys.map(key => [`Original · ${key}`, p => p.original?.[key]])
    ];
    return '\uFEFF' + [columns.map(([label]) => safeCsvValue(label)).join(';'), ...payments.map(payment => columns.map(([, get]) => safeCsvValue(get(payment))).join(';'))].join('\r\n') + '\r\n';
  }

  function safeFilename(value, fallback = 'archivo') {
    const name = String(value || fallback).normalize('NFC').replace(/[\u0000-\u001f<>:"/\\|?*]/g, '_').replace(/\.{2,}/g, '.').replace(/^\.+|\.+$/g, '').slice(0, 140);
    return name || fallback;
  }
  function attachmentPath(payment, attachment) {
    return `soportes/${safeFilename(payment.id, 'abono')}/${safeFilename(attachment.id, 'soporte')}-${safeFilename(attachment.name)}`;
  }
  function downloadBlob(blob, name) {
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url; link.download = name; link.hidden = true;
    document.body.appendChild(link); link.click(); link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }

  let accessEpoch=0;
  globalThis.addEventListener?.('jac-reconciliation-access-denied',()=>{accessEpoch++;});
  async function exportPackage(payments, options = {}) {
    const epoch=accessEpoch;
    const checkAccess=()=>{if(epoch!==accessEpoch)throw new Error('Tu acceso cambió. Se canceló la exportación; vuelve a ingresar.');};
    const { includeFiles = true, filename = 'conciliacion', onProgress } = options;
    if (!payments.length) throw new Error('No hay abonos para exportar con los filtros seleccionados.');
    const name = safeFilename(filename).replace(/\.(zip|csv)$/i, '');
    const csv = csvForPayments(payments);
    if (!includeFiles) {
      downloadBlob(new Blob([csv], { type: 'text/csv;charset=utf-8' }), `${name}.csv`);
      return { payments: payments.length, files: 0 };
    }
    if (!globalThis.JSZip) throw new Error('No se pudo cargar el exportador. Recarga la página.');
    const zip = new JSZip();
    zip.file('relacion.csv', csv);
    const total = payments.reduce((sum, payment) => sum + (payment.attachments?.length || 0), 0);
    if(payments.reduce((sum,p)=>sum+(p.attachments||[]).reduce((n,f)=>n+Number(f.size||0),0),0)>200*1024*1024)throw new Error('Los soportes superan 200 MB. Filtra los abonos y exporta en varios paquetes.');
    let downloaded = 0;
    let bytes = 0;
    for (const payment of payments) {
      for (const attachment of payment.attachments || []) {
        const url = new URL(attachment.url || `/api/reconciliation/files/${encodeURIComponent(attachment.id)}`, location.origin);
        if (url.origin !== location.origin || !url.pathname.startsWith('/api/reconciliation/files/')) throw new Error('Un soporte tiene una dirección no válida. Vuelve a cargar los datos.');
        const response = await fetch(url.href, { credentials: 'same-origin' });
        if ([401,403].includes(response.status)) globalThis.dispatchEvent(new CustomEvent('jac-reconciliation-access-denied',{detail:{status:response.status}}));
        if (!response.ok) throw new Error(`No se pudo descargar ${attachment.name}. No se generó el paquete; inténtalo nuevamente.`);
        const data = await response.arrayBuffer();
        checkAccess();
        bytes += data.byteLength;
        if (bytes > 200 * 1024 * 1024) throw new Error('Los soportes superan 200 MB. Filtra los abonos y exporta en varios paquetes.');
        zip.file(attachmentPath(payment, attachment), data);
        downloaded++;
        if (onProgress) onProgress({ downloaded, total });
      }
    }
    const ready = payments.filter(payment => payment.status === 'identified' && payment.attachments?.length).length;
    const totalAmount = payments.reduce((sum, payment) => sum + Math.round(Number(payment.amount || 0) * 100), 0) / 100;
    zip.file('LEEME.txt', [
      'JAC MUSIC · RELACIÓN DE ABONOS', `Exportado: ${new Date().toISOString()}`,
      `Abonos incluidos: ${payments.length}`, `Valor total COP: ${totalAmount}`, `Listos para contabilidad: ${ready}`, `Comprobantes incluidos: ${downloaded}`, '',
      'relacion.csv incluye datos originales y conciliación. Ábrelo en Excel como CSV UTF-8, delimitador punto y coma.',
      'Para conservar ceros iniciales de NIT, referencias y documentos, importa esas columnas como texto.',
      'Los comprobantes están organizados por ID de abono en la carpeta soportes. La columna Soportes indica la ruta de cada archivo.',
      'Identificado significa que el usuario asignó un show y un empresario. Listo para contabilidad exige además al menos un comprobante.',
      'Los campos originales de factura y recibo son referencias importadas; este paquete no emite facturas ni certifica validación contable.',
      'Descargar este paquete no lo envía a contabilidad ni marca los abonos como entregados.'
    ].join('\r\n'));
    const blob = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE', compressionOptions: { level: 3 } });
    checkAccess();
    downloadBlob(blob, `${name}.zip`);
    return { payments: payments.length, files: downloaded };
  }

  globalThis.FileTools = Object.freeze({ parseXlsx, parseCsv, normalizeDate, normalizeAmount, normalize, exportPackage, csvForPayments, safeCsvValue });
})();
