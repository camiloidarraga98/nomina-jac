import test from 'node:test';
import assert from 'node:assert/strict';
import {readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {Miniflare} from 'miniflare';

// Run after npm run build. Use the date supported by the installed disposable
// Workerd, without changing the production Worker's compatibility settings.
test('built Worker serves AASA and a private anonymous page, and rejects an unknown share',async()=>{
 const root=resolve('dist/server'),entry=resolve(root,'index.js');
 const paths=(await readdir(root,{recursive:true,withFileTypes:true})).filter(x=>x.isFile()&&/\.m?js$/.test(x.name)).map(x=>resolve(x.parentPath,x.name)).filter(x=>x!==entry);
 const mf=new Miniflare({modules:[entry,...paths].map(path=>({type:'ESModule',path})),modulesRoot:root,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],d1Databases:{DB:'fixture-built-media'},bindings:{JAC_HOSTING:'cloudflare',JAC_READY:'1',PAYROLL_AUTH_KEY:'fixture-built-share-independent-auth-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')},outboundService:()=>{throw new Error('No external service may be contacted by the built share fixture');}});
 try{
  const aasa=await mf.dispatchFetch('https://built-share.invalid/.well-known/apple-app-site-association');assert.equal(aasa.status,200);assert.deepEqual((await aasa.json()).applinks.details[0].appIDs,['AYHVYN8BJF.co.jacmusic.nomina']);
  const page=await mf.dispatchFetch('https://built-share.invalid/compartir/'+'a'.repeat(43)),html=await page.text();assert.equal(page.status,200,html.slice(0,300));assert.ok(html.includes('Carpeta compartida'));assert.match(page.headers.get('cache-control'),/no-store/);assert.equal(page.headers.get('referrer-policy'),'no-referrer');
  const denied=await mf.dispatchFetch('https://built-share.invalid/api/media/shared?token='+'a'.repeat(43));assert.equal(denied.status,410);assert.match(denied.headers.get('cache-control'),/no-store/);
  const zip=await mf.dispatchFetch('https://built-share.invalid/api/media/shared/download',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token:'a'.repeat(43),mode:'all'}).toString()});assert.equal(zip.status,410);assert.match(zip.headers.get('content-type'),/text\/html/);assert.equal(zip.headers.get('content-disposition'),null);assert.match(await zip.text(),/No se pudo descargar/);
 }finally{await mf.dispose();}
});
