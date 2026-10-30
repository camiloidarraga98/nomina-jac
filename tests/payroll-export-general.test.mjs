import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {unzipSync,strFromU8} from 'fflate';
import {getDocument} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {mkdir,writeFile} from 'node:fs/promises';
const result=await build({stdin:{contents:"export * from './lib/payroll';export * from './lib/payroll-seed';export * from './lib/payroll-export';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const m=await import('data:text/javascript;base64,'+Buffer.from(result.outputFiles[0].contents).toString('base64'));
function fixture(){const state=m.initialPayroll(),p=state.periods[0];state.employees.forEach(e=>e.active=false);const e=state.employees.find(e=>e.category==='musicos');e.active=true;e.name='Persona ficticia';e.email='ficticio@example.invalid';e.showRate=750000;e.fixedService=0;e.salary=0;e.withholding=.05;e.ica=0;
 p.shows=[{id:'promo',date:p.start,name:'Promocional ficticio',sale:2000000,promotional:true,halfPay:true,participants:[{employeeId:e.id,amount:750000}]}];
 p.snapshot={...m.calculate(state,p),employees:structuredClone(state.employees),closedAt:'2026-10-15T20:00:00Z',closedBy:'ficticio@example.invalid'};p.status='cerrada';return {p,e};}
async function pdfText(bytes){const task=getDocument({data:Uint8Array.from(bytes),isEvalSupported:false,disableFontFace:true,useSystemFonts:false});try{const doc=await task.promise;let text='';for(let n=1;n<=doc.numPages;n++)text+=' '+(await (await doc.getPage(n)).getTextContent()).items.map(x=>x.str??'').join(' ');return text.replace(/\s+/g,' ');}finally{await task.destroy();}}
test('preliquidación PDF y Excel conserva quincena editable, importes y marca de revisión; cambios actualizan el reporte',async()=>{
 const {p,e}=fixture(),state={...m.initialPayroll(),employees:p.snapshot.employees,settings:p.snapshot.settings,periods:[p]};
 p.status='abierta';delete p.snapshot;
 const before=structuredClone(state),{period,review}=m.payrollReview(state,p,12,'2026-10-30T16:00:00Z');
 const pdf=await m.payrollPdf(period,undefined,false,review),text=await pdfText(pdf),xlsx=m.payrollXlsx(period,review),files=unzipSync(xlsx),sheet=strFromU8(files['xl/worksheets/sheet1.xml']);
 assert.match(text,/Preliquidación de nómina/);assert.match(text,/PRELIQUIDACIÓN · PARA REVISIÓN/);assert.match(text,/Versión 12/);assert.match(text,/375\.000,00/);assert.match(text,/18\.750,00/);assert.match(text,/356\.250,00/);assert.match(text,/456\.250,00/);
 assert.doesNotMatch(text,/Cierre:|Cerrada por|Desprendible de pago/);assert.match(sheet,/PRELIQUIDACIÓN/);assert.match(sheet,/<f>H8\+H7<\/f><v>456250<\/v>/);assert.match(strFromU8(files['xl/worksheets/sheet8.xml']),/Versión/);
 assert.deepEqual(state,before);assert.equal(p.status,'abierta');assert.equal(p.snapshot,undefined);
 p.shows[0].participants[0].amount=900000;const next=m.payrollReview(state,p,13);assert.equal(next.review.calculation.rows.find(r=>r.employeeId===e.id).net,427500);
 await assert.rejects(()=>m.payrollPdf(period,e.id,false,review),/no genera desprendibles/);
 await mkdir('work/local/payroll-preliquidation',{recursive:true});await Promise.all([writeFile('work/local/payroll-preliquidation/preliquidacion.pdf',pdf),writeFile('work/local/payroll-preliquidation/preliquidacion.xlsx',xlsx)]);
});
test('preliquidación muestra pendientes y usa condiciones históricas de corrección sin cambiar cierres anteriores',async()=>{
 const {p}=fixture(),snapshot=structuredClone(p.snapshot),state={...m.initialPayroll(),employees:p.snapshot.employees,settings:p.snapshot.settings,periods:[p]};
 assert.throws(()=>m.payrollReview(state,p,1),/quincena abierta/);
 p.status='abierta';delete p.snapshot;p.revisions=[snapshot];p.calculationBase={employees:structuredClone(state.employees),settings:structuredClone(state.settings)};
 state.employees.forEach(e=>{e.active=false;e.showRate=999999;});p.movements=[{id:'deduction',employeeId:p.shows[0].participants[0].employeeId,concept:'Deducción ficticia',kind:'descuento',amount:500000,quantity:1,note:''}];
 const before=structuredClone(state),{period,review}=m.payrollReview(state,p,14),text=await pdfText(await m.payrollPdf(period,undefined,false,review));
 assert.ok(review.issues.some(i=>i.includes('negativo')));assert.match(text,/PENDIENTES PARA REVISAR/);assert.match(text,/neto es negativo/);assert.deepEqual(state,before);assert.deepEqual(p.revisions,[snapshot]);
});
test('resumen PDF/Excel incluye a Camilo en la tabla y suma su comisión una sola vez',async()=>{
 const {p,e}=fixture(),before=structuredClone(p),general=m.payrollGeneral(p.snapshot);assert.equal(general.team,356250);assert.equal(general.total,456250);
 const pdf=await m.payrollPdf(p),text=await pdfText(pdf);assert.match(text,/TOTAL GENERAL DE NÓMINA/);assert.match(text,/Camilo Idarraga.*Comisión del 5%/);assert.match(text,/456\.250,00/);assert.match(text,/356\.250,00/);assert.match(text,/100\.000,00/);
 const xlsx=m.payrollXlsx(p),files=unzipSync(xlsx),summary=strFromU8(files['xl/worksheets/sheet1.xml']),shows=strFromU8(files['xl/worksheets/sheet3.xml']);
 assert.match(summary,/TOTAL EQUIPO/);assert.match(summary,/Camilo Idarraga.*Comisión del 5%/);assert.match(summary,/<f>H8\+H7<\/f><v>456250<\/v>/);assert.match(shows,/<v>750000<\/v>/);assert.match(shows,/50%/);assert.match(shows,/<f>ROUND\(E6\*0.5,2\)<\/f><v>375000<\/v>/);
 const slip=await pdfText(await m.payrollPdf(p,e.id));assert.match(slip,/375\.000,00/);assert.match(slip,/356\.250,00/);assert.doesNotMatch(slip,/comisión|456\.250,00/);
 assert.equal((text.match(/Camilo Idarraga/g)||[]).length,1);assert.ok(text.indexOf('Camilo Idarraga')<text.indexOf('NETO DEL EQUIPO'));
 assert.equal((summary.match(/Camilo Idarraga/g)||[]).length,1);assert.ok(summary.indexOf('Camilo Idarraga')<summary.indexOf('TOTAL EQUIPO'));
 assert.match(summary,/<f>SUM\(H6:H6\)<\/f><v>356250<\/v>/);assert.match(summary,/<autoFilter ref="A5:H7"/);
 assert.doesNotMatch(slip,/Camilo Idarraga/);
 assert.deepEqual(p,before);await mkdir('work/local/payroll-promotional',{recursive:true});await Promise.all([writeFile('work/local/payroll-promotional/resumen.pdf',pdf),writeFile('work/local/payroll-promotional/resumen.xlsx',xlsx)]);
});
test('cierres sin comisión o con comisión pendiente conservan total del equipo y no inventan un total general',async()=>{
 for(const mode of ['missing','pending']){const {p}=fixture();if(mode==='missing')delete p.snapshot.camiloCommission;else p.snapshot.camiloCommission.amount=null;
  const before=structuredClone(p),text=await pdfText(await m.payrollPdf(p)),sheet=strFromU8(unzipSync(m.payrollXlsx(p))['xl/worksheets/sheet1.xml']);
  assert.match(text,/Pendiente de revisión/);assert.match(text,/356\.250,00/);assert.doesNotMatch(text,/456\.250,00/);assert.match(sheet,/Pendiente de revisión/);assert.doesNotMatch(sheet,/<f>H8\+H7<\/f>/);assert.deepEqual(p,before);
 }
});
test('el general conserva la comisión cuando no hay participantes por pagar y Excel no suma un rango vacío invertido',async()=>{
 const {p}=fixture(),settings=p.snapshot.settings,employees=p.snapshot.employees.map(e=>({...e,active:false}));
 p.status='abierta';delete p.snapshot;p.shows[0].participants=[];
 p.snapshot={...m.calculate({settings,employees,concepts:[],periods:[p]},p),employees,closedAt:'2026-10-15T20:00:00Z',closedBy:'ficticio@example.invalid'};p.status='cerrada';
 assert.deepEqual(m.payrollGeneral(p.snapshot),{team:0,camilo:100000,total:100000,gross:100000});
 const sheet=strFromU8(unzipSync(m.payrollXlsx(p))['xl/worksheets/sheet1.xml']);assert.doesNotMatch(sheet,/SUM\([A-H]6:[A-H]5\)/);assert.match(sheet,/<f>H7\+H6<\/f><v>100000<\/v>/);
 const text=await pdfText(await m.payrollPdf(p));assert.match(text,/100\.000,00/);assert.match(text,/Camilo Idarraga.*Comisión del 5%/);
});
