// Google payloads are untrusted. Only allowlisted codes/service names and a
// numeric project ID may enter diagnostics; never echo Google's raw message.
export function crmGoogleError(status:number,body:unknown,host:string){
 const error=(body as {error?:{details?:{reason?:unknown;metadata?:{service?:unknown;consumer?:unknown}}[];errors?:{reason?:unknown}[]}}|null)?.error;
 const info=Array.isArray(error?.details)?error.details.find(d=>d&&typeof d.reason==='string'&&['SERVICE_DISABLED','ACCESS_TOKEN_SCOPE_INSUFFICIENT','RATE_LIMIT_EXCEEDED'].includes(d.reason)):undefined;
 const legacy=Array.isArray(error?.errors)?error.errors.map(e=>e?.reason):[];
 const service=info?.metadata?.service==='drive.googleapis.com'?'Google Drive API':info?.metadata?.service==='sheets.googleapis.com'?'Google Sheets API':host==='sheets.googleapis.com'?'Google Sheets API':'Google Drive API';
 const consumer=info?.metadata?.consumer,project=typeof consumer==='string'&&/^projects\/\d{1,30}$/.test(consumer)?consumer.slice(9):'';
 const disabled=info?.reason==='SERVICE_DISABLED'||legacy.includes('accessNotConfigured'),scope=info?.reason==='ACCESS_TOKEN_SCOPE_INSUFFICIENT'||legacy.includes('insufficientPermissions');
 const reason=disabled?'SERVICE_DISABLED':scope?'ACCESS_TOKEN_SCOPE_INSUFFICIENT':info?.reason==='RATE_LIMIT_EXCEEDED'||legacy.includes('rateLimitExceeded')||legacy.includes('userRateLimitExceeded')?'RATE_LIMIT_EXCEEDED':'OTHER';
 const message=disabled?`${service} está desactivada${project?' en el proyecto '+project:''}. Actívala en el proyecto de Google de JAC y vuelve a preparar la hoja.`:scope?'Google no concedió el permiso por archivo. Vuelve a autorizar Google Sheets con la cuenta compartida de JAC.':reason==='RATE_LIMIT_EXCEEDED'?'Google alcanzó su límite temporal. Conservamos el registro; vuelve a sincronizar más tarde.':status===403?'Google rechazó el acceso a la hoja. Revisa la cuenta y la autorización.':status===401?'Vuelve a conectar Google Sheets.':'No se pudo sincronizar con Google Sheets. El abono sigue guardado en JAC.';
 return {message,service,reason,project};
}
