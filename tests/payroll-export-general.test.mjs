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
test('resumen PDF/Excel suma Camilo aparte y muestra honorarios efectivos conservando la tarifa completa',async()=>{
 const {p,e}=fixture(),before=structuredClone(p),general=m.payrollGeneral(p.snapshot);assert.equal(general.team,356250);assert.equal(general.total,456250);
 const pdf=await m.payrollPdf(p),text=await pdfText(pdf);assert.match(text,/TOTAL GENERAL DE NÓMINA/);assert.match(text,/Camilo · comisión del 5%/);assert.match(text,/456\.250,00/);assert.match(text,/356\.250,00/);assert.match(text,/100\.000,00/);
 const xlsx=m.payrollXlsx(p),files=unzipSync(xlsx),summary=strFromU8(files['xl/worksheets/sheet1.xml']),shows=strFromU8(files['xl/worksheets/sheet3.xml']);
 assert.match(summary,/TOTAL EQUIPO/);assert.match(summary,/Camilo · comisión del 5%/);assert.match(summary,/<f>H6\+H7<\/f><v>456250<\/v>/);assert.match(shows,/<v>750000<\/v>/);assert.match(shows,/50%/);assert.match(shows,/<f>E2\*0.5<\/f><v>375000<\/v>/);
 const slip=await pdfText(await m.payrollPdf(p,e.id));assert.match(slip,/375\.000,00/);assert.match(slip,/356\.250,00/);assert.doesNotMatch(slip,/comisión|456\.250,00/);
 assert.deepEqual(p,before);await mkdir('work/local/payroll-promotional',{recursive:true});await Promise.all([writeFile('work/local/payroll-promotional/resumen.pdf',pdf),writeFile('work/local/payroll-promotional/resumen.xlsx',xlsx)]);
});
test('cierres sin comisión o con comisión pendiente conservan total del equipo y no inventan un total general',async()=>{
 for(const mode of ['missing','pending']){const {p}=fixture();if(mode==='missing')delete p.snapshot.camiloCommission;else p.snapshot.camiloCommission.amount=null;
  const before=structuredClone(p),text=await pdfText(await m.payrollPdf(p)),sheet=strFromU8(unzipSync(m.payrollXlsx(p))['xl/worksheets/sheet1.xml']);
  assert.match(text,/Pendiente de revisión/);assert.match(text,/356\.250,00/);assert.doesNotMatch(text,/456\.250,00/);assert.match(sheet,/Pendiente de revisión/);assert.doesNotMatch(sheet,/<f>H6\+H7<\/f>/);assert.deepEqual(p,before);
 }
});
