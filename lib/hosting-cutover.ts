type CutoverEnv={JAC_ORIGIN_FROZEN?:string;JAC_HOSTING?:string};

// Activated only for the final copy. The old origin stays frozen after the
// switch so a cached DNS answer cannot create a second writable database.
// Unfreezing is a deliberate rollback step, never an automatic timeout.
export function frozenOriginResponse(request:Request,env:CutoverEnv):Response|null{
 if(env.JAC_ORIGIN_FROZEN!=='1'||env.JAC_HOSTING==='cloudflare')return null;
 const path=new URL(request.url).pathname;
 const migration=path==='/migracion'||path==='/api/hosting-transfer'||path==='/api/hosting-transfer-inventory';
 const asset=['GET','HEAD'].includes(request.method)&&/^\/assets\/[A-Za-z0-9._-]+$/.test(path);
 if(migration||asset)return null;
 return new Response('JAC está trasladando sus datos. Intenta nuevamente en unos minutos.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store','Retry-After':'60','X-Robots-Tag':'noindex, nofollow'}});
}
