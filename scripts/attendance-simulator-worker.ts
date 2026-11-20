import {attendanceBoundary} from '../lib/attendance-http';
import {handlePayrollAuth} from '../lib/payroll-auth-http';

// Only loaded into the disposable local Miniflare instance.
const loginPage = '<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Acceso · JAC</title><link rel="stylesheet" href="/_jac/acceso.css"><div id="acceso"></div><script type="module" src="/_jac/acceso.js"></script></html>';
const loginAssets = new Set(['/_jac/acceso.js', '/_jac/acceso.css', '/jac-music-offline.js']);

const worker = {
  async fetch(request: Request, env: {DB: D1Database; ASSETS: Fetcher}) {
    const response = await attendanceBoundary(request, env);
    if (response) return response;
    const url = new URL(request.url);
    if (url.pathname === '/api/auth' && request.method === 'POST') {
      return handlePayrollAuth(request, async () => null);
    }
    if (request.method === 'GET' || request.method === 'HEAD') {
      if (url.pathname === '/') return Response.redirect(new URL('/acceso', url), 303);
      if (url.pathname === '/acceso') {
        return new Response(request.method === 'HEAD' ? null : loginPage, {headers: {
          'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'private, no-store'
        }});
      }
      if (loginAssets.has(url.pathname)) return env.ASSETS.fetch(request);
    }
    return new Response(null, {status: 404});
  }
};
export default worker;
