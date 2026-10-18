import {headers} from 'next/headers';
import {sessionToken,tokenHash} from './payroll-auth-crypto';
import {payrollUser} from './payroll-access';
import {hasSection,sectionSql,type AccessUser} from './payroll-permissions';

export type PayrollSectionGuard={sql:string;bindings:(string|number)[]};
// User updates revoke the session within the same transaction as the role change.
// Repeat that condition inside the payroll CAS, not only before asynchronous work.
export async function payrollSectionGuard(user:AccessUser):Promise<PayrollSectionGuard|undefined>{
 if(user.legacy)return undefined;
 const h=await headers(),local=/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(h.get('host')||''),session=tokenHash(sessionToken(h.get('cookie')||'',!local));
 return {sql:`EXISTS(SELECT 1 FROM payroll_sessions ps JOIN payroll_users pu ON pu.id=ps.user_id AND pu.version=ps.user_version WHERE ps.id=? AND pu.id=? AND (ps.persistent=1 OR ps.expires_at>?) AND pu.active=1 AND pu.password_hash<>'' AND ${sectionSql('pu','payroll')})`,bindings:[session,user.id,new Date().toISOString()]};
}
export async function payrollReadAuthorized(user:AccessUser){const current=await payrollUser();return !!current&&current.id===user.id&&hasSection(current,'payroll')&&JSON.stringify(current)===JSON.stringify(user);}
export function combinePayrollGuards(...guards:(PayrollSectionGuard|undefined)[]):PayrollSectionGuard|undefined{const defined=guards.filter((guard):guard is PayrollSectionGuard=>!!guard);return defined.length?{sql:defined.map(guard=>'('+guard.sql+')').join(' AND '),bindings:defined.flatMap(guard=>guard.bindings)}:undefined;}
