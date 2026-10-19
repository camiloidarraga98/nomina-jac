import {processMediaPresentations} from '../lib/media-stream';
import application from './index';

type DeploymentEnv=Parameters<typeof application.fetch>[1]&{JAC_HOSTING?:string;JAC_READY?:string};
const publicFiles=new Set(['/favicon.svg','/manifest.webmanifest','/jac-music-logo.png','/jac-app-icon.png','/jac-push-sw.js','/jac-media-offline.js','/fotografia-offline.html','/file.svg','/globe.svg','/window.svg']);

export default {
  async scheduled(_controller:unknown,env:DeploymentEnv){if(env.JAC_READY==='1')await processMediaPresentations();},
  async fetch(request:Request,env:DeploymentEnv,ctx:Parameters<typeof application.fetch>[2]){
    const url=new URL(request.url);
    if(url.pathname==='/.well-known/apple-app-site-association'&&['GET','HEAD'].includes(request.method))return Response.json({applinks:{details:[{appIDs:['AYHVYN8BJF.co.jacmusic.nomina'],components:[{'/':'/compartir/*'}]}]}},{headers:{'Cache-Control':'public, max-age=3600','X-Content-Type-Options':'nosniff'}});
    if(['/_jac/transfer','/migracion','/api/hosting-transfer','/api/hosting-transfer-inventory'].includes(url.pathname))return new Response(null,{status:404,headers:{'Cache-Control':'no-store'}});
    if(url.pathname==='/_jac/health'){
      return Response.json({service:'JAC',ready:env.JAC_READY==='1'},{headers:{'Cache-Control':'no-store','X-Robots-Tag':'noindex, nofollow'}});
    }
    // A deployment alone cannot activate an empty database, send notifications
    // or expose the CRM. Readiness is a runtime secret set after migration QA;
    // it is deliberately absent from the build configuration and GitHub.
    if(env.JAC_READY!=='1')return new Response('JAC está preparando este entorno. El sitio habitual sigue disponible.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store','Retry-After':'3600','X-Robots-Tag':'noindex, nofollow'}});
    // run_worker_first sends even CSS/JS here. Only public build files bypass
    // the application; APIs and private documents always retain their guards.
    if(['GET','HEAD'].includes(request.method)&&(url.pathname.startsWith('/assets/')||url.pathname.startsWith('/licenses/')||publicFiles.has(url.pathname)))return env.ASSETS.fetch(request);
    const response=await application.fetch(request,env,ctx);
    if(url.pathname.startsWith('/compartir/')){const protectedResponse=new Response(response.body,response);protectedResponse.headers.set('Cache-Control','private, no-store');protectedResponse.headers.set('Referrer-Policy','no-referrer');protectedResponse.headers.set('X-Robots-Tag','noindex, nofollow, noarchive');return protectedResponse;}
    return response;
  }
};
