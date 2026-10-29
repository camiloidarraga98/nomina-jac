'use client';
import {useState} from 'react';
import {Plus,Pencil,Trash2} from 'lucide-react';
import {Input} from '@/components/ui/input';
import {Button} from '@/components/ui/button';
import {Select,SelectContent,SelectItem,SelectTrigger,SelectValue} from '@/components/ui/select';
import {Table,TableBody,TableCell,TableHead,TableHeader,TableRow} from '@/components/ui/table';
import CopInput from './cop-input';
import {money,showExpenseNames,type CamiloCommission,type ShowExpense,type Period} from '@/lib/payroll';

function Pick({label,value,onChange,options}:{label:string;value:string;onChange:(s:string)=>void;options:{value:string;label:string}[]}){return <div className="field"><span className="field-label">{label}</span><Select value={value} onValueChange={onChange}><SelectTrigger aria-label={label}><SelectValue/></SelectTrigger><SelectContent>{options.map(x=><SelectItem key={x.value} value={x.value}>{x.label}</SelectItem>)}</SelectContent></Select></div>;}
export function ShowExpenseForm({value,period,busy,onSave}:{value?:ShowExpense;period:Period;busy:boolean;onSave:(e:ShowExpense)=>Promise<void>}){
 const [expense,set]=useState<ShowExpense>(()=>value?structuredClone(value):{id:crypto.randomUUID(),showId:period.shows[0]?.id||'',date:period.shows[0]?.date||period.start,category:'tiquetes',concept:'',amount:0,note:''}),[error,setError]=useState('');
 return <form className="editor" onSubmit={e=>{e.preventDefault();if(!expense.showId||!expense.concept.trim()||expense.amount<=0){setError('Selecciona un show, escribe el concepto e introduce un valor mayor que cero.');return;}void onSave(expense);}}>
  {error&&<p className="message error" role="alert">{error}</p>}
  <Pick label="Show del gasto" value={expense.showId} onChange={showId=>set({...expense,showId})} options={period.shows.map(s=>({value:s.id,label:s.name+' · '+s.date+(s.promotional?' · Promocional':'')}))}/>
  <div className="form-grid"><Pick label="Tipo de gasto" value={expense.category} onChange={category=>set({...expense,category:category as ShowExpense['category']})} options={Object.entries(showExpenseNames).map(([value,label])=>({value,label}))}/><label className="field"><span className="field-label">Fecha del gasto</span><Input aria-label="Fecha del gasto" type="date" required value={expense.date} onChange={e=>set({...expense,date:e.target.value})}/></label></div>
  <label className="field"><span className="field-label">Concepto del gasto</span><Input aria-label="Concepto del gasto" value={expense.concept} required maxLength={180} onChange={e=>set({...expense,concept:e.target.value})}/></label>
  <div className="field"><span className="field-label">Valor del gasto (COP)</span><CopInput label="Valor del gasto (COP)" value={expense.amount} onChange={amount=>set({...expense,amount})}/></div>
  <label className="field"><span className="field-label">Observación opcional</span><Input aria-label="Observación del gasto" value={expense.note} maxLength={500} onChange={e=>set({...expense,note:e.target.value})}/></label>
  <p className="muted">Registra cada costo una sola vez. Este gasto sirve para el costo del show y la comisión; no genera un pago ni duplica los comprobantes de Gastos de viaje.</p>
  <Button type="submit" className="primary" disabled={busy}>{busy?'Guardando…':'Guardar gasto'}</Button>
 </form>;
}
export function ShowExpensesPanel({period,readOnly,blocked,onAdd,onEdit,onDelete}:{period:Period;readOnly:boolean;blocked:boolean;onAdd:()=>void;onEdit:(e:ShowExpense)=>void;onDelete:(id:string)=>void}){
 const [show,setShow]=useState('all'),expenses=(period.showExpenses||[]).filter(e=>show==='all'||e.showId===show);
 return <section className="panel"><div className="panel-title"><h2>Gastos de los shows</h2>{!readOnly&&<Button className="primary" disabled={blocked||!period.shows.length} onClick={onAdd}><Plus/>Agregar gasto</Button>}</div>
  <div className="panel-note"><Pick label="Filtrar gastos por show" value={show} onChange={setShow} options={[{value:'all',label:'Todos los shows'},...period.shows.map(s=>({value:s.id,label:s.name+' · '+s.date}))]}/></div>
  {!period.shows.length?<p className="panel-note">Agrega un show antes de registrar sus gastos.</p>:!expenses.length?<p className="panel-note">No hay gastos registrados para esta selección.</p>:<Table><TableHeader><TableRow><TableHead>Show y gasto</TableHead><TableHead>Tipo y fecha</TableHead><TableHead className="numeric">Valor</TableHead><TableHead/></TableRow></TableHeader><TableBody>{expenses.map(e=><TableRow key={e.id}><TableCell><strong>{e.concept}</strong><small>{period.shows.find(s=>s.id===e.showId)?.name}{e.note?' · '+e.note:''}</small></TableCell><TableCell>{showExpenseNames[e.category]}<small>{e.date}</small></TableCell><TableCell className="numeric">{money(e.amount)}</TableCell><TableCell>{!readOnly&&<div className="icon-actions"><Button aria-label={'Editar gasto '+e.concept} variant="ghost" size="icon" disabled={blocked} onClick={()=>onEdit(e)}><Pencil/></Button><Button aria-label={'Eliminar gasto '+e.concept} variant="ghost" size="icon" disabled={blocked} onClick={()=>onDelete(e.id)}><Trash2/></Button></div>}</TableCell></TableRow>)}</TableBody></Table>}
  <div className="panel-note"><strong>Total de gastos de esta selección: {money(expenses.reduce((v,e)=>v+e.amount,0))}</strong></div>
 </section>;
}
export default function CommissionPanel({value}:{value?:CamiloCommission}){
 if(!value)return <section className="panel"><div className="panel-title"><h2>Comisión de Camilo</h2></div><p className="panel-note">Este cierre histórico no tiene cálculo de comisión guardado. Sus pagos se conservan.</p></section>;
 return <section className="panel commission-panel"><div className="panel-title"><h2>Comisión de Camilo · 5%</h2></div><div className="rules-grid"><div><small>Ventas de todos los shows</small><strong>{money(value.sales)}</strong></div><div><small>Costos descontados</small><strong>{money(value.costs)}</strong><p>Honorarios brutos, kilómetros y gastos de shows no promocionales.</p></div><div><small>Costos promocionales excluidos</small><strong>{money(value.promotionalCosts)}</strong></div><div><small>Base de comisión</small><strong>{money(value.base)}</strong>{value.balance<0&&<p>Los costos superan las ventas. La comisión queda en cero, sin saldo al próximo corte.</p>}</div></div>
  {!!value.issues.length&&<div className="panel-note message error">{value.issues.map(issue=><p key={issue}>{issue}</p>)}</div>}
  <div className="inline-total"><span>Comisión para revisión</span><strong>{value.amount===null?'Pendiente de revisión':money(value.amount)}</strong></div><p className="panel-note">Base × 5%. Se suma en una línea independiente al total general de nómina. Excluye salarios, honorarios fijos, novedades, reintegros y recorridos extra; los gastos de esta pestaña se registran por separado.</p>
  {value.unlinkedKilometers>0&&<p className="panel-note">Kilómetros anteriores sin show identificado, no descontados: {money(value.unlinkedKilometers)}. Revisa su vinculación si corresponden a un show.</p>}
  <details className="show-cost-details"><summary>Costos y resultado por show</summary><Table><TableHeader><TableRow><TableHead>Show</TableHead><TableHead className="numeric">Ventas</TableHead><TableHead className="numeric">Músicos</TableHead><TableHead className="numeric">Técnica</TableHead><TableHead className="numeric">Conductores / km</TableHead><TableHead className="numeric">Gastos</TableHead><TableHead className="numeric">Costo total</TableHead><TableHead className="numeric">Resultado</TableHead><TableHead className="numeric">Costo descontado</TableHead></TableRow></TableHeader><TableBody>{value.shows.map(s=><TableRow key={s.id}><TableCell><strong>{s.name}</strong><small>{s.date}{s.promotional?' · Promocional':''}</small></TableCell>{[s.sale,s.musicians,s.technical,s.drivers,s.expenses,s.cost,s.sale-s.cost,s.deductible].map((n,i)=><TableCell className="numeric" key={i}>{money(n)}</TableCell>)}</TableRow>)}</TableBody></Table></details>
 </section>;
}
