import {payrollUser, payrollHeaders} from '@/lib/payroll-access';
import {canCrm} from '@/lib/crm-core';
import {crmGuard} from '@/lib/crm-access';
import {guardActive} from '@/lib/crm-store';
import {reconciliationHtml} from '@/lib/reconciliation-view';

export const dynamic = 'force-dynamic';

const headers = {
  ...payrollHeaders,
  'Content-Type': 'text/html; charset=utf-8',
  'X-Frame-Options': 'SAMEORIGIN',
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data:; connect-src 'self'; frame-src 'self' blob:; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'self'",
};

function denied(status: number) {
  const message = status === 401 ? 'Inicia sesión con tu cuenta de JAC para continuar.' : 'La conciliación está disponible solo para administradores con acceso al CRM.';
  return new Response(`<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Acceso a conciliación</title></head><body><main><h1>Conciliación de abonos</h1><p>${message}</p><a href="/acceso?returnTo=%2Fcrm%3Fseccion%3Dconciliacion" target="_top">Iniciar sesión en JAC</a></main></body></html>`, {status, headers});
}

export async function GET(request: Request) {
  try {
    const user = await payrollUser();
    if (!user || user.legacy) return denied(401);
    if (!canCrm(user) || !await guardActive(crmGuard(request, user))) return denied(403);
    return new Response(reconciliationHtml, {headers});
  } catch {
    return new Response('No pudimos abrir la conciliación. Actualiza la página para volver a intentar.', {status: 503, headers: {...headers, 'Content-Type': 'text/plain; charset=utf-8'}});
  }
}
