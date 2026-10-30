import {categoryNames, periodLabel, type Period} from '@/lib/payroll';
import {documentBrand, documentDate} from '@/lib/document-brand';

const money = (value: number) => '$ ' + value.toLocaleString('es-CO', {minimumFractionDigits: 2, maximumFractionDigits: 2});

export default function SlipDocument({period, employee}: {period: Period; employee: string}) {
  const snapshot = period.snapshot!, rows = snapshot.rows.filter(row => row.employeeId === employee), person = rows[0];
  return <article className="jac-letterhead">
    <header className="print-letterhead">
      <img src={documentBrand.logoPath} width="116" height="45" alt="JAC Music"/>
      <div><h1>Desprendible de pago</h1><p>{periodLabel(period)}</p><small>LIQUIDACIÓN DEFINITIVA</small></div>
    </header>
    <p className="print-company">{snapshot.company} · NIT {snapshot.nit}</p>
    <section className="print-person"><h2>{person.name}</h2><p>Documento: {person.document || 'Sin registrar'}<br/>{person.role}</p></section>
    {rows.map(row => <section key={row.category}>
      <h3>{categoryNames[row.category]}</h3>
      <table><colgroup><col style={{width: '63%'}}/><col style={{width: '11%'}}/><col style={{width: '26%'}}/></colgroup><thead><tr><th>Concepto</th><th>Cant.</th><th>Valor</th></tr></thead>
        <tbody>{row.items.map((item, index) => <tr key={index}><td>{item.concept}{item.reference && <small>{item.reference}</small>}</td><td>{item.quantity}</td><td>{item.kind === 'deduccion' ? '− ' : ''}{money(item.amount)}</td></tr>)}</tbody>
      </table>
      <p className="print-subtotal">Neto {categoryNames[row.category]} <strong>{money(row.net)}</strong></p>
    </section>)}
    <div className="print-total"><span>TOTAL A PAGAR</span><strong>{money(rows.reduce((value, row) => value + row.net, 0))}</strong></div>
    <div className="print-closure">Cierre: {documentDate(snapshot.closedAt)} · Hora Colombia<br/>Responsable: {snapshot.closedBy}{period.revisions?.length ? <><br/>Versión del cierre: {period.revisions.length + 1}</> : null}</div>
    <footer><div>E-mail: {documentBrand.email}<br/>Tel: {documentBrand.phone}</div><div>{documentBrand.address}<br/>{documentBrand.social}</div></footer>
  </article>;
}
