import {test} from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';

const output=await build({stdin:{contents:"export * from './lib/boarding-message';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {parseBoardingMessage:parse,canonicalBoardingMessage:canonical,normalizeBoardingMessageTime:time}=await import('data:text/javascript;base64,'+Buffer.from(output.outputFiles[0].text).toString('base64'));

test('la descripción de un pase normaliza cuatro campos sin guardar otro texto del mensaje',()=>{
 const input='Aquí está tu pase.\n*SILLA:* 0012a\n**Hora de salida:** 6:45 p. m.\nHora en sala: 17:30\n*AEROLÍNEA*: Avianca';
 const expected={seat:'12A',departureTime:'18:45',boardingTime:'17:30',airline:'Avianca'};
 assert.deepEqual(parse(input),expected);
 assert.equal(canonical(input),'Silla: 12A\nHora de salida: 18:45\nHora en sala: 17:30\nAerolínea: Avianca');
 assert.deepEqual(parse(canonical(input)),expected);
 assert.equal(canonical(canonical(input)),canonical(input));
});

test('los campos vacíos se omiten y una silla sin asignar queda explícitamente vacía',()=>{
 assert.equal(parse('Silla:\nHora de salida: \nHora en sala:\nAerolínea:'),undefined);
 assert.equal(parse('Descripción del archivo sin campos de vuelo.'),undefined);
 assert.deepEqual(parse('Silla: Sin asignar\nHora de salida: 00:30'),{seat:'',departureTime:'00:30'});
 assert.equal(canonical('Silla: Sin asignación'),'Silla: Sin asignar');
 assert.ok(Object.hasOwn(parse('Silla: Pendiente'),'seat'));
 assert.equal(Object.hasOwn(parse('Hora en sala: 23:30'),'seat'),false);
 assert.deepEqual(parse('constructor: Otro vuelo\n__proto__: prueba\nHora en sala: 23:30'),{boardingTime:'23:30'});
});

test('las horas son civiles y explícitas, sin convertir zonas ni inferir otro horario',()=>{
 for(const [input,expected] of [['18:45','18:45'],['0:05','00:05'],['6:45 p. m.','18:45'],['12:05 AM','00:05'],['12:05 PM','12:05'],['11:59pm','23:59']])assert.equal(time(input),expected,input);
 for(const input of ['24:00','14:61','00:30 AM','18:45 PM','18:45 / 19:45','18:45 UTC-5','18:45:00','Gate 6',18,null,{},'Hora de salida: 18:45'])assert.equal(time(input),undefined,JSON.stringify(input));
 assert.deepEqual(parse('Hora en sala: 23:30'),{boardingTime:'23:30'},'No inventar una salida a partir de la hora en sala.');
});

test('la anotación Colombia UTC−5 conserva la hora local y no descarta la silla ni el resto del bloque',()=>{
 const input='Persona ficticia · AV9999 · Ruta ficticia\nSilla: 18C\nHora de salida: 18:35 (hora Colombia, UTC−5)\nHora en sala: 17:35 (hora Colombia, UTC−5)\nAerolínea: Avianca';
 const expected={seat:'18C',departureTime:'18:35',boardingTime:'17:35',airline:'Avianca'};
 assert.deepEqual(parse(input),expected);assert.deepEqual(parse(canonical(input)),expected);
 assert.equal(canonical(input),'Silla: 18C\nHora de salida: 18:35\nHora en sala: 17:35\nAerolínea: Avianca');
 for(const [input,value] of [['0:05 (hora de Colombia, UTC-05:00)','00:05'],['6:35 p. m. (COT, UTC-5)','18:35'],['12:05 AM (HORA COLOMBIA, UTC−5)','00:05']])assert.equal(time(input),value);
});

test('una zona contradictoria, anotación libre o segunda hora sigue rechazando el bloque completo',()=>{
 for(const value of ['18:35 (hora Colombia, UTC-4)','18:35 (hora Colombia, UTC+5)','18:35 (hora local, UTC−5)','18:35 (hora Colombia, UTC-05:30)','18:35 / 19:35 (hora Colombia, UTC−5)','18:35 (hora Colombia, UTC−5) 19:35','18:35 (hora Colombia, UTC−5)\u202e']){
  assert.equal(time(value),undefined,value);assert.equal(parse('Silla: 18C\nHora de salida: '+value),undefined,value);
 }
});

test('no combina dos bloques de vuelo ni acepta valores contradictorios o imposibles',()=>{
 for(const input of [
  'Silla: 12A\nSilla: 22C',
  'Silla: 12A\nSilla: 12A',
  'Hora de salida: 06:00\nHora de salida: 18:45',
  'Silla: 12A\nHora de salida: 18:45\n\nSilla: 22C\nHora de salida: 21:10',
  'Silla: 0A\nHora de salida: 18:45',
  'Silla: 1000A',
  'Hora de salida: 18:45 / 19:45\nAerolínea: Avianca',
  'Hora de salida: 24:00',
  'Aerolínea: <https://untrusted.example.invalid>',
  'Aerolínea: '+ 'A'.repeat(81),
  'Silla: 12A\u0000',
  'Hora de salida: 18:45\u202e',
  'Silla: 12A\n'+'x'.repeat(2000),
 ]){assert.equal(parse(input),undefined,input);assert.equal(canonical(input),'',input);}
 for(const input of [undefined,null,12,[],{seat:'12A'}])assert.equal(parse(input),undefined);
});
