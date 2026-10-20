import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const general=await readFile('public/rider/index.html','utf8');
const privateRider=await readFile('public/rider/privados/index.html','utf8');
const area=(html,id)=>html.match(new RegExp('<section class="technical-section" id="'+id+'"[\\s\\S]*?</section>'))?.[0]||'';
const rows=html=>[...html.matchAll(/<div class="inventory-row"><span class="quantity">([^<]+)<\/span><span class="item-description">([^<]+)<\/span><\/div>/g)].map(match=>[match[1],match[2]]);

test('general y privados tienen selector enlazable y conservan sus inventarios separados',()=>{
 for(const html of [general,privateRider]){assert.match(html,/aria-label="Modalidad del rider"/);assert.match(html,/href="\/rider"/);assert.match(html,/href="\/rider\/privados"/);assert.doesNotMatch(html,/data-check=|class="checklist-box"|<span>MI LISTA<\/span>/);}
 assert.equal(rows(general).length,54);assert.equal(rows(privateRider).length,44);
 assert.match(general,/12 × 8 × 1,50 m/);assert.match(privateRider,/8 × 6 × 1,50 m/);
});

test('privados usa las cantidades del PDF, incluidos Gerbs, dos lágrimas estrechas y un solo teleprompter',()=>{
 const fx=rows(area(privateRider,'backline'));for(const[count,part]of [['4','Boquillas sencillas de CO₂ con 16 pipas de 25 kg'],['4','Lanzallamas con 24 latas'],['4','Sparkular Stage con 8 sobres de insumos'],['1 sistema','Pirotecnia Cobra'],['12','Gerbs 1 × 8']])assert.ok(fx.some(([qty,name])=>qty===count&&name===part),part);
 const lights=rows(area(privateRider,'iluminacion'));for(const[count,name]of [['16','Robin Pointe'],['12','PAR LED'],['4','Blinder de 4 bombillas'],['10','MAC Aura'],['4','Atomics RGB']])assert.ok(lights.some(([qty,label])=>qty===count&&label===name),name);
 assert.match(area(privateRider,'iluminacion'),/Consola MA2 o MA3/);assert.doesNotMatch(area(privateRider,'iluminacion'),/ChamSys|Seguidores|Puente trasero/);
 const video=rows(area(privateRider,'video'));assert.ok(video.some(([qty,name])=>qty==='2'&&name.startsWith('Lágrimas: 0,50 × 4 m')));assert.ok(video.some(([qty,name])=>qty==='1'&&name.startsWith('Teleprompter de 32 pulgadas, a 1,50 m al lateral derecho')));
 assert.doesNotMatch(area(privateRider,'video'),/CCTV|Cámaras|intercom|Videoprocesadores/);
 assert.doesNotMatch(area(privateRider,'backline'),/Sparkular Fall|Flamer X2|Stadiumshot|Minas con/);
});

test('privados conserva infraestructura, hospitalidad, contactos y cuatro referencias originales con advertencia',()=>{
 const stage=area(privateRider,'tarima');for(const text of ['Escalera al lado','Mesas técnicas fuera','mínimo 1,50 × 2,50 m','área de 1 m libre','polisombra'])assert.ok(stage.includes(text),text);
 for(const text of ['Cristhian Betancourt','Camilo Idárraga','Fabio Sánchez','Juan José Rivera','Juan Sebastián Sánchez','110 V','20 personas','Don Julio 70','Red Bull originales','2 pacas de agua y 2 de Electrolit/Gatorade','Condición contractual'])assert.ok(privateRider.includes(text),text);
 assert.equal((privateRider.match(/data-plan="/g)||[]).length,4);assert.match(privateRider,/id="panel-general"/);assert.match(privateRider,/no sustituye los listados de esta versión/);assert.match(privateRider,/https:\/\/wa.me\/573117132850/);
 assert.match(privateRider,/href="\/rider\/privados\/rider-discotecas-privados-2026.pdf"/);
});
