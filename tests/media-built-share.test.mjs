import test from 'node:test';
import assert from 'node:assert/strict';
import {readdir,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {Miniflare} from 'miniflare';

// Run after npm run build. Use the date supported by the installed disposable
// Workerd, without changing the production Worker's compatibility settings.
test('built Worker serves AASA and a private anonymous page, and rejects an unknown share',async()=>{
 const root=resolve('dist/server'),entry=resolve(root,'index.js');
 const paths=(await readdir(root,{recursive:true,withFileTypes:true})).filter(x=>x.isFile()&&/\.m?js$/.test(x.name)).map(x=>resolve(x.parentPath,x.name)).filter(x=>x!==entry);
 const mf=new Miniflare({unsafeTriggerHandlers:true,modules:[entry,...paths].map(path=>({type:'ESModule',path})),modulesRoot:root,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],d1Databases:{DB:'fixture-built-media'},bindings:{JAC_HOSTING:'cloudflare',JAC_READY:'1',PAYROLL_AUTH_KEY:'fixture-built-share-independent-auth-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')},outboundService:()=>{throw new Error('No external service may be contacted by the built share fixture');}});
 try{
  const db=await mf.getD1Database('DB');for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
  const aasa=await mf.dispatchFetch('https://built-share.invalid/.well-known/apple-app-site-association');assert.equal(aasa.status,200);assert.deepEqual((await aasa.json()).applinks.details[0].appIDs,['AYHVYN8BJF.co.jacmusic.nomina']);
  const page=await mf.dispatchFetch('https://built-share.invalid/compartir/'+'a'.repeat(43)),html=await page.text();assert.equal(page.status,200,html.slice(0,300));assert.ok(html.includes('Carpeta compartida'));assert.match(page.headers.get('cache-control'),/no-store/);assert.equal(page.headers.get('referrer-policy'),'no-referrer');
  const denied=await mf.dispatchFetch('https://built-share.invalid/api/media/shared?token='+'a'.repeat(43));assert.equal(denied.status,410);assert.match(denied.headers.get('cache-control'),/no-store/);
  const playback=await mf.dispatchFetch('https://built-share.invalid/api/media/playback?id=r2_private');assert.equal(playback.status,401);assert.match(playback.headers.get('cache-control'),/no-store/);
  const diagnostics=await mf.dispatchFetch('https://built-share.invalid/api/media/playback?diagnostics=1');assert.equal(diagnostics.status,401);assert.equal((await diagnostics.json()).configured,undefined);
  const invalidLease=await mf.dispatchFetch('https://built-share.invalid/api/media/playback?lease=invalid&asset=manifest/video.m3u8');assert.equal(invalidLease.status,403);
  // No Stream secret is provided: the real scheduled entry point must return
  // without creating tables, copying media or contacting an external service.
  const scheduled=await mf.dispatchFetch('https://built-share.invalid/cdn-cgi/handler/scheduled?cron='+encodeURIComponent('* * * * *'));assert.equal(scheduled.status,200);
  // The readiness switch must also pause scheduled paid work, even when its
  // secret is configured. This database intentionally has no user tables.
  const paused=new Miniflare({unsafeTriggerHandlers:true,modules:[entry,...paths].map(path=>({type:'ESModule',path})),modulesRoot:root,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],d1Databases:{DB:'fixture-paused-media'},bindings:{JAC_READY:'0',JAC_STREAM_API_TOKEN:'fixture-paused-only'},outboundService:()=>{throw new Error('Paused Worker must not contact Stream');}});
  try{assert.equal((await paused.dispatchFetch('https://paused-share.invalid/cdn-cgi/handler/scheduled')).status,200);}finally{await paused.dispose();}
  const zip=await mf.dispatchFetch('https://built-share.invalid/api/media/shared/download',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token:'a'.repeat(43),mode:'all'}).toString()});assert.equal(zip.status,410);assert.match(zip.headers.get('content-type'),/text\/html/);assert.equal(zip.headers.get('content-disposition'),null);assert.match(await zip.text(),/No se pudo descargar/);
 }finally{await mf.dispose();}
});
