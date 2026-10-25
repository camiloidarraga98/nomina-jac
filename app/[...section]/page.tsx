import PayrollPage from '../payroll-page';
import {payrollRoute} from '@/lib/payroll-navigation';
import {notFound} from 'next/navigation';
export const dynamic='force-dynamic';
export default async function SectionPage({params,searchParams}:{params:Promise<{section:string[]}>;searchParams:Promise<{periodo?:string;'jac-notice'?:string;carpeta?:string}>}){const {section}=await params;const route=payrollRoute('/'+section.join('/'));if(!route)notFound();const query=await searchParams;return <PayrollPage route={route} periodId={query.periodo} noticeId={query['jac-notice']} mediaFolderId={query.carpeta}/>;}
