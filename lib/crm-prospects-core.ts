export const PROSPECT_YEAR=2027;
export const PROSPECT_WHATSAPP='https://wa.me/573125064091';
export const PROSPECT_MAX_BATCH=20;
export const STAGE_LABELS={new:'Nuevo',contacted:'Contactado',interested:'Interesado',negotiating:'En negociación',won:'Ganado',lost:'Descartado',do_not_contact:'No contactar'} as const;
export const DELIVERY_LABELS={pending:'En cola',sending:'Enviando',sent:'Enviado',error:'Error',uncertain:'Por confirmar',cancelled:'Cancelado'} as const;
export type ProspectStage=keyof typeof STAGE_LABELS;
export type DeliveryStatus=keyof typeof DELIVERY_LABELS;
export type ReplyStatus='none'|'received'|'automatic'|'bounced';
export type Delivery={id:string;batchId:string;prospectId:string;email:string;subject:string;body:string;status:DeliveryStatus;replyStatus:ReplyStatus;sentAt:string;messageId:string;threadId:string;rfcMessageId:string;error:string;repliedAt:string;createdAt:string;gmailUrl:string};
export type Prospect={id:string;version:number;sourceId:string;year:number;department:string;municipality:string;festival:string;period:string;month:number;projectedDate:string;mayorName:string;email:string;emails:string[];dateStatus:'projected';stage:ProspectStage;notes:string;nextFollowUp:string;eligible:boolean;contacted:boolean;lastDelivery:Delivery|null};
export type Brochure={id:string;filename:string;size:number;ready:boolean};
export type Batch={id:string;status:'pending'|'completed'|'cancelled';createdAt:string;total:number;pending:number;sending:number;sent:number;error:number;uncertain:number;cancelled:number};
export type ProspectMailConnection={sender:string;connected:boolean;trackingConnected:boolean;error:string};
export type ProspectFeed={prospects:Prospect[];total:number;page:number;pages:number;pageSize:number;summary:{total:number;ready:number;sent:number;replied:number;pending:number;contacted:number};departments:string[];brochure:Brochure|null;mail:ProspectMailConnection;template:{subject:string;body:string}};
export type ProspectPreview={messages:{prospectId:string;prospectVersion:number;email:string;subject:string;body:string}[];brochure:Brochure|null;excluded:{prospectId:string;reason:string}[];previewHash:string};
export const PROSPECT_TEMPLATE={
 subject:'{{fiesta}} {{anio}} en {{municipio}}: una noche con Jhon Alex Castaño',
 body:'{{saludo}}\n\nLe escribimos desde el equipo de management de Jhon Alex Castaño para proponer su show en vivo para {{fiesta}}, en {{municipio}}, dentro de la programación de {{anio}}.\n\nQueremos ayudarles a crear una noche que la gente recuerde y cante de principio a fin. Jhon Alex llega acompañado de nueve músicos en vivo y un repertorio que conecta con el público, con canciones como «Mi Tío», «Amigos con Derechos» y «Dos Razones».\n\nAdjuntamos el brochure para que conozcan la propuesta artística y el formato del espectáculo. Nos gustaría conversar sobre la fecha prevista, el espacio y el presupuesto de su celebración, y revisar juntos disponibilidad y condiciones.\n\n¿Podría indicarnos quién coordina la programación artística de las fiestas? También puede contactarme directamente por WhatsApp: {{whatsapp}}\n\nCamilo Idarraga\nManagement de Jhon Alex Castaño · JAC Music'
};
export class ProspectFailure extends Error{constructor(message:string,readonly status=400){super(message);}}
export const prospectUUID=(value:unknown):value is string=>typeof value==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
export const prospectEmail=(value:unknown):value is string=>typeof value==='string'&&value.length<=254&&/^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$/.test(value)&&!/[\r\n]/.test(value);
export function prospectDate(value:unknown):value is string{if(value==='')return true;if(typeof value!=='string'||!/^2027-\d{2}-\d{2}$/.test(value))return false;const date=new Date(value+'T12:00:00Z');return !Number.isNaN(date.getTime())&&date.toISOString().slice(0,10)===value;}
export function followUpDate(value:unknown):value is string{if(value==='')return true;if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;const date=new Date(value+'T12:00:00Z');return !Number.isNaN(date.getTime())&&date.toISOString().slice(0,10)===value;}
const TOKENS=new Set(['municipio','departamento','fiesta','alcalde','saludo','periodo','whatsapp','anio','fecha']);
export function validateProspectTemplate(subject:unknown,body:unknown){
 if(typeof subject!=='string'||!subject.trim()||subject.length>200||/[\r\n\x00-\x1f\x7f]/.test(subject))throw new ProspectFailure('Revisa el asunto: hasta 200 caracteres y una sola línea.');
 if(typeof body!=='string'||!body.trim()||body.length>10000||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(body))throw new ProspectFailure('Revisa el mensaje: hasta 10.000 caracteres.');
 for(const value of [subject,body]){for(const match of value.matchAll(/\{\{\s*([^{}]+?)\s*\}\}/g))if(!TOKENS.has(match[1]))throw new ProspectFailure('La plantilla contiene un campo que no está disponible.');if(value.replace(/\{\{\s*[^{}]+?\s*\}\}/g,'').includes('{{')||value.replace(/\{\{\s*[^{}]+?\s*\}\}/g,'').includes('}}'))throw new ProspectFailure('Revisa las llaves de los campos personalizados.');}
 return {subject:subject.trim(),body:body.trim()};
}
export function renderProspectMessage(prospect:Pick<Prospect,'municipality'|'department'|'festival'|'mayorName'|'period'|'projectedDate'|'year'>,subject:string,body:string){
 const template=validateProspectTemplate(subject,body),clean=(value:string)=>value.replace(/[\r\n\x00-\x1f\x7f]/g,' ').trim();
 const values:Record<string,string>={municipio:clean(prospect.municipality),departamento:clean(prospect.department),fiesta:clean(prospect.festival),alcalde:clean(prospect.mayorName),saludo:prospect.mayorName.trim()?`Señor(a) alcalde(sa) ${clean(prospect.mayorName)} y equipo de la Alcaldía de ${clean(prospect.municipality)}:`:`Señor alcalde y equipo de la Alcaldía de ${clean(prospect.municipality)}:`,periodo:clean(prospect.period),whatsapp:PROSPECT_WHATSAPP,anio:String(prospect.year),fecha:prospect.projectedDate||clean(prospect.period)};
 const render=(value:string)=>value.replace(/\{\{\s*([^{}]+?)\s*\}\}/g,(_,token:string)=>values[token]);
 const result={subject:render(template.subject),body:render(template.body)};if(result.subject.length>500)throw new ProspectFailure('El asunto personalizado es demasiado largo.');return result;
}
