import PayrollPage from './payroll-page';
export const dynamic='force-dynamic';
export default async function Home({searchParams}:{searchParams:Promise<{periodo?:string}>}){const params=await searchParams;return <PayrollPage periodId={params.periodo}/>;}
