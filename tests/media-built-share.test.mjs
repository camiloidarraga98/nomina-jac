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

test('built Worker delivers signed HLS initialization and fragments with real D1 guards and revocation',async()=>{
 const root=resolve('dist/server'),entry=resolve(root,'index.js'),uid='b'.repeat(32),delivery='https://customer-fixture.cloudflarestream.com/'+uid;
 const paths=(await readdir(root,{recursive:true,withFileTypes:true})).filter(x=>x.isFile()&&/\.m?js$/.test(x.name)).map(x=>resolve(x.parentPath,x.name)).filter(x=>x!==entry);
 let deliveries=0;
 const mf=new Miniflare({modules:[entry,...paths].map(path=>({type:'ESModule',path})),modulesRoot:root,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],d1Databases:{DB:'fixture-built-playback'},bindings:{JAC_HOSTING:'cloudflare',JAC_READY:'1',JAC_STREAM_API_TOKEN:'fixture-built-stream-token',PAYROLL_AUTH_KEY:'fixture-built-independent-auth-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,9).toString('base64url')},outboundService:async request=>{
  const url=new URL(request.url);
  if(url.hostname==='api.cloudflare.com'){assert.ok(url.pathname.endsWith('/'+uid+'/token'));assert.equal(request.headers.get('authorization'),'Bearer fixture-built-stream-token');return Response.json({success:true,result:{token:'fixture.built.signature'}});}
  assert.ok(['videodelivery.net','customer-fixture.cloudflarestream.com'].includes(url.hostname),'No R2 originals or other hosts may be read');assert.equal(request.headers.has('authorization'),false);assert.equal(request.headers.has('cookie'),false);deliveries++;
  if(url.pathname.endsWith('/manifest/video.m3u8'))return new Response('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000\n'+delivery+'/manifest/main.m3u8?token=playlist-secret&sig=list-proof\n');
  assert.equal(url.hostname,'customer-fixture.cloudflarestream.com');assert.ok(url.pathname.startsWith('/'+uid+'/'));
  if(url.pathname.endsWith('.m3u8')){assert.equal(url.searchParams.get('sig'),'list-proof');return new Response('#EXTM3U\n#EXT-X-MAP:URI="'+delivery+'/video/init.mp4?token=media-secret&sig=init-proof"\n#EXTINF:4,\n'+delivery+'/video/part.m4s?token=media-secret&sig=part-proof\n#EXT-X-ENDLIST\n');}
  assert.equal(url.searchParams.get('token'),'media-secret');assert.equal(url.searchParams.get('sig'),url.pathname.endsWith('init.mp4')?'init-proof':'part-proof');return new Response(new Uint8Array([1,2,3,4]),{headers:{'Content-Type':'video/mp4'}});
 }});
 try{
  const db=await mf.getD1Database('DB');for(const name of (await readdir('drizzle')).filter(n=>n.endsWith('.sql')).sort())for(const statement of (await readFile('drizzle/'+name,'utf8')).split('--> statement-breakpoint').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();
  const actor='fixture-viewer',sessionID='a'.repeat(64),id='r2_11111111-1111-4111-8111-111111111111',source='originals/'+id.slice(3),revision='2026-10-19T12:00:00Z';
  await db.prepare('INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,media_only,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)').bind(actor,'fixture-viewer','viewer@example.invalid','Ficticio','fixture','[]',1,revision,revision).run();
  await db.prepare('INSERT INTO payroll_sessions(id,user_id,user_version,expires_at,persistent) VALUES(?,?,1,?,1)').bind(sessionID,actor,'').run();
  await db.prepare("INSERT INTO jac_media_r2_connection(id,enabled,version,updated_at) VALUES('jac',1,1,?)").bind(revision).run();
  await db.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,object_key,actor_id,payload_hash,created_at,modified_at) VALUES(?,?,?,?,?,?,?,?,?)').bind(id,'jac_r2_root','Ficticio.mp4','video/mp4',source,actor,'fixture',revision,revision).run();
  await db.prepare("INSERT INTO jac_media_presentations(file_id,source_key,connection_version,stream_uid,stream_status,updated_at) VALUES(?,?,1,?,'ready',?)").bind(id,source,uid,revision).run();
  const value={v:1,id,revision,version:1,expires:Date.now()+3600000,actorID:actor,sessionID},key=await crypto.subtle.importKey('raw',Buffer.alloc(32,9),{name:'AES-GCM'},false,['encrypt']),iv=crypto.getRandomValues(new Uint8Array(12)),encrypted=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(JSON.stringify(value))),lease=Buffer.from(iv).toString('base64url')+'.'+Buffer.from(encrypted).toString('base64url');
  const get=url=>mf.dispatchFetch(new URL(url,'https://built-playback.invalid'));
  const master=await get('/api/media/playback?'+new URLSearchParams({lease,asset:'manifest/video.m3u8'}));assert.equal(master.status,200);const text=await master.text();assert.ok(!text.includes('playlist-secret'));const child=text.split('\n').find(line=>line.startsWith('/api/'));
  const media=await get(child);assert.equal(media.status,200);const playlist=await media.text(),initialization=playlist.match(/URI="([^"]+)"/)[1],fragment=playlist.split('\n').find(line=>line.startsWith('/api/'));assert.ok(!playlist.includes('media-secret'));
  for(const url of [initialization,fragment]){const response=await get(url);assert.equal(response.status,200);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),new Uint8Array([1,2,3,4]));}
  const before=deliveries;await db.prepare('UPDATE payroll_users SET active=0 WHERE id=?').bind(actor).run();assert.equal((await get(fragment)).status,403);assert.equal(deliveries,before);
 }finally{await mf.dispose();}
});
