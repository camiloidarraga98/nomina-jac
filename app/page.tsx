import PayrollPage from './payroll-page';
export const dynamic='force-dynamic';
export default async function Home({searchParams}:{searchParams:Promise<{periodo?:string;'jac-notice'?:string}>}){const params=await searchParams;return <PayrollPage periodId={params.periodo} noticeId={params['jac-notice']}/>;}
