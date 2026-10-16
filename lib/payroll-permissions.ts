import {sameValue} from './payroll-policy';
import type {PayrollState} from './payroll';
export const permissions={payroll:'Registrar shows, kilómetros, horas y novedades',staff:'Modificar personal y tarifas',rules:'Modificar conceptos y parámetros',close:'Cerrar quincenas y enviar sus desprendibles',modifyClosed:'Modificar cierres de quincena (reabrir, corregir y volver a cerrar)',send:'Enviar o reintentar desprendibles',export:'Descargar e imprimir documentos'} as const;
export type Permission=keyof typeof permissions;
export type AccessUser={id:string;email:string;username:string;displayName:string;fullName:string|null;isOwner:boolean;permissions:Permission[];itinerariesOnly?:boolean;mediaOnly?:boolean;legacy?:boolean};
export const permissionKeys=Object.keys(permissions) as Permission[];
// Correction authority must be explicitly granted by the owner.
export const defaultPermissionKeys=permissionKeys.filter(p=>p!=='modifyClosed');
export function can(user:AccessUser,permission:Permission){return !user.mediaOnly&&!user.itinerariesOnly&&(user.isOwner||user.permissions.includes(permission));}
export function savePermissionIssue(current:PayrollState,next:PayrollState,user:AccessUser){
 if(!sameValue(current.employees,next.employees)&&!can(user,'staff'))return 'No tienes permiso para modificar personal o tarifas.';
 if((!sameValue(current.settings,next.settings)||!sameValue(current.concepts,next.concepts))&&!can(user,'rules'))return 'No tienes permiso para modificar conceptos o parámetros.';
 for(const p of current.periods){const n=next.periods.find(n=>n.id===p.id);if(!sameValue(p,n)&&!can(user,p.ownerOnly?'modifyClosed':'payroll'))return p.ownerOnly?'No tienes permiso para modificar cierres de quincena.':'No tienes permiso para modificar quincenas.';}
 if(next.periods.some(p=>!current.periods.some(old=>old.id===p.id))&&!can(user,'payroll'))return 'No tienes permiso para modificar quincenas.';
 return null;
}
