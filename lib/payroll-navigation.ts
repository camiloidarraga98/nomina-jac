import {hasSection,type AccessUser} from './payroll-permissions';
// Navigation only: these paths never execute payroll commands.
export const sectionPaths:Record<string,string>={fotografia:'/fotografia',crm:'/crm',gastos:'/gastos-de-viaje',configuracion:'/configuracion',notificaciones:'/configuracion/notificaciones',conexiones:'/configuracion/conexiones',quincena:'/',agenda:'/agenda',itinerarios:'/itinerarios',alertas:'/alertas',personal:'/personal',reglas:'/conceptos',archivo:'/archivo',correos:'/correos',cuenta:'/mi-cuenta',usuarios:'/usuarios'};
export const tabPaths:Record<string,string>={shows:'/',novedades:'/quincena/novedades',gastosShow:'/quincena/gastos',recorridos:'/quincena/recorridos',horas:'/quincena/horas',pagos:'/quincena/liquidacion'};
export type PayrollRoute={view:string;tab:string};
export function payrollRoute(pathname:string):PayrollRoute|null{
 const path=pathname.replace(/\/$/,'')||'/';
 const view=Object.keys(sectionPaths).find(key=>sectionPaths[key]===path);
 if(view)return {view,tab:'shows'};
 const tab=Object.keys(tabPaths).find(key=>tabPaths[key]===path);
 return tab?{view:'quincena',tab}:null;
}
export function payrollHref(view:string,tab='shows',periodId?:string){
 const path=view==='quincena'?tabPaths[tab]:sectionPaths[view];
 if(!path)throw new Error('Sección desconocida');
 return path+(periodId&&['quincena','correos'].includes(view)?'?periodo='+encodeURIComponent(periodId):'');
}

export function canViewSection(user:AccessUser,view:string):boolean {
 if(view==='cuenta')return true;
 if(view==='agenda')return hasSection(user,'calendar');
 if(view==='itinerarios')return hasSection(user,'itineraries')||hasSection(user,'boarding');
 if(view==='alertas')return hasSection(user,'alerts');
 if(view==='fotografia')return hasSection(user,'media');
 if(view==='crm')return user.isOwner&&hasSection(user,'crm');
 if(view==='gastos')return hasSection(user,'itineraries');
 if(view==='notificaciones')return ['itineraries','alerts','boarding'].some(k=>hasSection(user,k as 'itineraries'|'alerts'|'boarding'));
 if(['usuarios','conexiones'].includes(view))return user.isOwner;
 if(view==='configuracion')return ['gastos','notificaciones','alertas','personal','reglas','archivo','correos','usuarios','conexiones'].some(v=>canViewSection(user,v));
 return ['quincena','personal','reglas','archivo','correos'].includes(view)&&hasSection(user,'payroll');
}
export function defaultSection(user:AccessUser){if(user.sections===undefined&&user.itinerariesOnly&&!user.mediaOnly)return 'itinerarios';return ['quincena','agenda','itinerarios','fotografia','alertas','cuenta'].find(v=>canViewSection(user,v))||'cuenta';}
