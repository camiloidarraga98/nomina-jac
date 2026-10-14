// Navigation only: these paths never execute payroll commands.
export const sectionPaths:Record<string,string>={crm:'/crm',gastos:'/gastos-de-viaje',configuracion:'/configuracion',notificaciones:'/configuracion/notificaciones',conexiones:'/configuracion/conexiones',quincena:'/',agenda:'/agenda',itinerarios:'/itinerarios',alertas:'/alertas',personal:'/personal',reglas:'/conceptos',archivo:'/archivo',correos:'/correos',cuenta:'/mi-cuenta',usuarios:'/usuarios'};
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
