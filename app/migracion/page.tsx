import {env} from 'cloudflare:workers';
import {notFound} from 'next/navigation';
import {payrollUser} from '@/lib/payroll-access';
import {OWNER_EMAIL} from '@/lib/payroll-auth-store';
import HostingTransfer from './transfer';
export const dynamic='force-dynamic';
export default async function MigrationPage(){
 const user=await payrollUser();
 if(!user||user.legacy||user.email!==OWNER_EMAIL||!await env.DB.prepare('SELECT id FROM payroll_users WHERE id=? AND owner=1 AND active=1').bind(user.id).first())notFound();
 const e=env as typeof env&{JAC_TRANSFER_PUBLIC_KEY?:string;JAC_TRANSFER_EXPIRES?:string};
 const expiry=Date.parse(e.JAC_TRANSFER_EXPIRES||'');
 const enabled=!!e.JAC_TRANSFER_PUBLIC_KEY&&Number.isFinite(expiry)&&expiry>Date.now()&&expiry-Date.now()<=2*60*60*1000;
 return <main style={{maxWidth:720,margin:'60px auto',padding:24}}><h1>Traslado de JAC</h1><p>Prepara una copia cifrada para trasladar JAC a tu cuenta de Cloudflare. Los originales permanecen en el sitio actual.</p><HostingTransfer enabled={enabled}/><p><a href="/crm">Volver al CRM</a></p></main>;
}
