import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const result=await build({stdin:{contents:"export * from './lib/payroll';export * from './lib/payroll-seed';export * from './lib/payroll-schema';export * from './lib/payroll-policy';export * from './lib/payroll-mobile-edits';export * from './lib/payroll-permissions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const m=await import('data:text/javascript;base64,'+Buffer.from(result.outputFiles[0].contents).toString('base64'));
function fixture(){const template=m.initialPayroll().employees[0];const employee=(id,category,extra={})=>({...template,id,document:'TEST',name:'Persona ficticia '+id,email:id+'@example.invalid',category,active:true,deleted:false,showRate:0,kmRate:0,fixedService:0,salary:0,transport:0,nonSalary:0,withholding:.2,ica:.01,...extra});const p=m.newPeriod('2026-10-01','2026-10-15');p.id='period';const state={employees:[employee('music','musicos',{fixedService:1500000}),employee('tech','tecnica'),employee('driver','conductores',{salary:2000000,kmRate:1000}),employee('fixed','administracion',{salary:8000000})],settings:{company:'JAC Ficticio',nit:'TEST',hourDivisor:210,hourFactors:[.35,.9,1.25,1.25,1.75,2.15,2.65]},concepts:[],periods:[p]};return {state,p};}
const show=(id,sale,promotional=false)=>({id,name:'Show ficticio '+id,date:'2026-10-08',sale,promotional,participants:[{employeeId:'music',amount:750000},{employeeId:'tech',amount:250000}]});
const expense=(id,showId,amount)=>({id,showId,amount,concept:'Hotel ficticio',category:'hoteles',date:'2026-10-07',note:''});
test('comisión 5% usa honorarios brutos/km/gastos por show, excluye salarios, fijos, novedades y extras',()=>{
 const {state,p}=fixture();p.shows=[show('normal',10000000)];p.routes=[{id:'route',showId:'normal',name:p.shows[0].name,date:p.shows[0].date,km:100,drivers:[{employeeId:'driver',rate:1000}]},{id:'extra',kind:'extra',name:'Traslado ficticio',date:p.start,km:999,drivers:[{employeeId:'driver',rate:1000}]}];p.showExpenses=[expense('hotel','normal',300000),{...expense('ticket','normal',500000),category:'tiquetes'}];p.movements=[{id:'move',employeeId:'music',kind:'reintegro',concept:'Reintegro ficticio',quantity:1,amount:900000,note:''}];
 const out=m.calculate(state,p),c=out.camiloCommission;assert.equal(c.sales,10000000);assert.equal(c.costs,1900000);assert.equal(c.base,8100000);assert.equal(c.amount,405000);assert.equal(c.shows[0].expenses,800000);assert.equal(c.shows[0].drivers,100000);assert.equal(out.rows.some(r=>r.category==='comision'),false,'El cálculo no agrega un pago');assert.equal(c.shows[0].musicians,750000,'No descuenta retenciones al costo bruto');
 const before=structuredClone(out.rows);p.shows[0].promotional=true;const promotional=m.calculate(state,p);assert.deepEqual(promotional.rows,before,'Promocional conserva todos los pagos del equipo');assert.equal(promotional.camiloCommission.costs,0);assert.equal(promotional.camiloCommission.promotionalCosts,1900000);assert.equal(promotional.camiloCommission.amount,500000);
});
test('ventas promocionales siguen en total, solo sus costos se excluyen; negativo queda cero sin arrastre',()=>{
 const {state,p}=fixture();p.shows=[show('ordinary',2000000),show('promo',500000,true)];p.showExpenses=[expense('promo-hotel','promo',350000)];let c=m.calculate(state,p).camiloCommission;assert.equal(c.sales,2500000);assert.equal(c.costs,1000000);assert.equal(c.promotionalCosts,1350000);assert.equal(c.amount,75000);
 p.shows[0].sale=0;p.shows[1].sale=0;c=m.calculate(state,p).camiloCommission;assert.equal(c.balance,-1000000);assert.equal(c.amount,0);assert.equal(c.base,0);
 const future=m.newPeriod('2026-10-16','2026-10-31');future.shows=[{...show('next',1000000),date:future.start,participants:[]}];assert.equal(m.calculate(state,future).camiloCommission.amount,50000);
});
test('gastos requieren show existente, identificador único, fecha real y categoría válida; datos antiguos conservan compatibilidad',()=>{
 const {state,p}=fixture();p.shows=[show('one',10000000)];assert.ok(m.stateSchema.safeParse(state).success);p.showExpenses=[expense('hotel','one',300000)];assert.ok(m.stateSchema.safeParse(state).success);
 for(const change of [s=>s.periods[0].showExpenses[0].showId='missing',s=>s.periods[0].showExpenses.push({...s.periods[0].showExpenses[0]}),s=>s.periods[0].showExpenses[0].date='2026-02-30',s=>s.periods[0].showExpenses[0].category='salary',s=>s.periods[0].showExpenses[0].amount=-1,s=>s.periods[0].showExpenses[0].concept=' ',s=>s.periods[0].shows[0].promotional='true']){const next=structuredClone(state);change(next);assert.equal(m.stateSchema.safeParse(next).success,false);}
});
test('congela comisión/costos al cerrar y conserva revisión/condiciones cuando se reabre',()=>{
 const {state,p}=fixture();p.shows=[show('one',10000000)];p.showExpenses=[expense('hotel','one',300000)];p.snapshot={...m.calculate(state,p),employees:structuredClone(state.employees),closedAt:'2026-10-15T12:00:00Z',closedBy:'owner@example.invalid'};p.status='cerrada';const old=structuredClone(p.snapshot);state.employees.forEach(e=>{e.active=false;e.category='administracion';e.salary=99999999;});assert.deepEqual(m.calculate(state,p),old);
 m.reopenPeriod(p,'camilo@mac2you.co');assert.equal(m.calculate(state,p).camiloCommission.amount,old.camiloCommission.amount);p.showExpenses[0].amount+=100000;assert.equal(m.calculate(state,p).camiloCommission.amount,old.camiloCommission.amount-5000);assert.deepEqual(p.revisions[0],old);
 const legacy=structuredClone(old);delete legacy.camiloCommission;p.snapshot=legacy;p.status='cerrada';assert.deepEqual(m.calculate(state,p),legacy,'No recalcula cierres anteriores sin comisión guardada');
});
test('ediciones móviles conservan promocional omitido; CRUD de gastos y borrado relacionado no tocan otro show',()=>{
 const {state,p}=fixture();p.shows=[show('one',10000000,true),show('two',5000000)];p.showExpenses=[expense('first','one',300000),expense('second','two',400000)];const oldClient={...p.shows[0]};delete oldClient.promotional;
 const mobile=m.applyMobileEdit(state,{kind:'show',periodId:p.id,record:oldClient});assert.equal(mobile.periods[0].shows[0].promotional,true);
 const added=m.applyMobileEdit(mobile,{kind:'showExpense',periodId:p.id,record:expense('third','one',150000)});assert.equal(added.periods[0].showExpenses.length,3);assert.equal(m.calculate(added,added.periods[0]).camiloCommission.shows[0].expenses,450000);
 const removed=m.applyMobileEdit(added,{kind:'showExpense',periodId:p.id,id:'third'},true);assert.equal(removed.periods[0].showExpenses.length,2);m.removeShow(removed.periods[0],'one');assert.deepEqual(removed.periods[0].showExpenses.map(e=>e.id),['second']);assert.ok(m.stateSchema.safeParse(removed).success);
 const next=structuredClone(state);delete next.periods[0].shows[0].promotional;assert.match(m.validateSave(state,next,'owner@example.invalid'),/promocional/);const drop=structuredClone(state);delete drop.periods[0].showExpenses;assert.match(m.validateSave(state,drop,'owner@example.invalid'),/gastos/);
 assert.ok(m.savePermissionIssue(state,added,{isOwner:false,permissions:[],itinerariesOnly:false}));
});
test('kilómetros históricos se asignan una sola vez y coincidencias ambiguas requieren revisión',()=>{
 const {state,p}=fixture();p.shows=[show('one',5000000)];p.routes=[{id:'old',employeeId:'driver',date:p.shows[0].date,name:'Ruta anterior',km:100,rate:1000}];assert.equal(m.calculate(state,p).camiloCommission.shows[0].drivers,100000);
 p.shows.push({...show('two',5000000),name:p.shows[0].name});p.routes[0].name=p.shows[0].name;const c=m.calculate(state,p).camiloCommission;assert.equal(c.amount,null);assert.equal(c.issues.length,1);
 p.routes[0].date=p.start;const unlinked=m.calculate(state,p).camiloCommission;assert.equal(unlinked.unlinkedKilometers,100000);assert.equal(unlinked.shows.reduce((v,s)=>v+s.drivers,0),0);
});
