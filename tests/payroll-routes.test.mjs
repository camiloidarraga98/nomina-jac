import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {unzipSync,strFromU8} from 'fflate';
import {getDocument} from 'pdfjs-dist/legacy/build/pdf.mjs';
const bundle=await build({stdin:{contents:"export * from './lib/payroll';export * from './lib/payroll-routes';export * from './lib/payroll-seed';export * from './lib/payroll-schema';export * from './lib/payroll-mobile';export * from './lib/payroll-policy';export * from './lib/payroll-export';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const m=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
function fixture(){const state=m.initialPayroll();state.settings.company='JAC ficticio';state.settings.nit='TEST';state.employees.forEach(e=>{e.active=false;e.name='Persona ficticia '+e.id;e.document='TEST-'+e.id;e.email=e.id+'@example.invalid'});const andres=state.employees.find(e=>e.id==='emp-18'),mariano=state.employees.find(e=>e.id==='emp-19');andres.active=mariano.active=true;andres.name='Andrés ficticio';mariano.name='Mariano ficticio';const p=state.periods[0];return {state,p,andres,mariano};}
const extra=p=>({id:'route-andres',kind:'extra',date:p.start,name:'Pereira–Medellín · actividad externa ficticia',km:100,drivers:[{employeeId:'emp-18',rate:1250}]});
test('Andrés es elegible por su identidad, con tarifa base de Mariano, sin cambiar su categoría ni seleccionarlo automáticamente',()=>{
 const {state,p,andres,mariano}=fixture(),before=structuredClone(state),options=m.routeParticipantOptions(state.employees),option=options.find(e=>e.employeeId===andres.id);
 assert.equal(option.rate,1250);assert.equal(option.selectedByDefault,false);assert.equal(option.selectAloneLabel,'Solo Andrés Rey');assert.deepEqual(state,before);assert.equal(andres.category,'tecnica');assert.equal(andres.kmRate,0);
 mariano.kmRate=1500;assert.equal(m.routeParticipantOptions(state.employees).find(e=>e.employeeId===andres.id).rate,1500);
 const native=m.mobilePeriod(state,p,1);assert.ok(!native.editing.drivers.some(e=>e.employeeId===andres.id));assert.ok(native.editing.routeParticipants.some(e=>e.employeeId===andres.id));assert.equal(p.routes.length,0);assert.ok(!m.calculate(state,p).rows.some(r=>r.employeeId===andres.id));
 p.shows=[{id:'new-show',date:p.start,name:'Show nuevo ficticio',sale:0,participants:[]}];const template=m.mobilePeriod(state,p,2).editing.showRoutes[0];assert.deepEqual(template.drivers,[{employeeId:mariano.id,rate:1500}]);assert.equal(p.routes.length,0,'Consultar una plantilla no registra recorridos ni añade a Andrés');
});
test('ruta independiente paga únicamente a Andrés y usa sus retenciones sin alterar el salario de Mariano',()=>{
 const {state,p,andres,mariano}=fixture(),before=m.calculate(state,p);p.routes=[extra(p)];assert.ok(m.stateSchema.safeParse(state).success);
 const result=m.calculate(state,p),row=result.rows.find(r=>r.employeeId===andres.id);assert.equal(row.category,'tecnica');assert.equal(row.gross,125000);assert.equal(row.deductions,8750);assert.equal(row.net,116250);assert.equal(row.items[0].rate,1250);assert.match(row.items[0].concept,/Pereira–Medellín/);
 assert.deepEqual(result.rows.filter(r=>r.employeeId===mariano.id),before.rows.filter(r=>r.employeeId===mariano.id));assert.equal(result.camiloCommission.costs,0);assert.equal(result.camiloCommission.unlinkedKilometers,0);assert.deepEqual(m.closeIssues(state,p),[]);
});
test('ruta externa en fecha de show no se consolida, no duplica honorarios y no reduce la comisión del show',()=>{
 const {state,p,andres}=fixture();p.shows=[{id:'show',date:p.start,name:'Show ficticio',sale:2000000,participants:[{employeeId:andres.id,amount:600000}]}];p.routes=[extra(p)];
 const result=m.calculate(state,p),row=result.rows.find(r=>r.employeeId===andres.id);assert.equal(row.gross,725000);assert.equal(row.items.filter(i=>i.kind==='ingreso').length,2);assert.equal(result.camiloCommission.costs,600000);
 m.setShowRoute(p,{id:'shared',showId:'show',name:'',date:p.start,km:10,drivers:[{employeeId:'emp-19',rate:1250}]});assert.equal(p.routes.length,2);assert.ok(p.routes.some(r=>r.kind==='extra'));
 m.removeShow(p,'show');assert.deepEqual(p.routes,[extra(p)]);assert.equal(m.calculate(state,p).rows.find(r=>r.employeeId===andres.id).gross,125000);
});
test('si se selecciona a Andrés para un show, sus kilómetros forman parte del costo sin cambiar sus honorarios técnicos',()=>{
 const {state,p,andres}=fixture();p.shows=[{id:'show',date:p.start,name:'Show ficticio',sale:2000000,participants:[{employeeId:andres.id,amount:600000}]}];m.setShowRoute(p,{id:'shared',showId:'show',date:p.start,name:'',km:100,drivers:[{employeeId:andres.id,rate:1250}]});
 assert.ok(m.stateSchema.safeParse(state).success);const result=m.calculate(state,p),cost=result.camiloCommission.shows[0];assert.equal(cost.technical,600000);assert.equal(cost.drivers,125000);assert.equal(cost.cost,725000);assert.equal(result.camiloCommission.amount,63750);
 const native=m.mobilePeriod(state,p,1);assert.deepEqual(native.editing.showRoutes[0].drivers,p.routes[0].drivers);
 p.shows[0].promotional=true;p.shows[0].halfPay=true;const promo=m.calculate(state,p);assert.equal(promo.rows.find(r=>r.employeeId===andres.id).gross,425000);assert.equal(promo.camiloCommission.shows[0].drivers,125000,'El porcentaje promocional no reduce los kilómetros de Andrés');assert.equal(promo.camiloCommission.promotionalCosts,425000);
});
test('validación exige una ruta descriptiva y participantes válidos; exclusión o inactividad retira la opción y bloquea el cierre',()=>{
 const {state,p,andres}=fixture();p.routes=[extra(p)];
 for(const change of [s=>s.periods[0].routes[0].name=' ',s=>s.periods[0].routes[0].drivers=[],s=>s.periods[0].routes[0].drivers.push({...s.periods[0].routes[0].drivers[0]}),s=>s.periods[0].routes[0].km=0,s=>s.periods[0].routes[0].drivers[0].employeeId='emp-1']){const next=structuredClone(state);change(next);assert.equal(m.stateSchema.safeParse(next).success,false);}
 p.excludedEmployees.push(andres.id);assert.ok(!m.routePayees(state.employees,p.excludedEmployees).some(e=>e.id===andres.id));assert.ok(m.closeIssues(state,p).some(x=>/excluida/.test(x)));
 p.excludedEmployees=[];andres.active=false;assert.ok(!m.routePayees(state.employees).some(e=>e.id===andres.id));assert.ok(m.closeIssues(state,p).some(x=>/inactiva/.test(x)));
});
test('tarifas guardadas y cierres conservan sus importes aunque cambie Mariano; reapertura conserva la base histórica',()=>{
 const {state,p,andres,mariano}=fixture();p.routes=[extra(p)];const original=m.calculate(state,p);p.snapshot={...original,employees:structuredClone(state.employees),closedAt:'2026-10-29T20:00:00Z',closedBy:'test@example.invalid'};p.status='cerrada';const frozen=structuredClone(p.snapshot);
 mariano.kmRate=2000;andres.withholding=.5;assert.deepEqual(m.calculate(state,p),frozen);m.reopenPeriod(p,'camilo@mac2you.co');assert.equal(m.calculate(state,p).total,original.total);assert.deepEqual(p.revisions,[frozen]);assert.equal(m.mobilePeriod(state,p,2).editing.routeParticipants.find(e=>e.employeeId===andres.id).rate,1250);assert.equal(p.routes[0].drivers[0].rate,1250);
});
test('Solo Andrés retira otros participantes y conserva su tarifa capturada aunque la nueva referencia haya cambiado',()=>{
 const stored=[{employeeId:'emp-18',rate:1250},{employeeId:'emp-19',rate:1500}],before=structuredClone(stored),person={id:'emp-18',kmRate:1500};
 assert.deepEqual(m.onlyRouteParticipant(stored,person),[{employeeId:'emp-18',rate:1250}]);assert.deepEqual(stored,before);
 assert.deepEqual(m.onlyRouteParticipant([],person),[{employeeId:'emp-18',rate:1500}]);
});
test('PDF individual y Excel incluyen la ruta pagada a Andrés, sus kilómetros y la tarifa capturada',async()=>{
 const {state,p,andres}=fixture();p.routes=[extra(p)];p.snapshot={...m.calculate(state,p),employees:structuredClone(state.employees),closedAt:'2026-10-29T20:00:00Z',closedBy:'test@example.invalid'};p.status='cerrada';
 const sheet=strFromU8(unzipSync(m.payrollXlsx(p))['xl/worksheets/sheet6.xml']);assert.match(sheet,/Andrés ficticio/);assert.match(sheet,/Pereira–Medellín/);assert.match(sheet,/<v>1250<\/v>/);assert.match(sheet,/<f>D6\*E6<\/f><v>125000<\/v>/);
 const task=getDocument({data:Uint8Array.from(await m.payrollPdf(p,andres.id)),isEvalSupported:false,disableFontFace:true,useSystemFonts:false});try{const pdf=await task.promise,text=(await (await pdf.getPage(1)).getTextContent()).items.map(x=>x.str??'').join(' ');assert.match(text,/Pereira-Medellín/);assert.match(text,/125\.000,00/);assert.match(text,/116\.250,00/);}finally{await task.destroy();}
});
