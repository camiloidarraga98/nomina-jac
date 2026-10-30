import {createDocumentPdf} from './document-pdf';
import {documentDate} from './document-brand';
import {categoryNames, payrollGeneral, periodLabel, type Period} from './payroll';
import type {PayrollReview} from './payroll-export';

const money = (value: number) => new Intl.NumberFormat('es-CO', {
  style: 'currency', currency: 'COP', minimumFractionDigits: 2, maximumFractionDigits: 2,
}).format(value);

export async function payrollPdf(period: Period, employeeId?: string, allSlips = false, review?: PayrollReview) {
  if (review && (employeeId || allSlips)) throw Error('La preliquidación no genera desprendibles.');
  const snapshot = review?.calculation ?? period.snapshot!;
  const isSlip = !!employeeId || allSlips;
  const title = isSlip ? 'Desprendible de pago' : review ? 'Preliquidación de nómina' : 'Resumen de nómina';
  const pdf = await createDocumentPdf({title, period: periodLabel(period), company: snapshot.company, nit: snapshot.nit,
    status: review ? 'PARA REVISIÓN · Versión ' + review.version : 'LIQUIDACIÓN DEFINITIVA',
    footer: review ? 'PRELIQUIDACIÓN · PARA REVISIÓN · Quincena abierta' : 'JAC MUSIC · ' + period.start + ' al ' + period.end});
  const generated = review ? 'Generada: ' + documentDate(review.generatedAt) + ' · Hora Colombia'
    : 'Cierre: ' + documentDate(period.snapshot!.closedAt) + ' · Hora Colombia';

  if (!isSlip) {
    const general = payrollGeneral(snapshot);
    pdf.addPage(generated);
    pdf.total('TOTAL GENERAL DE NÓMINA', general.total === null ? 'Pendiente de revisión' : money(general.total), 'Neto del equipo + comisión de Camilo');
    pdf.gap(17);
    for (const [label, value] of [['Devengado del equipo', snapshot.gross], ['Adiciones y reintegros', snapshot.reimbursements],
      ['Descuentos', snapshot.deductions], ['Ventas de shows', snapshot.sale]] as [string, number][]) pdf.keyValue(label, money(value));
    pdf.gap(14);
    const columns = review ? [{label: 'PERSONA', width: 180}, {label: 'DEVENGADO', width: 84, align: 'right' as const},
      {label: 'ADICIONES', width: 84, align: 'right' as const}, {label: 'DESCUENTOS', width: 84, align: 'right' as const},
      {label: 'NETO', width: 84, align: 'right' as const}]
      : [{label: 'PERSONA', width: 260}, {label: 'GRUPO', width: 126}, {label: 'NETO A PAGAR', width: 130, align: 'right' as const}];
    pdf.table(columns, snapshot.rows.map(row => review
      ? [{text: row.name, detail: categoryNames[row.category]}, {text: money(row.gross)}, {text: money(row.reimbursements)}, {text: money(row.deductions)}, {text: money(row.net), bold: true}]
      : [{text: row.name}, {text: categoryNames[row.category], muted: true}, {text: money(row.net), bold: true}]), 'Detalle de pagos · Continuación');
    // Keep the reconciliation together. If needed it starts on a fresh page.
    pdf.ensure(185, 'Consolidado de nómina'); pdf.gap(18);
    pdf.keyValue('NETO DEL EQUIPO', money(general.team), true);
    pdf.keyValue('Camilo · comisión del 5%', general.camilo === null ? 'Pendiente de revisión' : money(general.camilo));
    pdf.gap(9);
    pdf.total('TOTAL GENERAL', general.total === null ? 'Pendiente de revisión' : money(general.total));
    pdf.gap(13);
    pdf.paragraph(review ? 'Para revisión. Quincena abierta; valores sujetos a cambios.' : 'Cerrada por ' + period.snapshot!.closedBy, {size: 8, muted: true});
    if (review?.issues.length) {
      pdf.gap(23); pdf.section('PENDIENTES PARA REVISAR', 35);
      review.issues.forEach((issue, index) => { pdf.paragraph(`${index + 1}. ${issue}`, {size: 9}); pdf.gap(10); });
    }
  } else {
    const ids = employeeId ? [employeeId] : [...new Set(snapshot.rows.map(row => row.employeeId))];
    if (!ids.length) { pdf.addPage(); pdf.paragraph('No hay desprendibles en esta quincena.'); }
    for (const id of ids) {
      const rows = snapshot.rows.filter(row => row.employeeId === id);
      if (!rows.length) continue;
      const person = rows[0];
      pdf.addPage();
      pdf.paragraph(person.name, {size: 13, bold: true}); pdf.gap(6);
      pdf.paragraph('Documento: ' + (person.document || 'Sin registrar'), {size: 9, muted: true});
      pdf.paragraph(person.role, {size: 9, muted: true}); pdf.gap(20);
      for (const row of rows) {
        pdf.table([{label: 'CONCEPTO', width: 326}, {label: 'CANT.', width: 58, align: 'right'}, {label: 'VALOR', width: 132, align: 'right'}],
          row.items.map(item => [{text: item.concept, detail: item.reference || undefined}, {text: String(item.quantity)},
            {text: (item.kind === 'deduccion' ? '- ' : '') + money(item.amount), bold: item.kind !== 'deduccion'}]), person.name + ' · ' + categoryNames[row.category] + ' · Continuación', categoryNames[row.category].toUpperCase());
        pdf.gap(12); pdf.keyValue('Neto ' + categoryNames[row.category], money(row.net), true); pdf.gap(14);
      }
      pdf.ensure(147, person.name + ' · Total del desprendible');
      pdf.total('TOTAL A PAGAR', money(rows.reduce((value, row) => value + row.net, 0)));
      pdf.gap(16); pdf.paragraph(generated, {size: 8, muted: true});
      pdf.paragraph('Responsable: ' + period.snapshot!.closedBy, {size: 8, muted: true});
      if (period.revisions?.length) pdf.paragraph('Versión del cierre: ' + (period.revisions.length + 1), {size: 8, muted: true});
    }
  }
  return pdf.finish();
}
