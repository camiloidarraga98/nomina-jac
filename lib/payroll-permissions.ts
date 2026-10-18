import {sameValue} from './payroll-policy';
import type {PayrollState} from './payroll';
export const permissions={payroll:'Registrar shows, kilómetros, horas y novedades',staff:'Modificar personal y tarifas',rules:'Modificar conceptos y parámetros',close:'Cerrar quincenas y enviar sus desprendibles',modifyClosed:'Modificar cierres de quincena (reabrir, corregir y volver a cerrar)',send:'Enviar o reintentar desprendibles',export:'Descargar e imprimir documentos'} as const;
export type Permission=keyof typeof permissions;
export type AccessUser={id:string;email:string;username:string;displayName:string;fullName:string|null;isOwner:boolean;permissions:Permission[];itinerariesOnly?:boolean;mediaOnly?:boolean;sections?:SectionKey[];legacy?:boolean};
export const sectionLabels={payroll:'Nómina y quincenas',calendar:'Agenda',itineraries:'Itinerarios',alerts:'Alertas',boarding:'Pases de abordar',media:'Fotografía y video',mediaUpload:'Subir fotos y videos',crm:'CRM (administradores)'} as const;
export type SectionKey=keyof typeof sectionLabels;
export const sectionKeys=Object.keys(sectionLabels) as SectionKey[];
const standardSections:SectionKey[]=['payroll','calendar','itineraries','alerts','boarding'];
type SectionUser=Pick<AccessUser,'isOwner'|'itinerariesOnly'|'mediaOnly'|'sections'>;
export function resolvedSections(user:SectionUser):SectionKey[]{
 if(user.isOwner&&!user.itinerariesOnly&&!user.mediaOnly)return [...sectionKeys];
 if(user.sections!==undefined){if(!Array.isArray(user.sections)||user.sections.some(key=>!sectionKeys.includes(key)))return [];return sectionKeys.filter(key=>user.sections!.includes(key)&&(key!=='crm'||user.isOwner)&&(key!=='mediaUpload'||user.sections!.includes('media')));}
 if(user.mediaOnly)return ['media','mediaUpload'];
 return user.itinerariesOnly?standardSections.filter(key=>key!=='payroll'):[...standardSections];
}
export function hasSection(user:SectionUser,key:SectionKey){return resolvedSections(user).includes(key);}
// Only literal internal aliases and allowlisted keys enter this SQL fragment.
// NULL preserves legacy profiles; explicit arrays grant only selected sections.
export function sectionSql(alias:string,key:SectionKey){
 if(!/^[A-Za-z_][A-Za-z0-9_]*$/.test(alias)||!sectionKeys.includes(key))throw new Error('Invalid section predicate');
 const a=alias+'.',admin=`(${a}media_only=0 AND ${a}itineraries_only=0 AND ((${a}owner=1 AND ${a}email='camilo@mac2you.co') OR EXISTS(SELECT 1 FROM json_each(${a}permissions) WHERE value='administrator')))`;
 if(key==='crm')return admin;
 const legacy=key==='payroll'?`(${a}media_only=0 AND ${a}itineraries_only=0)`:key==='media'||key==='mediaUpload'?`(${a}media_only=1 OR ${admin})`:`${a}media_only=0`;
 const payload=`CASE WHEN json_valid(${a}section_access) AND json_type(CASE WHEN json_valid(${a}section_access) THEN ${a}section_access ELSE 'null' END)='array' THEN ${a}section_access ELSE '[]' END`;
 const known=sectionKeys.map(k=>`'${k}'`).join(',');
 const custom=`(NOT EXISTS(SELECT 1 FROM json_each(${payload}) WHERE type<>'text' OR value NOT IN (${known})) AND EXISTS(SELECT 1 FROM json_each(${payload}) WHERE value='${key}')${key==='mediaUpload'?` AND EXISTS(SELECT 1 FROM json_each(${payload}) WHERE value='media')`:''})`;
 return `(${admin} OR CASE WHEN ${a}section_access IS NULL THEN ${legacy} ELSE ${custom} END)`;
}
export const permissionKeys=Object.keys(permissions) as Permission[];
// Correction authority must be explicitly granted by the owner.
export const defaultPermissionKeys=permissionKeys.filter(p=>p!=='modifyClosed');
export function can(user:AccessUser,permission:Permission){return hasSection(user,'payroll')&&(user.isOwner||user.permissions.includes(permission));}
export function savePermissionIssue(current:PayrollState,next:PayrollState,user:AccessUser){
 if(!sameValue(current.employees,next.employees)&&!can(user,'staff'))return 'No tienes permiso para modificar personal o tarifas.';
 if((!sameValue(current.settings,next.settings)||!sameValue(current.concepts,next.concepts))&&!can(user,'rules'))return 'No tienes permiso para modificar conceptos o parámetros.';
 for(const p of current.periods){const n=next.periods.find(n=>n.id===p.id);if(!sameValue(p,n)&&!can(user,p.ownerOnly?'modifyClosed':'payroll'))return p.ownerOnly?'No tienes permiso para modificar cierres de quincena.':'No tienes permiso para modificar quincenas.';}
 if(next.periods.some(p=>!current.periods.some(old=>old.id===p.id))&&!can(user,'payroll'))return 'No tienes permiso para modificar quincenas.';
 return null;
}
