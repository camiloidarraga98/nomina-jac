import {tokenHash,sessionToken} from './payroll-auth-crypto';
import {canCrm,CrmFailure} from './crm-core';
import {sectionSql,type AccessUser} from './payroll-permissions';
export type CrmGuard={sql:string;bindings:(string|number)[]};
export function crmGuard(req:Request,u:AccessUser):CrmGuard{
 if(!canCrm(u))throw new CrmFailure('El CRM está disponible solo para administradores.',403);
 const secure=!/^(localhost|127\.0\.0\.1)$/.test(new URL(req.url).hostname),token=sessionToken(req.headers.get('cookie')||'',secure);
 return crmStoredGuard(tokenHash(token),u.id);
}
export function crmStoredGuard(sessionID:string,userID:string):CrmGuard{
 return {sql:`EXISTS(SELECT 1 FROM payroll_sessions cs JOIN payroll_users cu ON cu.id=cs.user_id AND cu.version=cs.user_version WHERE cs.id=? AND cu.id=? AND (cs.persistent=1 OR cs.expires_at>?) AND cu.active=1 AND cu.password_hash<>'' AND ${sectionSql('cu','crm')})`,bindings:[sessionID,userID,new Date().toISOString()]};
}
