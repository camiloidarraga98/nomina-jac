import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const bundle=await build({entryPoints:['lib/cop-input.ts'],bundle:true,platform:'node',format:'esm',write:false});
const {copText,editCop,copPaste}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].contents).toString('base64'));
test('editar venta: borrar el cero deja vacío y escribir millones no conserva ceros iniciales',()=>{
 assert.deepEqual(editCop(''),{text:'',value:0,caret:0});
 assert.equal(editCop('014000000').text,'14.000.000');
 assert.equal(editCop('014000000').value,14000000);
 let text='';for(const digit of '14000000')text=editCop(text+digit).text;
 assert.equal(text,'14.000.000');assert.equal(editCop(text).value,14000000);
 assert.equal(copText(750000),'750.000');assert.equal(copText(999),'999');
});
test('tarifas conservan centavos con coma decimal y guardan números en pesos',()=>{
 assert.equal(copText(750000.5),'750.000,5');
 assert.equal(editCop('750.000,50').value,750000.5);
 assert.equal(editCop('0,01').value,0.01);assert.equal(editCop(',50').text,'0,50');
 assert.equal(editCop('14.000.000,').text,'14.000.000,');assert.equal(editCop('14.000.000,').value,14000000);
 assert.equal(editCop('12,345'),null);assert.equal(editCop('-500'),null);assert.equal(editCop('1e6'),null);
});
test('pegar COP agrupados o decimales no cambia la magnitud y rechaza texto ambiguo',()=>{
 for(const source of ['14.000.000','$ 14.000.000','COP 14000000'])assert.equal(editCop(copPaste(source)).value,14000000);
 assert.equal(editCop(copPaste('750.000,50 COP')).value,750000.5);
 assert.equal(editCop(copPaste('750000.50')).value,750000.5);
 for(const source of ['-14000','USD 14','1e6','1.40.000','14,000,000','un millón'])assert.equal(copPaste(source),null,source);
});
test('el cursor acompaña inserción y borrado entre miles, centavos y ceros iniciales',()=>{
 const middle=editCop('1.4500.000',4);assert.equal(middle.text,'14.500.000');assert.equal(middle.caret,4);
 const eraseSeparator=editCop('1400.000',1);assert.equal(eraseSeparator.text,'1.400.000');assert.equal(eraseSeparator.caret,1);
 assert.equal(editCop('014000000',9).caret,10);
 const cents=editCop('750.000,5',9);assert.equal(cents.caret,9);assert.equal(cents.value,750000.5);
});
