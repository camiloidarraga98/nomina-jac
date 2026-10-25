import test,{beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {build} from 'esbuild';
import {readFile,readdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

// Independent, in-memory catalogue and identities. No R2/Drive/provider reads.
const sql=new DatabaseSync(':memory:');
for(const name of(await readdir('drizzle')).filter(name=>name.endsWith('.sql')).sort())sql.exec(await readFile('drizzle/'+name,'utf8'));
let beforeQuery,afterQuery,queries=[],external=0;
class Query{
 constructor(text,args=[]){this.text=text;this.args=args;}
 bind(...args){return new Query(this.text,args);}
 execute(){const query=sql.prepare(this.text);return query.columns().length?{results:query.all(...this.args),meta:{changes:0}}:{results:[],meta:{changes:Number(query.run(...this.args).changes)}};}
 async first(){await beforeQuery?.(this);const value=sql.prepare(this.text).get(...this.args)||null;await afterQuery?.(this);return value;}
 async all(){await beforeQuery?.(this);queries.push(this);const results=sql.prepare(this.text).all(...this.args);await afterQuery?.(this);return {results};}
 async run(){await beforeQuery?.(this);return this.execute();}
}
const environment={DB:{prepare:text=>new Query(text),batch:async queries=>{sql.exec('BEGIN');try{const results=queries.map(query=>query.execute());sql.exec('COMMIT');return results;}catch(error){sql.exec('ROLLBACK');throw error;}}},PAYROLL_AUTH_KEY:'recent-photos-independent-fixture-authentication-key',PAYROLL_MAIL_KEY:Buffer.alloc(32,42).toString('base64url')};
globalThis.__recentPhotosEnv=environment;globalThis.__recentPhotosHeaders=new Headers();
globalThis.fetch=async()=>{external++;throw Error('Every external request is blocked.');};
const built=await build({stdin:{resolveDir:process.cwd(),contents:"export * as api from './app/api/media/recent/route';export * from './lib/media-r2-gallery';export * from './lib/payroll-auth-store';export * from './lib/payroll-auth-crypto';export {encryptMail} from './lib/payroll-mail-core';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'recent-private-fixture',setup(b){b.onResolve({filter:/^(cloudflare:workers|next\/headers)$/},args=>({path:args.path,namespace:'fake'}));b.onLoad({filter:/.*/,namespace:'fake'},args=>({contents:args.path==='cloudflare:workers'?'export const env=globalThis.__recentPhotosEnv;':'export const headers=async()=>globalThis.__recentPhotosHeaders;'}));}}]});
const directory=await mkdtemp(resolve('work/media-recent-')),filename=resolve(directory,'fixture.mjs');await writeFile(filename,built.outputFiles[0].contents);const m=await import(pathToFileURL(filename).href);await rm(directory,{recursive:true});
const user=crypto.randomUUID(),calendar=crypto.randomUUID(),stamp='2026-10-25T00:00:00.000Z';
for(const [id,sections] of [[user,['media']],[calendar,['calendar']]])sql.prepare("INSERT INTO payroll_users(id,username,email,name,password_hash,permissions,section_access,created_at,updated_at) VALUES (?,?,?,'Fixture','fixture','[]',?,?,?)").run(id,id,id+'@example.invalid',JSON.stringify(sections),stamp,stamp);
const secret={accountId:'1'.repeat(32),bucket:'jac-fotografia',accessKeyId:'2'.repeat(32),secretAccessKey:'3'.repeat(64)},credentials=await m.encryptMail(secret,environment.PAYROLL_MAIL_KEY);
let token,calendarToken;
beforeEach(async()=>{
 beforeQuery=undefined;afterQuery=undefined;queries=[];external=0;
 sql.exec('DELETE FROM jac_media_operations;DELETE FROM jac_media_r2_entries;DELETE FROM jac_media_r2_connection;DELETE FROM payroll_sessions;DELETE FROM jac_media_connection;');
 sql.prepare('UPDATE payroll_users SET active=1,section_access=? WHERE id=?').run('["media"]',user);
 token=await m.makeSession(user);calendarToken=await m.makeSession(calendar);
 sql.prepare("INSERT INTO jac_media_r2_connection(id,credentials,enabled,version,updated_at) VALUES('jac',?,1,7,?)").run(credentials,stamp);
});
function folder(parent=m.R2_ROOT,id='r2_'+crypto.randomUUID()){
 sql.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,thumbnail_key,actor_id,payload_hash,created_at,modified_at) VALUES (?,?,?, ?,0,\'\',\'\',?,\'folder-fixture\',?,?)').run(id,parent,'Carpeta ficticia','application/vnd.google-apps.folder',user,stamp,stamp);return id;
}
function photo(created,parent=m.R2_ROOT,options={}){
 const request=options.request??crypto.randomUUID(),id='r2_'+request.toLowerCase(),mime=options.mime??'image/jpeg',key=options.key??'originals/'+request.toLowerCase(),size=100,hash='fixture-'+request;
 if(options.operation!==false)sql.prepare('INSERT INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,drive_id,name,mime_type,size,offset,status,connection_version,created_at,expires_at) VALUES (?,?,?,?,\'r2-upload\',?,?,?,?,?,?,?,?,?)').run(request,user,parent,hash,id,'Foto ficticia.jpg',mime,size,options.offset??size,options.status??'ready',options.version??7,created,'2090-01-01T00:00:00.000Z');
 sql.prepare('INSERT INTO jac_media_r2_entries(id,parent_id,name,mime_type,size,object_key,thumbnail_key,actor_id,payload_hash,created_at,modified_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)').run(id,parent,'Foto ficticia.jpg',mime,size,key,options.thumbnail===false?'':'thumbnails/'+request.toLowerCase()+'.jpg',user,hash,created,options.modified??created);return id;
}
function tombstone(id,kind='r2-delete-folder',status='pending'){
 sql.prepare('INSERT INTO jac_media_operations(id,actor_id,parent_id,payload_hash,kind,drive_id,name,mime_type,status,connection_version,created_at,expires_at) VALUES (?,?,?,\'delete-fixture\',?,\'\',\'Ficticio\',\'\',?,7,?,?)').run('r2-delete:'+id,user,id,kind,status,stamp,'2090-01-01T00:00:00.000Z');
}
async function get(session=token,query=''){
 const cookie=session?'__Host-jac_session='+session:'';globalThis.__recentPhotosHeaders=new Headers({cookie,host:'recent.example.invalid'});
 const response=await m.api.GET(new Request('https://recent.example.invalid/api/media/recent'+query,{headers:{cookie}}));
 return {response,data:await response.json()};
}
const listing=query=>query.text.startsWith('WITH authorized AS');

test('recent returns the latest eight global photos with stable ties and folder deep links, never a visited-folder list',async()=>{
 const first=folder(),second=folder(first),expected=[];
 for(let i=0;i<12;i++)expected.push({id:photo('2026-10-25T00:00:'+String(Math.floor(i/2)).padStart(2,'0')+'.000Z',i%2?first:second,{thumbnail:i!==10,request:i===11?crypto.randomUUID().toUpperCase():undefined}),created:'2026-10-25T00:00:'+String(Math.floor(i/2)).padStart(2,'0')+'.000Z'});
 expected.sort((a,b)=>b.created.localeCompare(a.created)||b.id.localeCompare(a.id));
 photo('2090-01-01T00:00:00.000Z',first,{mime:'video/mp4'});
 const {response,data}=await get(token,'?folder='+first+'&limit=999&pageToken=1000000');
 assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'private, no-store, max-age=0');assert.equal(data.collectionID,m.R2_COLLECTION);
 assert.deepEqual(data.items.map(item=>item.id),expected.slice(0,8).map(item=>item.id));assert.ok(data.items.some(item=>item.parentId===second));assert.ok(data.items.every(item=>item.kind==='image'));
 for(const item of data.items)assert.deepEqual(Object.keys(item).sort(),['id','name','mimeType','kind','size','createdAt','modifiedAt','thumbnailAvailable','parentId'].sort());
 const serialized=JSON.stringify(data);for(const forbidden of [secret.secretAccessKey,secret.accessKeyId,credentials,'originals/','thumbnails/','object_key','actor_id','payload_hash'])assert.equal(serialized.includes(forbidden),false);
 assert.equal(external,0);assert.equal(queries.filter(listing).length,2);
 const query=queries.find(listing),plan=sql.prepare('EXPLAIN QUERY PLAN '+query.text).all(...query.args).map(row=>row.detail).join('\n');
 assert.match(plan,/USING INDEX jac_media_r2_entries_recent/);assert.match(plan,/USING INDEX jac_media_operations_media_notify/);
});

test('pending, cancelled, deleted, orphan, wrong-collection and structurally invalid originals are excluded before the eight-photo limit',async()=>{
 const visible=folder(),deleted=folder(),invalidParent=photo(stamp),foreign=folder(m.R2_ROOT,'drive_folder_foreign'),cycle1=folder(),cycle2=folder(cycle1);
 sql.prepare('UPDATE jac_media_r2_entries SET parent_id=? WHERE id=?').run(cycle2,cycle1);
 tombstone(deleted);
 const keep=photo(stamp,visible,{thumbnail:false});
 for(const status of ['pending','cancelled','deleted'])photo('2090-01-01T00:00:00.000Z',visible,{status});
 photo('2090-01-01T00:00:00.000Z',visible,{operation:false});photo('2090-01-01T00:00:00.000Z',visible,{version:6});photo('2090-01-01T00:00:00.000Z',visible,{offset:0});photo('2090-01-01T00:00:00.000Z',visible,{key:'originals/wrong-file'});
 for(const parent of [deleted,'r2_'+crypto.randomUUID(),invalidParent,foreign,cycle1])photo('2090-01-01T00:00:00.000Z',parent);
 const deletedFile=photo('2090-01-01T00:00:00.000Z',visible);tombstone(deletedFile,'r2-delete-file','ready');
 let tooDeep=m.R2_ROOT;for(let i=0;i<23;i++)tooDeep=folder(tooDeep);photo('2090-01-01T00:00:00.000Z',tooDeep);
 const {response,data}=await get();assert.equal(response.status,200);assert.deepEqual(new Set(data.items.map(item=>item.id)),new Set([keep,invalidParent]));assert.equal(data.items.find(item=>item.id===keep).thumbnailAvailable,false);assert.equal(external,0);
});

test('the recent route requires the current session and Photography section and never activates or falls back to Drive',async()=>{
 assert.equal((await get('')).response.status,401);assert.equal((await get(calendarToken)).response.status,403);
 sql.prepare('UPDATE jac_media_r2_connection SET enabled=0').run();sql.prepare("INSERT INTO jac_media_connection(id,credentials,email,version,updated_at) VALUES ('jac','legacy-private-grant','jacmusicestudios@gmail.com',1,?)").run(stamp);
 const inactive=await get();assert.equal(inactive.response.status,409);assert.equal(external,0);assert.equal(sql.prepare('SELECT enabled FROM jac_media_r2_connection').get().enabled,0);assert.equal(sql.prepare('SELECT credentials FROM jac_media_connection').get().credentials,'legacy-private-grant');
});

test('an authorized empty collection is distinct from a revoked session or changed connection',async()=>{
 const empty=await get();assert.equal(empty.response.status,200);assert.deepEqual(empty.data,{items:[],collectionID:m.R2_COLLECTION});
 for(const mutate of [()=>sql.prepare('DELETE FROM payroll_sessions WHERE user_id=?').run(user),()=>sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["calendar"]',user),()=>sql.prepare('UPDATE jac_media_r2_connection SET version=version+1').run(),()=>sql.prepare('UPDATE jac_media_r2_connection SET credentials=?').run('different-private-cipher')]){
  sql.prepare('UPDATE payroll_users SET section_access=? WHERE id=?').run('["media"]',user);sql.prepare('UPDATE jac_media_r2_connection SET credentials=?,version=7').run(credentials);token=await m.makeSession(user);
  let reads=0;beforeQuery=query=>{if(listing(query)&&++reads===2)mutate();};
  const result=await get();assert.equal(result.response.status,403);assert.equal(result.data.items,undefined);beforeQuery=undefined;
 }
 assert.equal(external,0);
});

test('a folder tombstone during metadata work removes its photos from the final snapshot',async()=>{
 const target=folder(),other=folder(),removed=photo('2026-10-25T00:02:00.000Z',target),keep=photo(stamp,other);let reads=0;
 beforeQuery=query=>{if(listing(query)&&++reads===2)tombstone(target);};
 const {response,data}=await get();assert.equal(response.status,200);assert.deepEqual(data.items.map(item=>item.id),[keep]);assert.equal(data.items.some(item=>item.id===removed),false);assert.equal(external,0);
});

test('a revoked account after the final SQL read cannot be serialized by the recent API',async()=>{
 photo(stamp);let reads=0;afterQuery=query=>{if(listing(query)&&++reads===2)sql.prepare('UPDATE payroll_users SET active=0 WHERE id=?').run(user);};
 const {response,data}=await get();assert.equal(response.status,403);assert.equal(data.items,undefined);assert.equal(external,0);
});
