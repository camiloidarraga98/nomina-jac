import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';

const compiled=await build({entryPoints:['lib/boarding-wallet-details.ts'],bundle:true,platform:'node',format:'cjs',write:false});
const module={exports:{}};
new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),module,module.exports);
const {parseWalletBarcodeDetails:parse}=module.exports;

function leg({origin='BOG',destination='MDE',seat='012A',variable='',day='100',carrier='XX ',flight='00123'}={}) {
 return 'DEMO123'+origin+destination+carrier+flight+day+'Y'+seat+'00001'+'1'+variable.length.toString(16).toUpperCase().padStart(2,'0')+variable;
}
function barcode(legs=[leg()],name='TRAVELLER/FIXTURE',tail='') {
 return 'M'+legs.length+name.padEnd(20,' ').slice(0,20)+'E'+legs.join('')+tail;
}

test('BCBP mandatory fields preserve the source and expose only passenger, route and assigned seat',()=>{
 const source=barcode(),copy=source.slice();
 assert.equal(source.length,60);
 assert.deepEqual(parse(source),{passenger:'FIXTURE TRAVELLER',legs:[{origin:'BOG',destination:'MDE',seat:'12A'}]});
 assert.equal(source,copy);
 assert.deepEqual(parse(barcode([leg({seat:'0007'})])),{passenger:'FIXTURE TRAVELLER',legs:[{origin:'BOG',destination:'MDE',seat:'7'}]});
 assert.deepEqual(parse(barcode([leg()],"O'NEILL/TEST-PERSON"))?.passenger,"TEST-PERSON O'NEILL");
 assert.deepEqual(Object.keys(parse(source)).sort(),['legs','passenger']);
 assert.deepEqual(Object.keys(parse(source).legs[0]).sort(),['destination','origin','seat']);
});

test('BCBP multiple legs skip each exact variable-length block and keep routes and seats separate',()=>{
 const source=barcode([leg({variable:'>1SYNTHETIC00000000'}),leg({origin:'MDE',destination:'CTG',seat:'002F',variable:'ABCD'})]);
 assert.deepEqual(parse(source),{passenger:'FIXTURE TRAVELLER',legs:[{origin:'BOG',destination:'MDE',seat:'12A'},{origin:'MDE',destination:'CTG',seat:'2F'}]});
 const four=barcode([leg(),leg(),leg(),leg()]);assert.equal(parse(four).legs.length,4);
 assert.equal(parse('M2'+barcode().slice(2)),null,'A missing second leg cannot be replaced by the first leg');
});

test('BCBP missing or unassigned values remain absent and complete names are never invented',()=>{
 for(const seat of ['0000','000 ','    ','000A','----','ABCD']) {
  assert.deepEqual(parse(barcode([leg({seat})])),{passenger:'FIXTURE TRAVELLER',legs:[{origin:'BOG',destination:'MDE'}]});
 }
 assert.deepEqual(parse(barcode([leg()],'                    ')),{legs:[{origin:'BOG',destination:'MDE',seat:'12A'}]});
 assert.equal(parse(barcode([leg()],'TRAVELLER/'))?.passenger,'TRAVELLER');
 assert.equal(parse(barcode([leg()],'TRAVELLER'))?.passenger,'TRAVELLER');
 assert.equal(parse(barcode([leg()],'NAME/FIRST/OTHER'))?.passenger,undefined);
});

test('BCBP malformed, truncated or non-ASCII records cannot supply automatic flight details',()=>{
 const source=barcode();
 for(const invalid of [null,{},'',source.slice(0,59),' '+source,'M0'+source.slice(2),'M5'+source.slice(2),source+'\n',source+'é',source+'arbitrary-tail',barcode([leg({origin:'123'})]),barcode([leg({destination:'mde'})]),barcode([leg({day:'000'})]),barcode([leg({day:'367'})]),barcode([leg({carrier:'   '})]),barcode([leg({flight:'ABCDE'})]),source.slice(0,58)+'GG',source.slice(0,58)+'FF',source.slice(0,22)+'X'+source.slice(23),'M1'+' '.repeat(4095)]) {
  assert.equal(parse(invalid),null,String(invalid));
 }
 assert.equal(parse(source.slice(0,58)+'04ABC'),null,'A truncated conditional block is not a complete leg');
});

test('BCBP security suffix stays outside flight legs and remains byte-identical',()=>{
 const suffix='^104ABCD',source=barcode([leg()],'TRAVELLER/FIXTURE',suffix+'   ');
 assert.deepEqual(parse(source),parse(barcode()));
 assert.ok(source.endsWith(suffix+'   '));
 assert.equal(parse(barcode([leg()],'TRAVELLER/FIXTURE','^105ABCD')),null);
 assert.equal(parse(barcode([leg()],'TRAVELLER/FIXTURE','^104ABCDunexpected')),null);
});
