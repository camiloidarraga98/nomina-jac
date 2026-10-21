import {runMaintenance} from '../lib/maintenance';
import {handleBirthdayApi,processBirthdayJobs} from '../lib/fans-birthday';
import application from './index';

type DeploymentEnv=Parameters<typeof application.fetch>[1]&{JAC_HOSTING?:string;JAC_READY?:string};
const publicFiles=new Set(['/favicon.svg','/manifest.webmanifest','/jac-music-logo.png','/jac-app-icon.png','/jac-push-sw.js','/jac-media-offline.js','/fotografia-offline.html','/musica-offline.html','/jac-music-offline.js','/jac-music-offline-shell.js','/file.svg','/globe.svg','/window.svg']);

export default {
  async scheduled(controller:{cron?:string},env:DeploymentEnv){
    if(env.JAC_READY!=='1')return;
    // Two independent invocations each start at most five generations. This
    // stays below Workers' six pending outgoing connections per invocation;
    // the database enforces ten active leases across both cron triggers.
    if(controller.cron==='0-59 * * * *')await processBirthdayJobs();
    else await runMaintenance();
  },
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
    // Public fan experience has its own anonymous cookie, bot checks and bounded
    // queue. It never enters the administrative application's authentication.
    if(url.pathname==='/api/fans/cumpleanos')return handleBirthdayApi(request);
    if(url.pathname==='/cumple'||url.pathname==='/cumple/'||url.pathname==='/cumple/index.html'||url.pathname==='/cumpleanos'||url.pathname.startsWith('/cumpleanos/')){
      if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:{Allow:'GET, HEAD'}});
      if(['/cumple/','/cumple/index.html','/cumpleanos','/cumpleanos/','/cumpleanos/index.html'].includes(url.pathname)){
        url.pathname='/cumple';
        return new Response(null,{status:308,headers:{Location:url.href,'Cache-Control':'public, max-age=300','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'}});
      }
      if(url.pathname==='/cumple')url.pathname='/cumpleanos/';
      const response=await env.ASSETS.fetch(new Request(url,request));
      const fanPage=new Response(response.body,response);
      fanPage.headers.set('X-Content-Type-Options','nosniff');
      fanPage.headers.set('Referrer-Policy','no-referrer');
      fanPage.headers.set('Content-Security-Policy',"default-src 'none'; script-src 'self' https://challenges.cloudflare.com; style-src 'self'; img-src 'self' blob: data:; connect-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'");
      fanPage.headers.set('Cache-Control',url.pathname.endsWith('.png')?'public, max-age=31536000, immutable':'public, max-age=300');
      return fanPage;
    }
    // The artist's rider is explicitly public. Keep its static namespace apart
    // from the application router and all authenticated API/document routes.
    if(url.pathname==='/rider'||url.pathname.startsWith('/rider/')||url.pathname==='/rider2'||url.pathname.startsWith('/rider2/')){
      if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:{Allow:'GET, HEAD'}});
      if(url.pathname==='/rider'||url.pathname==='/rider2')url.pathname+='/';
      const response=await env.ASSETS.fetch(new Request(url,request));
      const rider=new Response(response.body,response);
      rider.headers.set('X-Content-Type-Options','nosniff');
      rider.headers.set('Referrer-Policy','strict-origin-when-cross-origin');
      rider.headers.set('Content-Security-Policy',"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'none'");
      rider.headers.set('Cache-Control',url.pathname.endsWith('.pdf')?'public, max-age=3600':'public, max-age=300, stale-while-revalidate=86400');
      return rider;
    }
    // run_worker_first sends even CSS/JS here. Only public build files bypass
    // the application; APIs and private documents always retain their guards.
    if(['GET','HEAD'].includes(request.method)&&(url.pathname.startsWith('/assets/')||url.pathname.startsWith('/licenses/')||publicFiles.has(url.pathname)))return env.ASSETS.fetch(request);
    const response=await application.fetch(request,env,ctx);
    if(url.pathname.startsWith('/compartir/')){const protectedResponse=new Response(response.body,response);protectedResponse.headers.set('Cache-Control','private, no-store');protectedResponse.headers.set('Referrer-Policy','no-referrer');protectedResponse.headers.set('X-Robots-Tag','noindex, nofollow, noarchive');return protectedResponse;}
    return response;
  }
};
