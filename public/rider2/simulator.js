/* JAC Rider 2. Standalone, local-only spatial preview. Coordinates in metres. */
(()=>{'use strict';
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const canvas=$('#sim-canvas'), ctx=canvas.getContext('2d');
if(!ctx){$('#sim-selected-status').textContent='Este navegador no admite Canvas. Consulta los requisitos y planos abajo.';return;}
const types={
 pointe:{name:'Robin Pointe',count:24,layer:'lights',color:'#40d9ff',kind:'beam',page:6},
 par:{name:'PAR LED',count:22,layer:'lights',color:'#f07f7f',kind:'wash',page:6},
 blinder:{name:'Blinder · 4 bombillas',count:8,layer:'lights',color:'#ffe2a1',kind:'blinder',page:6},
 aura:{name:'MAC Aura',count:16,layer:'lights',color:'#b09aff',kind:'wash',page:6},
 atomic:{name:'Atomics RGB',count:8,layer:'lights',color:'#fe80df',kind:'strobe',page:6},
 follow:{name:'Seguidor · 2.500 W',count:2,layer:'lights',color:'#f3f3e0',kind:'beam',page:6},
 hazer:{name:'Hazer con ventilador',count:2,layer:'lights',color:'#a1bdc7',kind:'haze',page:6},
 central:{name:'Pantalla central · 6 × 4 m',count:1,layer:'video',color:'#36bce5',kind:'screen',w:6,h:4,page:7},
 tear:{name:'Lágrima · 1 × 4 m',count:4,layer:'video',color:'#36bce5',kind:'screen',w:1,h:4,page:7},
 fascia:{name:'Cenefa · 6 × 0,50 m',count:1,layer:'video',color:'#36bce5',kind:'screen',w:6,h:.5,page:7},
 cctv:{name:'CCTV · 4 × 5 m',count:2,layer:'video',color:'#36bce5',kind:'screen',w:4,h:5,page:7},
 co2:{name:'CO₂',count:8,layer:'fx',color:'#c2efff',kind:'co2',page:5,stock:'16 pipas de 25 kg'},
 flame:{name:'Lanzallamas',count:8,layer:'fx',color:'#ffab3d',kind:'flame',page:5,stock:'24 latas'},
 spark:{name:'Sparkular Stage',count:8,layer:'fx',color:'#ffdf96',kind:'spark',page:5,stock:'8 sobres'},
 fall:{name:'Sparkular Fall',count:8,layer:'fx',color:'#ffe7b0',kind:'fall',page:5,stock:'8 sobres'},
 x2:{name:'Flamer X2',count:4,layer:'fx',color:'#ff704b',kind:'x2',page:5,stock:'40 L de Isoparg'},
 cobra:{name:'Sistema Cobra',count:1,layer:'fx',color:'#8ca1ad',kind:'controller',page:5},
 mine:{name:'Minas / géiser',count:16,layer:'fx',color:'#f6b9ff',kind:'mine',page:5,stock:'Alternativa géiser de 1 s × 3 m según espacio'},
 shot:{name:'Stadiumshot',count:4,layer:'fx',color:'#92f0bc',kind:'shot',page:5,stock:'Con insumos'},
 prompter:{name:'Teleprompter · 32 pulgadas',count:2,layer:'support',color:'#829ba8',kind:'monitor',page:7},
 sidefill:{name:'Side fill · 3 vías',count:2,layer:'support',color:'#829ba8',kind:'speaker',page:5}
};
const spread=(i,n,a,b)=>n===1?(a+b)/2:a+(b-a)*i/(n-1);
const defaultDevices=[];
for(const [type,t] of Object.entries(types))for(let i=0;i<t.count;i++){
 let x=spread(i,t.count,-5.6,5.6),z=0,y=.15,angle=0,source='Propuesta editable · ubicación sin cotas en el documento.';
 if(t.layer==='lights'){
  if(type==='pointe'){const row=Math.floor(i/8),col=i%8;x=spread(col,8,-5.5,5.5);z=[0,4.3,7.5][row];y=row===0?.25:5.8;}
  if(type==='par'){const row=i<12?0:1;let j=row?i-12:i,n=row?10:12;x=spread(j,n,-5.5,5.5);z=row?7.5:4.3;y=5.8;}
  if(type==='aura'){x=spread(i%8,8,-5.4,5.4);z=i<8?0:4.3;y=5.55;}
  if(type==='blinder'){x=spread(i,8,-5.5,5.5);z=.05;y=5.7;}
  if(type==='atomic'){x=spread(i%4,4,-5.2,5.2);z=i<4?4.3:7.3;y=6.05;}
  if(type==='follow'){x=i?8:-8;z=-6;y=2.2;}
  if(type==='hazer'){x=i?5.5:-5.5;z=7;y=.1;}
  source='Adaptación editable del plano (págs. 11–13) al inventario de la pág. 6. Altura propuesta.';
 }
 if(t.kind==='screen'){
  z=7.85;y=3.3;
  if(type==='central')x=0;
  if(type==='tear')x=[-5.2,-3.8,3.8,5.2][i];
  if(type==='fascia'){x=0;z=5.7;y=.3;source='Frente de la sobretarima · medida y ubicación indicadas en pág. 7.';}
  else if(type==='cctv'){x=i?8.8:-8.8;y=3.6;source='Laterales L/R según plano; separación y altura ajustables.';}
  else source='Esquema de pantallas (pág. 14); medidas de pág. 7. Altura y separación propuestas.';
 }
 if(t.layer==='fx'){
  z=({co2:.3,flame:.7,spark:1.1,x2:1.5,mine:1.8,shot:1.3})[type]??-.5;
  if(type==='fall'){z=7.6;y=6.2;}
  if(type==='cobra'){x=-7;z=2;y=.3;}
 }
 if(type==='prompter'){x=i?1.5:-1.5;z=2.2;y=.2;source='A 1,50 m a izquierda y derecha del centro (pág. 7). Fondo propuesto.';}
 if(type==='sidefill'){x=i?6.7:-6.7;z=2;y=.6;source='L/R según pág. 5. Fondo y separación propuestos.';}
 defaultDevices.push({id:type+'-'+(i+1),type,x,z,y,angle,source});
}
let devices=structuredClone(defaultDevices), selectedId='central-1', view='iso',yaw=-.32,pitch=.36,zoom=1;
let labels=false, look='#36caff',intensity=.75,movement=.35,video=true,lightOn=true,haze=true;
let demoPaused=false;
let playing=false,playTime=0,lastTime=0,visualTime=0,paused=matchMedia('(prefers-reduced-motion: reduce)').matches;
const visible={lights:true,video:true,fx:true,support:true},active=new Map();
const defaultCues=[{time:0,target:'look:cyan'},{time:2,target:'co2'},{time:4,target:'flame'},{time:6,target:'look:amber'},{time:7,target:'x2'},{time:10,target:'spark'},{time:13,target:'fall'},{time:16,target:'look:magenta'},{time:17,target:'mine'},{time:20,target:'shot'},{time:23,target:'look:white'}];
let cues=structuredClone(defaultCues), fired=new Set(), hitPoints=[],W=900,H=510,S=32;
const storageKey='jac-rider2-montaje-v1';
const looks={cyan:'#36caff',amber:'#ffad44',magenta:'#dd68ff',white:'#e2f5ff'};
const current=()=>devices.find(d=>d.id===selectedId);
const round=n=>Math.round(n*10)/10;
const clamp=(n,a,b)=>Math.min(b,Math.max(a,n));
const status=message=>{$('#sim-save-status').textContent=message;};
function validateLayout(value){
 if(value?.version!==1||!Array.isArray(value.devices)||value.devices.length!==defaultDevices.length)throw Error('Formato de montaje incompatible.');
 const seen=new Set();
 const next=value.devices.map(d=>{
  const base=defaultDevices.find(b=>b.id===d.id&&b.type===d.type);
  if(!base||seen.has(d.id))throw Error('El montaje debe conservar todos los equipos y sus cantidades.');seen.add(d.id);
  for(const [key,min,max] of [['x',-12,12],['z',-8,14],['y',0,10],['angle',-180,180]])if(typeof d[key]!=='number'||!Number.isFinite(d[key])||d[key]<min||d[key]>max)throw Error('Coordenadas fuera del rango admitido.');
  return {...base,x:d.x,z:d.z,y:d.y,angle:d.angle};
 });
 let nextCues=structuredClone(defaultCues);
 if(value.cues!==undefined){if(!Array.isArray(value.cues)||value.cues.length>80)throw Error('Secuencia no válida.');nextCues=value.cues.map(c=>{if(!Number.isFinite(c.time)||c.time<0||c.time>24||!validTarget(c.target))throw Error('Evento no válido.');return {time:c.time,target:c.target};});}
 return {devices:next,cues:nextCues};
}
function validTarget(t){return typeof t==='string'&&(Boolean(types[t])||Boolean(devices.find(d=>d.id===t))||Boolean(looks[t.replace('look:','')])&&t.startsWith('look:'));}
function save(){try{localStorage.setItem(storageKey,JSON.stringify({version:1,devices,cues}));status('Montaje guardado en este navegador.');}catch{status('No se pudo guardar aquí. Usa Exportar montaje para conservarlo.');}}
try{const saved=localStorage.getItem(storageKey);if(saved){const next=validateLayout(JSON.parse(saved));devices=next.devices;cues=next.cues;}}catch{status('No se pudo recuperar el montaje guardado. Se usa el rider original.');}
function makeOption(value,label){const op=document.createElement('option');op.value=value;op.textContent=label;return op;}
const groupNames={lights:'ILUMINACIÓN',video:'VIDEO',fx:'EFECTOS',support:'APOYO'};
for(const layer of Object.keys(groupNames)){const group=document.createElement('optgroup');group.label=groupNames[layer];for(const [key,t] of Object.entries(types))if(t.layer===layer)group.append(makeOption(key,t.name+' · '+t.count));$('#sim-category').append(group);}
for(const [key,t] of Object.entries(types))if(t.kind!=='controller')$('#sim-cue-target').append(makeOption(key,t.name));
for(const key of Object.keys(looks))$('#sim-cue-target').append(makeOption('look:'+key,'Luces · '+({cyan:'Azul',amber:'Ámbar',magenta:'Magenta',white:'Blanco'})[key]));
function populateEquipment(){const key=$('#sim-category').value;$('#sim-equipment').replaceChildren(...devices.filter(d=>d.type===key).map((d,i)=>makeOption(d.id,types[key].name+' '+(i+1))));}
function selectDevice(id){selectedId=id;const d=current(),t=types[d.type];if($('#sim-category').value!==d.type){$('#sim-category').value=d.type;populateEquipment();}$('#sim-equipment').value=id;
 for(const k of ['x','z','y','angle'])$('#sim-'+k).value=round(d[k]);
 $('#sim-selected-name').textContent=t.name;$('#sim-selected-id').textContent=d.id.toUpperCase();$('#sim-source').textContent='Pág. '+t.page+' · '+d.source+(t.stock?' '+t.stock+'.':'');
 $('#sim-fire-selected').textContent=t.kind==='controller'?'Control de pirotecnia Cobra':'▶ Previsualizar este equipo';$('#sim-fire-selected').disabled=t.kind==='controller';$('#sim-selected-status').textContent=visible[t.layer]?'':'Esta capa está oculta. Actívala para ver el equipo.';
}
$('#sim-category').addEventListener('change',()=>{populateEquipment();selectDevice($('#sim-equipment').value);});$('#sim-equipment').addEventListener('change',e=>selectDevice(e.target.value));
for(const [key,min,max] of [['x',-12,12],['z',-8,14],['y',0,10],['angle',-180,180]])$('#sim-'+key).addEventListener('change',e=>{let val=e.target.valueAsNumber;if(!Number.isFinite(val)){selectDevice(selectedId);return;}current()[key]=round(clamp(val,min,max));selectDevice(selectedId);save();});
function setLook(key){look=looks[key];lightOn=true;$$('[data-look]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.look===key)));}
$$('[data-look]').forEach(b=>b.addEventListener('click',()=>setLook(b.dataset.look)));
function duration(type){return ({mine:1,flame:1.6,x2:1.8,co2:2.6,spark:3,fall:3.5,shot:4})[type]??2.2;}
function fire(target){
 demoPaused=false;if(document.body.classList.contains('motion-paused'))$('#motion-toggle').click();
 if(target.startsWith('look:')){setLook(target.slice(5));return;}
 const list=devices.filter(d=>d.type===target||d.id===target);
 for(const d of list){const t=types[d.type];if(t.kind==='controller')continue;active.set(d.id,{start:visualTime,duration:duration(d.type)});visible[t.layer]=true;if(t.kind==='screen')video=true;}
 if(list.some(d=>types[d.type].layer==='lights'))lightOn=true;
 syncLayers();$('#sim-selected-status').textContent='Previsualización: '+(types[target]?.name||types[list[0]?.type]?.name||'equipo')+'.';
}
$('#sim-fire-selected').addEventListener('click',()=>fire(selectedId));
for(const [key,t] of Object.entries(types))if(t.layer==='fx'&&t.kind!=='controller'){const b=document.createElement('button');b.dataset.fire=key;b.append(document.createTextNode(t.name+' '),Object.assign(document.createElement('b'),{textContent:String(t.count)}));b.addEventListener('click',()=>fire(key));$('#sim-fx-buttons').append(b);}
function syncLayers(){$$('[data-layer]').forEach(b=>b.setAttribute('aria-pressed',String(visible[b.dataset.layer])));$('#sim-video').setAttribute('aria-pressed',String(video));$('#sim-video').textContent=video?'Pantallas encendidas':'Pantallas apagadas';}
$$('[data-layer]').forEach(b=>b.addEventListener('click',()=>{visible[b.dataset.layer]=!visible[b.dataset.layer];syncLayers();selectDevice(selectedId);}));
$('#sim-labels').addEventListener('click',e=>{labels=!labels;e.currentTarget.setAttribute('aria-pressed',String(labels));});
$('#sim-video').addEventListener('click',()=>{video=!video;syncLayers();});
$('#sim-intensity').addEventListener('input',e=>{intensity=+e.target.value/100;lightOn=intensity>0;});$('#sim-movement').addEventListener('input',e=>movement=+e.target.value/100);
function updateTransport(){$('#sim-play').textContent=playing?'Ⅱ Pausar demo':'▶ Demo del show';$('#sim-time').textContent='00:'+String(Math.floor(playTime)).padStart(2,'0')+' / 00:24';$('#sim-timeline').value=playTime;$('#sim-running').textContent=playing?'● DEMO EN CURSO':'VISTA PREVIA';}
function renderCues(){const list=$('#sim-cues');list.replaceChildren();cues.forEach((cue,i)=>{const b=document.createElement('button');const name=cue.target.startsWith('look:')?'Luces':types[cue.target]?.name||cue.target;b.textContent=cue.time.toFixed(1)+'s '+name+' ×';b.setAttribute('aria-label','Eliminar evento '+name+' en '+cue.time+' segundos');b.addEventListener('click',()=>{cues.splice(i,1);fired.clear();renderCues();save();});list.append(b);});}
function stop(){demoPaused=false;playing=false;playTime=0;active.clear();fired.clear();updateTransport();}
$('#sim-play').addEventListener('click',()=>{if(playTime>=24){playTime=0;fired.clear();}playing=!playing;demoPaused=!playing;if(playing){if(document.body.classList.contains('motion-paused'))$('#motion-toggle').click();paused=false;lightOn=true;haze=true;}updateTransport();});
$('#sim-stop').addEventListener('click',stop);
$('#sim-blackout').addEventListener('click',()=>{stop();lightOn=false;video=false;haze=false;syncLayers();$('#sim-selected-status').textContent='Blackout: luces, pantallas y efectos apagados.';});
$('#sim-timeline').addEventListener('input',e=>{playTime=+e.target.value;active.clear();fired.clear();cues.forEach((c,i)=>{if(c.time<=playTime){fired.add(i);if(c.target.startsWith('look:'))fire(c.target);else if(playTime-c.time<duration(c.target)){fire(c.target);for(const d of devices.filter(d=>d.type===c.target||d.id===c.target)){const a=active.get(d.id);if(a)a.start=visualTime-(playTime-c.time);}}}});updateTransport();});
$('#sim-add-cue').addEventListener('click',()=>{if(cues.length>=80){status('Máximo 80 eventos por secuencia.');return;}cues.push({time:round(playTime),target:$('#sim-cue-target').value});cues.sort((a,b)=>a.time-b.time);fired.clear();renderCues();save();});
$('#sim-reset-cues').addEventListener('click',()=>{stop();cues=structuredClone(defaultCues);renderCues();save();});
$('#motion-toggle').addEventListener('click',()=>{paused=$('#motion-toggle').getAttribute('aria-pressed')==='true';});
$('#sim-zoom').addEventListener('input',e=>zoom=+e.target.value/100);
$$('[data-view]').forEach(b=>b.addEventListener('click',()=>{view=b.dataset.view;yaw=view==='iso'?-.32:0;pitch=view==='top'?Math.PI/2:view==='front'?.045:.36;$$('[data-view]').forEach(v=>v.setAttribute('aria-pressed',String(v===b)));$('#sim-view-help').textContent=view==='top'?'Vue superior · arrastra equipos para ubicarlos en metros'.replace('Vue','Vista'):'Arrastra un equipo para moverlo · Arrastra el fondo para girar';}));
$('#sim-fullscreen').addEventListener('click',async()=>{try{if(document.fullscreenElement)await document.exitFullscreen();else await $('.sim-workspace').requestFullscreen();}catch{status('Pantalla completa no disponible en este navegador.');}});
$('#sim-export').addEventListener('click',()=>{const blob=new Blob([JSON.stringify({version:1,title:'JAC Rider 2 · montaje',units:'metres',devices,cues},null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='jac-rider2-montaje.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
$('#sim-import').addEventListener('change',async e=>{const file=e.target.files[0];if(!file)return;try{if(file.size>300000)throw Error('El archivo supera 300 KB.');const next=validateLayout(JSON.parse(await file.text()));stop();devices=next.devices;cues=next.cues;selectDevice(selectedId);renderCues();save();status('Montaje importado. Cantidades del rider conservadas.');}catch(error){status('No se importó: '+error.message);}e.target.value='';});
$('#sim-reset').addEventListener('click',()=>{if(!confirm('¿Restaurar todas las posiciones del rider? Puedes exportar el montaje antes.'))return;devices=structuredClone(defaultDevices);stop();selectDevice(selectedId);save();});
function project(x,y,z){const zz=z-3,xx=x*Math.cos(yaw)+zz*Math.sin(yaw),depth=zz*Math.cos(yaw)-x*Math.sin(yaw);return {x:W/2+xx*S,y:H*.68-depth*Math.sin(pitch)*S-y*Math.cos(pitch)*S,depth:depth*Math.cos(pitch)+y*Math.sin(pitch)};}
function point(d){return project(d.x,d.y,d.z);}
function poly(points,fill,stroke,width=1){ctx.beginPath();points.forEach((p,i)=>{const q=project(...p);i?ctx.lineTo(q.x,q.y):ctx.moveTo(q.x,q.y);});ctx.closePath();if(fill){ctx.fillStyle=fill;ctx.fill();}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=width;ctx.stroke();}}
function line(a,b,color,width=1){const p=project(...a),q=project(...b);ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(q.x,q.y);ctx.strokeStyle=color;ctx.lineWidth=width;ctx.stroke();}
function box(x,y,z,w,h,dep,fill,stroke){poly([[x-w/2,y,z-dep/2],[x+w/2,y,z-dep/2],[x+w/2,y+h,z-dep/2],[x-w/2,y+h,z-dep/2]],fill,stroke);poly([[x+w/2,y,z-dep/2],[x+w/2,y,z+dep/2],[x+w/2,y+h,z+dep/2],[x+w/2,y+h,z-dep/2]],fill,stroke);poly([[x-w/2,y+h,z-dep/2],[x+w/2,y+h,z-dep/2],[x+w/2,y+h,z+dep/2],[x-w/2,y+h,z+dep/2]],fill,stroke);}
function text3(text,x,y,z,color='#7f9cac',size=9){const p=project(x,y,z);ctx.fillStyle=color;ctx.font=size+'px sans-serif';ctx.textAlign='center';ctx.fillText(text,p.x,p.y);}
function truss(a,b){line(a,b,'#6a8592',2);const len=Math.hypot(b[0]-a[0],b[1]-a[1],b[2]-a[2]),n=Math.ceil(len/.45);for(let i=0;i<n;i++){const t=i/n,u=(i+1)/n;const aa=a.map((v,k)=>v+(b[k]-v)*t),bb=a.map((v,k)=>v+(b[k]-v)*u);aa[1]+=.2;bb[1]-=.2;line(aa,bb,'#3d5969',.8);}const a2=[a[0],a[1]+.22,a[2]],b2=[b[0],b[1]+.22,b[2]];line(a2,b2,'#566f7e',1);}
function drawStructure(){
 // Ground and stage: base top y=0, physical height=1.5 m.
 for(let x=-12;x<=12;x+=1)line([x,-1.5,-8],[x,-1.5,14],'#122432',.7);
 for(let z=-8;z<=14;z+=1)line([-12,-1.5,z],[12,-1.5,z],'#122432',.7);
 poly([[-6,-1.5,0],[6,-1.5,0],[6,0,0],[-6,0,0]],'#0b1a24','#35505e');
 poly([[6,-1.5,0],[6,-1.5,8],[6,0,8],[6,0,0]],'#07131d','#35505e');
 poly([[-6,0,0],[6,0,0],[6,0,8],[-6,0,8]],'#132632','#45606e');
 for(let x=-6;x<=6;x++)line([x,.006,0],[x,.006,8],'#1b3442',.6);
 for(let z=0;z<=8;z++)line([-6,.006,z],[6,.006,z],'#1b3442',.6);
 poly([[-6,.01,0],[6,.01,0],[6,.01,2],[-6,.01,2]],'#3b281b66','#95612c');
 text3('ZONA DE EFECTOS · 2 m',0,.02,1,'#9d8159',9);
 box(0,0,6.5,8,.6,1.5,'#1c3542','#597580');
 text3('SOBRETARIMA 8 × 1,50 m',0,.65,6.5,'#628696',8);
 for(const side of [-1,1]){for(let i=0;i<4;i++)box(side*6.3,-1.5+i*.375,2+i*.28,.6,.375,.32,'#142936','#3e5663');}
 truss([-6,6,0],[6,6,0]);truss([-4,6,7.5],[4,6,7.5]);
 truss([-1.5,6,4.3],[1.5,6,4.3]);truss([-1.5,6,7.4],[1.5,6,7.4]);
 truss([-6,6,6.2],[-3,6,7.5]);truss([3,6,7.5],[6,6,6.2]);truss([-3.3,1,7.8],[-3.3,6,7.8]);truss([3.3,1,7.8],[3.3,6,7.8]);
 truss([-10.3,6.4,7.85],[-7.3,6.4,7.85]);truss([7.3,6.4,7.85],[10.3,6.4,7.85]);
 text3('12 m',0,-.6,0,'#9bb9c8',11);text3('8 m',6.3,0,4,'#9bb9c8',10);text3('PÚBLICO / FRENTE',0,-1.5,-5,'#3f687d',10);
}
function drawScreen(d){const t=types[d.type],a=d.angle*Math.PI/180,half=t.w/2,c=Math.cos(a),s=Math.sin(a),y=d.y;
 const pts=[[d.x-c*half,y-t.h/2,d.z-s*half],[d.x+c*half,y-t.h/2,d.z+s*half],[d.x+c*half,y+t.h/2,d.z+s*half],[d.x-c*half,y+t.h/2,d.z-s*half]];
 poly(pts,video?'#0b536d':'#08121a',video?'#3286a3':'#30434e',1);
 if(video){
  const count=d.type==='tear'?8:16;
  for(let i=0;i<count;i++){const f=(i+.5)/count,dx=(f-.5)*t.w,h=t.h*(.27+.22*Math.sin(i*.8+visualTime*.8));line([d.x+c*dx,y-h/2,d.z+s*dx],[d.x+c*dx,y+h/2,d.z+s*dx],d.type==='cctv'?(d.id.endsWith('1')?'#60dcb8':'#bd9af3'):look,Math.max(1,S*t.w/count*.4));}
  text3(d.type==='central'?'JHON ALEX':d.type==='cctv'?(d.id.endsWith('1')?'CCTV L':'CCTV R'):'',d.x,y+.05,d.z,'#dcf7ff',Math.max(7,S*.25));
 }
}
function drawDevice(d){const t=types[d.type],p=point(d),isSelected=d.id===selectedId;
 if(t.kind==='screen')drawScreen(d);
 else{
  if(t.kind==='speaker')box(d.x,d.y-.5,d.z,.55,1.2,.55,'#0a151e','#54707c');
  else if(t.kind==='monitor')box(d.x,d.y-.2,d.z,.7,.2,.35,'#152e3c','#7b9cab');
  else {const size=clamp(S*(t.layer==='lights'?.105:.12),2.5,7);ctx.fillStyle=t.layer==='lights'&&lightOn?t.color:'#172e3b';ctx.strokeStyle=t.color;ctx.lineWidth=1;ctx.beginPath();if(t.kind==='blinder'){ctx.rect(p.x-size*1.6,p.y-size*.6,size*3.2,size*1.2);}else if(t.layer==='fx'){ctx.rect(p.x-size,p.y-size,size*2,size*2);}else ctx.arc(p.x,p.y,size,0,Math.PI*2);ctx.fill();ctx.stroke();}
 }
 if(isSelected){ctx.strokeStyle='#a4f6ff';ctx.lineWidth=1.5;ctx.beginPath();ctx.arc(p.x,p.y,11,0,Math.PI*2);ctx.stroke();line([d.x,0,d.z],[d.x,d.y,d.z],'#51c6e866',1);}
 if(labels||isSelected){ctx.font='9px sans-serif';ctx.textAlign='center';const label=isSelected?t.name+' · '+d.id.split('-').pop():d.id.toUpperCase();const width=ctx.measureText(label).width;ctx.fillStyle='#05121ce6';ctx.fillRect(p.x-width/2-4,p.y-28,width+8,15);ctx.fillStyle=isSelected?'#bdffff':'#9bb4c4';ctx.fillText(label,p.x,p.y-17);}
 hitPoints.push({id:d.id,x:p.x,y:p.y,screen:t.kind==='screen',device:d});
}
function beam(d,color,power){const t=types[d.type],p=point(d),a=d.angle*Math.PI/180;
 const sweep=Math.sin(visualTime*.55+d.x*.8)*movement*3,spread=t.kind==='wash'?1.1:.3;
 const end=project(d.x+Math.sin(a)*3+sweep,0,d.z-3.3-Math.cos(a)*1.2);
 const grad=ctx.createLinearGradient(p.x,p.y,end.x,end.y);grad.addColorStop(0,color+'80');grad.addColorStop(1,color+'00');ctx.globalAlpha=power;ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(end.x-S*spread,end.y);ctx.lineTo(end.x+S*spread,end.y);ctx.closePath();ctx.fillStyle=grad;ctx.fill();ctx.globalAlpha=1;
}
function hash(i){const n=Math.sin(i*127.1+31.7)*43758.5453;return n-Math.floor(n);}
function drawEffect(d,age,total){const kind=types[d.type].kind;if(types[d.type].layer==='lights'){if(kind==='haze'){haze=true;}else beam(d,look,1);return;}if(kind==='screen'||kind==='monitor')return;
 const p=point(d),fade=Math.min(1,(total-age)*2),a=d.angle*Math.PI/180;
 ctx.globalAlpha=fade;
 const flame=(offset)=>{const height=(2.4+Math.sin(age*29)*.35)*Math.min(1,age*12,(total-age)*6),tip=project(d.x+Math.sin(a+offset)*height,d.y+Math.cos(a+offset)*height,d.z);const grad=ctx.createLinearGradient(p.x,p.y,tip.x,tip.y);grad.addColorStop(0,'#fff2a6');grad.addColorStop(.35,'#ffae32');grad.addColorStop(1,'#ff3b0a00');ctx.fillStyle=grad;ctx.beginPath();ctx.moveTo(p.x-S*.18,p.y);ctx.quadraticCurveTo(p.x-S*.35,tip.y+S,tip.x,tip.y);ctx.quadraticCurveTo(p.x+S*.4,tip.y+S,p.x+S*.18,p.y);ctx.fill();};
 if(kind==='flame')flame(0);else if(kind==='x2'){flame(-.5);flame(.5);}
 else if(kind==='co2'){
  for(let i=0;i<35;i++){const t=(age*1.5+i/35)%1,dx=(hash(i+d.x)-.5)*(.25+t*.8),q=project(d.x+dx+Math.sin(a)*t*3,d.y+t*3.8,d.z+(hash(i+81)-.5)*t*.3);ctx.globalAlpha=fade*(1-t)*.44;ctx.fillStyle='#d9f6ff';ctx.beginPath();ctx.ellipse(q.x,q.y,S*(.1+t*.22),S*(.14+t*.28),0,0,Math.PI*2);ctx.fill();}
 }else if(['spark','fall','mine','shot'].includes(kind)){
  const count=kind==='shot'?75:55,seed=Number(d.id.split('-').pop())*100;
  for(let i=0;i<count;i++){
   const life=kind==='mine'?age:kind==='shot'?age:(age+hash(i+seed)*1.2)%1.4;
   const speed=kind==='mine'?5.2:kind==='shot'?5:3.8,side=(hash(i+seed)-.5)*(kind==='shot'?3.8:kind==='mine'?1.4:.45);
   const height=kind==='fall'?-life*2.4:Math.max(0,life*speed-2.5*life*life);
   const x=d.x+side*life+Math.sin(a)*height,yy=d.y+height,z=d.z+(hash(i+9+seed)-.5)*life*.8;
   if(yy<0||kind==='mine'&&age>.95)continue;const q=project(x,yy,z);ctx.globalAlpha=fade*(.5+hash(i)*.5);ctx.fillStyle=kind==='shot'?['#96edff','#faf1c1','#fcb1da'][i%3]:kind==='mine'?'#ffe2b0':'#fff0b8';
   if(kind==='shot'){ctx.save();ctx.translate(q.x,q.y);ctx.rotate(age*4+i);ctx.fillRect(-2,-1,4,2);ctx.restore();}
   else {ctx.fillRect(q.x,q.y,1.5,2.5);const tail=project(x-side*.02,yy+(kind==='fall'?.08:-.08),z);ctx.strokeStyle='#ffc15788';ctx.beginPath();ctx.moveTo(q.x,q.y);ctx.lineTo(tail.x,tail.y);ctx.stroke();}
  }
 }
 ctx.globalAlpha=1;
}
function draw(){
 const rect=canvas.getBoundingClientRect(),ratio=Math.min(devicePixelRatio||1,2);W=rect.width;H=rect.height;if(canvas.width!==Math.round(W*ratio)||canvas.height!==Math.round(H*ratio)){canvas.width=Math.round(W*ratio);canvas.height=Math.round(H*ratio);}ctx.setTransform(ratio,0,0,ratio,0,0);S=Math.min(W/25,H/14)*zoom;
 const bg=ctx.createRadialGradient(W*.5,H*.35,5,W*.5,H*.5,W*.65);bg.addColorStop(0,'#102b3d');bg.addColorStop(1,'#050d15');ctx.fillStyle=bg;ctx.fillRect(0,0,W,H);hitPoints=[];
 drawStructure();
 const sorted=devices.filter(d=>visible[types[d.type].layer]).sort((a,b)=>point(b).depth-point(a).depth);
 // Screens and bodies are painted back-to-front; beams/effects are translucent overlays.
 for(const d of sorted)drawDevice(d);
 if(lightOn&&visible.lights){for(const d of devices){const t=types[d.type];if(t.layer==='lights'&&['beam','wash','blinder','strobe'].includes(t.kind)){
   if(t.kind==='blinder'){const p=point(d);ctx.globalAlpha=intensity*.28;ctx.fillStyle='#fff3c0';ctx.beginPath();ctx.arc(p.x,p.y,S*.35,0,Math.PI*2);ctx.fill();ctx.globalAlpha=1;}
   else if(t.kind==='strobe'){const p=point(d);ctx.fillStyle=look;ctx.globalAlpha=intensity*.4;ctx.fillRect(p.x-S*.16,p.y-S*.05,S*.32,S*.1);ctx.globalAlpha=1;}
   else beam(d,look,intensity*(t.kind==='wash'?.23:.4));
  }}
 }
 if(haze&&visible.lights){ctx.fillStyle='#92caff';ctx.globalAlpha=.018;const p=project(0,1.5,4);ctx.beginPath();ctx.ellipse(p.x,p.y,S*5,S*1.3,0,0,Math.PI*2);ctx.fill();ctx.globalAlpha=1;}
 for(const [id,a] of active){const d=devices.find(d=>d.id===id),age=visualTime-a.start;if(age>a.duration){active.delete(id);continue;}if(d&&visible[types[d.type].layer])drawEffect(d,age,a.duration);}
}
function hit(x,y){let best=null,dist=Infinity;for(const p of hitPoints){const d=Math.hypot(x-p.x,y-p.y);if(d<13&&d<dist){best=p;dist=d;}}if(best)return best;
 // Allow clicking the screen surface when no fixture centre is closer.
 for(const p of [...hitPoints].reverse()){if(!p.screen)continue;const d=p.device,t=types[d.type],a=d.angle*Math.PI/180;const verts=[[-1,-1],[1,-1],[1,1],[-1,1]].map(([sx,sy])=>project(d.x+Math.cos(a)*sx*t.w/2,d.y+sy*t.h/2,d.z+Math.sin(a)*sx*t.w/2));let inside=false;for(let i=0,j=3;i<4;j=i++){const A=verts[i],B=verts[j];if((A.y>y)!==(B.y>y)&&x<(B.x-A.x)*(y-A.y)/(B.y-A.y)+A.x)inside=!inside;}if(inside)return p;}
 return null;}
function ground(x,y,height){const xx=(x-W/2)/S,depth=(-(y-H*.68)/S-height*Math.cos(pitch))/Math.max(.04,Math.sin(pitch));return {x:xx*Math.cos(yaw)-depth*Math.sin(yaw),z:3+xx*Math.sin(yaw)+depth*Math.cos(yaw)};}
let drag=null;
canvas.addEventListener('pointerdown',e=>{const r=canvas.getBoundingClientRect(),x=e.clientX-r.left,y=e.clientY-r.top,p=hit(x,y);canvas.setPointerCapture(e.pointerId);if(p){selectDevice(p.id);const q=ground(x,y,current().y);drag={kind:'device',startX:x,startY:y,offsetX:current().x-q.x,offsetZ:current().z-q.z,moved:false};}else drag={kind:'orbit',startX:x,startY:y,yaw,pitch,moved:false};});
canvas.addEventListener('pointermove',e=>{const r=canvas.getBoundingClientRect(),x=e.clientX-r.left,y=e.clientY-r.top;
 if(drag){if(Math.hypot(x-drag.startX,y-drag.startY)>3)drag.moved=true;if(!drag.moved)return;
  if(drag.kind==='device'){const d=current();if(view==='front'){// A frontal view cannot resolve depth from the pointer. Preserve it; use depth input/top view.
   const dx=(x-drag.startX)/S;d.x=round(clamp(d.x+dx,-12,12));drag.startX=x;
  }else {const q=ground(x,y,d.y);d.x=round(clamp(q.x+drag.offsetX,-12,12));d.z=round(clamp(q.z+drag.offsetZ,-8,14));}selectDevice(d.id);}
  else if(view==='iso'){yaw=drag.yaw+(x-drag.startX)*.004;pitch=clamp(drag.pitch+(y-drag.startY)*.003,.16,1.3);}
 }else{const p=hit(x,y),tip=$('#sim-tooltip');canvas.style.cursor=p?'move':'grab';tip.hidden=!p;if(p){tip.textContent=types[p.device.type].name+' · '+p.id;tip.style.left=clamp(x+12,0,W-200)+'px';tip.style.top=clamp(y+15,0,H-50)+'px';}}
});
function endDrag(){if(drag?.kind==='device'&&drag.moved)save();drag=null;}canvas.addEventListener('pointerup',endDrag);canvas.addEventListener('pointercancel',endDrag);canvas.addEventListener('pointerleave',()=>{$('#sim-tooltip').hidden=true;});
canvas.addEventListener('keydown',e=>{const delta=e.shiftKey?.5:.1,d=current();if(e.key==='ArrowLeft')d.x=round(clamp(d.x-delta,-12,12));else if(e.key==='ArrowRight')d.x=round(clamp(d.x+delta,-12,12));else if(e.key==='ArrowUp')d.z=round(clamp(d.z+delta,-8,14));else if(e.key==='ArrowDown')d.z=round(clamp(d.z-delta,-8,14));else return;e.preventDefault();selectDevice(d.id);save();});
let inView=true;const observer=new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;},{rootMargin:'100px'});observer.observe(canvas);
function frame(time){const dt=Math.min((time-lastTime)/1000,.06)||0;lastTime=time;paused=document.body.classList.contains('motion-paused');if(!document.hidden&&inView){if(!paused&&!demoPaused){visualTime+=dt;if(playing){playTime+=dt*Number($('#sim-speed').value);cues.forEach((cue,i)=>{if(cue.time<=playTime&&!fired.has(i)){fire(cue.target);fired.add(i);}});if(playTime>=24){playTime=24;playing=false;}updateTransport();}}draw();}requestAnimationFrame(frame);}
selectDevice(selectedId);renderCues();updateTransport();syncLayers();requestAnimationFrame(frame);
})();
