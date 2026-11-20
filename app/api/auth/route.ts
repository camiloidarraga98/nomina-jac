import {payrollUser} from '@/lib/payroll-access';
import {handlePayrollAuth} from '@/lib/payroll-auth-http';
export const dynamic = 'force-dynamic';
export function POST(request: Request) {
  return handlePayrollAuth(request, payrollUser);
}
