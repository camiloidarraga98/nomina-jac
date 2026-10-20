'use strict';
const $=(s,root=document)=>root.querySelector(s);
const $$=(s,root=document)=>[...root.querySelectorAll(s)];
const reduceMotion=window.matchMedia('(prefers-reduced-motion: reduce)');
const motionButton=$('#motion-toggle');
let paused=reduceMotion.matches;
function setMotion(value){paused=value;document.body.classList.toggle('motion-paused',paused);motionButton.setAttribute('aria-pressed',String(paused));motionButton.setAttribute('aria-label',paused?'Reanudar animaciones':'Pausar animaciones');motionButton.replaceChildren(document.createTextNode(paused?'▷ ':'II '),Object.assign(document.createElement('span'),{textContent:paused?'Reanudar':'Pausar'}));}
setMotion(paused);
motionButton.addEventListener('click',()=>setMotion(!paused));
reduceMotion.addEventListener('change',event=>setMotion(event.matches));
const hotspotData={audio:['AUDIO / SISTEMA P.A.','Sistema estéreo a 3 vías · mínimo 110 dB SPL en F.O.H.'],iluminacion:['ILUMINACIÓN / CONTROL','Show por timecode · consolas originales ChamSys o grandMA.'],video:['VIDEO / PANTALLAS','Pantalla central 6 × 4 m · pitch máximo 4 mm.'],tarima:['TARIMA / INFRAESTRUCTURA','12 × 8 m · 1,50 m de altura · aforada con tela negra.']};
$$('[data-hotspot]').forEach(button=>button.addEventListener('click',()=>{const key=button.dataset.hotspot;$$('[data-hotspot]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));$('#stage-scene').dataset.selected=key;$('#stage-detail-label').textContent=hotspotData[key][0];$('#stage-detail-text').textContent=hotspotData[key][1];$('#stage-detail-link').href='#'+key;$('#stage-detail-link').setAttribute('aria-label','Ver requerimientos de '+key);}));
$('#stage-detail-text').setAttribute('aria-live','polite');
const menuButton=$('.mobile-menu'),mobileNav=$('#mobile-nav');
function closeMenu(){menuButton.setAttribute('aria-expanded','false');mobileNav.hidden=true;menuButton.setAttribute('aria-label','Abrir navegación');}
menuButton.addEventListener('click',()=>{const open=menuButton.getAttribute('aria-expanded')!=='true';menuButton.setAttribute('aria-expanded',String(open));menuButton.setAttribute('aria-label',open?'Cerrar navegación':'Abrir navegación');mobileNav.hidden=!open;});
$$('a',mobileNav).forEach(link=>link.addEventListener('click',closeMenu));
window.addEventListener('keydown',event=>{if(event.key==='Escape')closeMenu();});

const screenData={central:['1 central · 6 × 4 m','Pitch máximo 4 mm. Un procesador para todas las pantallas del escenario.'],lagrimas:['4 lágrimas · 1 × 4 m cada una','Pitch máximo 4 mm. Conectadas al mismo procesador del escenario.'],cenefa:['1 cenefa · 6 × 0,50 m','Pitch máximo 4 mm. Instalada en el frente de la sobretarima.'],cctv:['2 laterales CCTV · 4 × 5 m cada una','Pitch máximo 6 mm. Un procesador compartido, con salidas independientes full screen y sin duplicar.']};
function selectScreen(key){$$('[data-screen]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.screen===key)));$$('[data-screen-shape]').forEach(shape=>shape.classList.toggle('selected',shape.dataset.screenShape===key));$('#screen-detail b').textContent=screenData[key][0];$('#screen-detail span').textContent=screenData[key][1];}
$$('[data-screen]').forEach(button=>button.addEventListener('click',()=>selectScreen(button.dataset.screen)));
selectScreen('central');

const planNames={frontal:'Vista frontal',superior:'Vista superior',isometrico:'Vista isométrica'};
const planTabs=$$('[data-plan]');
function selectPlan(key,focus=false){planTabs.forEach(button=>{const selected=button.dataset.plan===key;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;$('#panel-'+button.dataset.plan).hidden=!selected;if(selected&&focus)button.focus();});$('#download-plan').href='/rider/assets/'+key+'.webp';}
planTabs.forEach((button,index)=>{button.addEventListener('click',()=>selectPlan(button.dataset.plan));button.addEventListener('keydown',event=>{let next;if(event.key==='ArrowRight')next=(index+1)%planTabs.length;else if(event.key==='ArrowLeft')next=(index-1+planTabs.length)%planTabs.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=planTabs.length-1;else return;event.preventDefault();selectPlan(planTabs[next].dataset.plan,true);});});
const planDialog=$('#plan-dialog'),enlarged=$('#enlarged-plan');let zoom=100;
function setZoom(value){zoom=Math.max(100,Math.min(300,value));enlarged.style.width=zoom+'%';$('#zoom-level').textContent=zoom+'%';$('#zoom-out').disabled=zoom===100;$('#zoom-in').disabled=zoom===300;}
$$('[data-enlarge]').forEach(button=>button.addEventListener('click',()=>{const key=button.dataset.enlarge;enlarged.src='/rider/assets/'+key+'.webp';enlarged.alt='Plano original de iluminación · '+planNames[key];$('#plan-dialog-title').textContent='Iluminación · '+planNames[key];setZoom(100);planDialog.showModal();$('.plan-dialog-canvas').scrollTo(0,0);}));
$('#zoom-in').addEventListener('click',()=>setZoom(zoom+25));$('#zoom-out').addEventListener('click',()=>setZoom(zoom-25));
$$('[data-close-dialog]').forEach(button=>button.addEventListener('click',()=>$('#'+button.dataset.closeDialog).close()));
$$('dialog').forEach(dialog=>{dialog.addEventListener('click',event=>{if(event.target!==dialog)return;const rect=dialog.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)dialog.close();});});

const searchDialog=$('#search-dialog'),searchInput=$('#rider-search'),searchResults=$('#search-results');
searchDialog.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();searchDialog.close();}});
const normalize=text=>text.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('es');
const searchSections=$$('.technical-section, #planos, #equipo');
const searchItems=[];
for(const area of searchSections){const title=$('h2',area)?.textContent.replace(/\s+/g,' ').trim()||'Rider técnico';searchItems.push({area,title,element:$('h2',area),text:title});const targets=$$('.inventory-row,.conditions p,.notice,.logistics-list article,.technical-section>p,.contact-card,.legend-grid>div,.mini-stats>div,.producer-callout,.timeline li,.console-grid>div,.spec-line,.dimension-card',area);for(const element of targets){const text=element.textContent.replace(/\s+/g,' ').trim();if(text)searchItems.push({area,title,element,text});}}
function openSearch(){closeMenu();searchDialog.showModal();searchInput.focus();}
$$('.search-trigger').forEach(button=>button.addEventListener('click',openSearch));
window.addEventListener('keydown',event=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='k'){event.preventDefault();if(!searchDialog.open&&!planDialog.open)openSearch();}});
function addMessage(text){const p=document.createElement('p');p.className='search-hint';p.textContent=text;searchResults.append(p);}
searchInput.addEventListener('input',()=>{const term=normalize(searchInput.value.trim());searchResults.replaceChildren();if(term.length<2){addMessage('Escribe al menos 2 caracteres. Prueba con “teleprompter”, “110 V” o “camerino”.');return;}const words=term.split(/\s+/);const matches=searchItems.filter(item=>words.every(word=>normalize(item.text+' '+item.title).includes(word)));if(!matches.length){addMessage('Sin resultados. Prueba con otro equipo, medida o área.');return;}addMessage(matches.length+' resultados'+(matches.length>30?' · mostrando los primeros 30':''));for(const item of matches.slice(0,30)){const link=document.createElement('a');link.href='#'+item.area.id;link.className='search-result';const title=document.createElement('strong');title.textContent=item.title+' ↗';const text=document.createElement('p');text.textContent=item.text;link.append(title,text);link.addEventListener('click',event=>{event.preventDefault();searchDialog.close();let parent=item.element.parentElement;while(parent){if(parent.tagName==='DETAILS')parent.open=true;parent=parent.parentElement;}history.replaceState(null,'','#'+item.area.id);item.element.scrollIntoView({behavior:reduceMotion.matches?'instant':'smooth',block:'center'});item.element.classList.remove('search-highlight');requestAnimationFrame(()=>item.element.classList.add('search-highlight'));item.element.setAttribute('tabindex','-1');item.element.focus({preventScroll:true});});searchResults.append(link);}});

let scrollQueued=false;
function updateReading(){const max=document.documentElement.scrollHeight-innerHeight;$('.reading-progress').style.transform='scaleX('+(max>0?scrollY/max:0)+')';let active=$$('.technical-section')[0];for(const section of $$('.technical-section')){if(section.getBoundingClientRect().top<innerHeight*.4)active=section;}$$('[data-nav]').forEach(link=>{const selected=link.dataset.nav===active?.id;link.classList.toggle('active',selected);if(selected)link.setAttribute('aria-current','location');else link.removeAttribute('aria-current');});scrollQueued=false;}
addEventListener('scroll',()=>{if(!scrollQueued){requestAnimationFrame(updateReading);scrollQueued=true;}},{passive:true});addEventListener('resize',updateReading);updateReading();
if('IntersectionObserver' in window&&!reduceMotion.matches){const observer=new IntersectionObserver(entries=>{for(const entry of entries){if(entry.isIntersecting){entry.target.classList.remove('is-waiting');observer.unobserve(entry.target);}}},{rootMargin:'0px 0px 70px 0px',threshold:.05});$$('.section-kicker,.plans-header,.team-heading,.contact-card').forEach(element=>{element.classList.add('reveal','is-waiting');observer.observe(element);});}
