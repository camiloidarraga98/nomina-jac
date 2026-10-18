import application from './index';

type DeploymentEnv=Parameters<typeof application.fetch>[1]&{JAC_HOSTING?:string;JAC_READY?:string};

export default {
  async fetch(request:Request,env:DeploymentEnv,ctx:Parameters<typeof application.fetch>[2]){
    const url=new URL(request.url);
    if(['/_jac/transfer','/migracion','/api/hosting-transfer','/api/hosting-transfer-inventory'].includes(url.pathname))return new Response(null,{status:404,headers:{'Cache-Control':'no-store'}});
    if(url.pathname==='/_jac/health'){
      return Response.json({service:'JAC',ready:env.JAC_READY==='1'},{headers:{'Cache-Control':'no-store','X-Robots-Tag':'noindex, nofollow'}});
    }
    // A deployment alone cannot activate an empty database, send notifications
    // or expose the CRM. Readiness is a runtime secret set after migration QA;
    // it is deliberately absent from the build configuration and GitHub.
    if(env.JAC_READY!=='1')return new Response('JAC está preparando este entorno. El sitio habitual sigue disponible.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store','Retry-After':'3600','X-Robots-Tag':'noindex, nofollow'}});
    return application.fetch(request,env,ctx);
  }
};
