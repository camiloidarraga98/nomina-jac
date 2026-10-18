import {createHash,timingSafeEqual} from 'node:crypto';

export type TransferEnv={DB:D1Database;BUCKET:R2Bucket;PAYROLL_AUTH_KEY?:string;PAYROLL_MAIL_KEY?:string;JAC_READY?:string;JAC_TRANSFER_TOKEN?:string;JAC_TRANSFER_EXPIRES?:string;JAC_TRANSFER_PUBLIC_KEY?:string};
const headers={'Cache-Control':'private, no-store','X-Robots-Tag':'noindex, nofollow','Content-Type':'application/json'};
const digest=(s:string)=>createHash('sha256').update(s).digest();
function authorized(req:Request,e:TransferEnv){
 const expiry=Date.parse(e.JAC_TRANSFER_EXPIRES||'');
 const token=/^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.get('Authorization')||'')?.[1];
 return req.method==='POST'&&!req.headers.has('Origin')&&!!e.JAC_TRANSFER_TOKEN&&e.JAC_TRANSFER_TOKEN.length===43&&!!token&&Number.isFinite(expiry)&&expiry>Date.now()&&expiry-Date.now()<=2*60*60*1000&&timingSafeEqual(digest(token),digest(e.JAC_TRANSFER_TOKEN));
}
const missing=()=>new Response(null,{status:404,headers});
async function input(req:Request){
 if(!/^application\/json(?:;|$)/i.test(req.headers.get('Content-Type')||''))throw Error('input');
 const reader=req.body?.getReader();if(!reader)throw Error('input');const chunks:Uint8Array[]=[];let size=0;
 while(true){const r=await reader.read();if(r.done)break;size+=r.value.byteLength;if(size>2*1024*1024){await reader.cancel();throw Error('input');}chunks.push(r.value);}
 const bytes=new Uint8Array(size);let n=0;for(const c of chunks){bytes.set(c,n);n+=c.length;}return JSON.parse(new TextDecoder().decode(bytes));
}
const quote=(s:string)=>'"'+s.replaceAll('"','""')+'"';
const internal=(s:string)=>s.startsWith('sqlite_')||s.startsWith('_cf_')||s==='d1_migrations'||s==='__drizzle_migrations';
async function tables(db:D1Database){return (await db.prepare("SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name").all<{name:string;sql:string}>()).results.filter(t=>!internal(t.name));}
function base64(bytes:Uint8Array){let s='';for(let n=0;n<bytes.length;n+=8192)s+=String.fromCharCode(...bytes.subarray(n,n+8192));return btoa(s);}
async function seal(value:unknown,e:TransferEnv){
 const publicKey=JSON.parse(e.JAC_TRANSFER_PUBLIC_KEY||'null');
 if(publicKey?.kty!=='RSA'||publicKey.d||publicKey.alg!=='RSA-OAEP-256')throw Error('key');
 const rsa=await crypto.subtle.importKey('jwk',publicKey,{name:'RSA-OAEP',hash:'SHA-256'},false,['encrypt']);
 const raw=crypto.getRandomValues(new Uint8Array(32)),iv=crypto.getRandomValues(new Uint8Array(12));
 const key=await crypto.subtle.importKey('raw',raw,'AES-GCM',false,['encrypt']);
 const bytes=new TextEncoder().encode(JSON.stringify(value));if(bytes.length>16*1024*1024)throw Error('size');
 const data=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,bytes);
 const wrapped=await crypto.subtle.encrypt({name:'RSA-OAEP'},rsa,raw);
 return Response.json({format:'jac-transfer-v1',key:base64(new Uint8Array(wrapped)),iv:base64(iv),data:base64(new Uint8Array(data))},{headers});
}

// This route is disabled unless a short-lived runtime capability and a pinned
// recipient public key have both been configured. It never returns plaintext
// records or keys, accepts SQL, changes source data, or calls external services.
export async function sourceTransfer(req:Request,e:TransferEnv,founderSession:()=>Promise<boolean>){
 const expiry=Date.parse(e.JAC_TRANSFER_EXPIRES||'');
 if(req.method!=='POST'||req.headers.get('Origin')!==new URL(req.url).origin||!e.JAC_TRANSFER_PUBLIC_KEY||!Number.isFinite(expiry)||expiry<=Date.now()||expiry-Date.now()>2*60*60*1000||!await founderSession())return missing();
 try{
  const p=await input(req);
  const output=async(value:unknown)=>{if(!await founderSession())return missing();return seal(value,e);};
  if(p.action==='database'){
   const list=await tables(e.DB);if(list.length>45)throw Error('tables');
   const results=await e.DB.batch<Record<string,unknown>>(list.map(t=>e.DB.prepare('SELECT * FROM '+quote(t.name))));
   const data=list.map((t,i)=>({name:t.name,sql:t.sql,rows:results[i].results}));
   const sequences=(await e.DB.prepare('SELECT name,seq FROM sqlite_sequence').all<{name:string;seq:number}>()).results.filter(s=>list.some(t=>t.name===s.name));
   return await output({kind:'database',tables:data,sequences});
  }
  if(p.action==='secrets'){
   if(!e.PAYROLL_AUTH_KEY||!e.PAYROLL_MAIL_KEY)throw Error('keys');
   return await output({kind:'secrets',values:{PAYROLL_AUTH_KEY:e.PAYROLL_AUTH_KEY,PAYROLL_MAIL_KEY:e.PAYROLL_MAIL_KEY}});
  }
  if(p.action==='objects'){
   if(p.cursor!==undefined&&(typeof p.cursor!=='string'||p.cursor.length>4096))throw Error('cursor');
   const page=await e.BUCKET.list({limit:100,cursor:p.cursor});
   return await output({kind:'objects',objects:page.objects.map(o=>({key:o.key,size:o.size,etag:o.etag})),cursor:page.truncated?page.cursor:null});
  }
  if(p.action==='object'){
   if(typeof p.key!=='string'||p.key.length>1024||typeof p.etag!=='string'||!Number.isSafeInteger(p.offset)||p.offset<0)throw Error('object');
   const object=await e.BUCKET.get(p.key,{range:{offset:p.offset,length:1024*1024},onlyIf:{etagMatches:p.etag}});
   if(!object||!('body' in object)||object.etag!==p.etag)throw Error('changed');
   const bytes=new Uint8Array(await object.arrayBuffer());
   return await output({kind:'object',key:object.key,size:object.size,etag:object.etag,offset:p.offset,httpMetadata:object.httpMetadata,customMetadata:object.customMetadata,bytes:base64(bytes)});
  }
  return missing();
 }catch{return new Response(null,{status:409,headers});}
}

// The import capability works only while the independent deployment is blocked.
// It is never a user-facing feature and cannot access other accounts/buckets.
export async function targetTransfer(req:Request,e:TransferEnv){
 if(e.JAC_READY==='1'||!authorized(req,e))return missing();
 try{
  const url=new URL(req.url);
  if(url.searchParams.get('action')==='object'){
   const key=url.searchParams.get('key'),size=Number(req.headers.get('Content-Length')),sha=req.headers.get('X-JAC-SHA256');
   if(!key||key.length>1024||!Number.isSafeInteger(size)||size<0||size>100*1024*1024||!sha||!/^[a-f0-9]{64}$/.test(sha)||!req.body)throw Error('object');
   const meta=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(req.headers.get('X-JAC-Metadata')||''),c=>c.charCodeAt(0))));
   const result=await e.BUCKET.put(key,req.body,{httpMetadata:meta.httpMetadata,customMetadata:meta.customMetadata,sha256:Uint8Array.from(sha.match(/../g)!,h=>parseInt(h,16))});
   if(!result||result.size!==size)throw Error('size');
   return Response.json({ok:true,size:result.size,sha256:sha},{headers});
  }
  const p=await input(req),list=await tables(e.DB);
  if(p.action==='tables'){
   const counts=await e.DB.batch<{n:number}>(list.map(t=>e.DB.prepare('SELECT count(*) AS n FROM '+quote(t.name))));
   return Response.json({tables:list.map((t,i)=>({name:t.name,sql:t.sql,count:counts[i].results[0].n}))},{headers});
  }
  if(p.action==='clear'){
   if(p.confirmation!=='jac-nomina-staging')throw Error('confirmation');
   await e.DB.batch(list.map(t=>e.DB.prepare('DELETE FROM '+quote(t.name))));
   return Response.json({ok:true},{headers});
  }
  if(p.action==='rows'){
   if(!list.some(t=>t.name===p.table)||!Array.isArray(p.rows)||p.rows.length>20)throw Error('table');
   const columns=(await e.DB.prepare('PRAGMA table_info('+quote(p.table)+')').all<{name:string}>()).results.map(c=>c.name);
   const writes=p.rows.map((row:Record<string,unknown>)=>{
    if(!row||typeof row!=='object'||Object.keys(row).length!==columns.length||columns.some(c=>!Object.hasOwn(row,c)||!['string','number'].includes(typeof row[c])&&row[c]!==null))throw Error('row');
    return e.DB.prepare('INSERT INTO '+quote(p.table)+' ('+columns.map(quote).join(',')+') VALUES ('+columns.map(()=>'?').join(',')+')').bind(...columns.map(c=>row[c]));
   });
   if(writes.length)await e.DB.batch(writes);return Response.json({ok:true,rows:writes.length},{headers});
  }
  if(p.action==='sequences'){
   if(!Array.isArray(p.sequences)||p.sequences.length>45||p.sequences.some((s:{name:string;seq:number})=>!list.some(t=>t.name===s.name)||!Number.isSafeInteger(s.seq)||s.seq<0))throw Error('sequences');
   const writes=p.sequences.flatMap((s:{name:string;seq:number})=>[e.DB.prepare('DELETE FROM sqlite_sequence WHERE name=?').bind(s.name),e.DB.prepare('INSERT INTO sqlite_sequence(name,seq) VALUES (?,?)').bind(s.name,s.seq)]);
   if(writes.length)await e.DB.batch(writes);
   return Response.json({ok:true},{headers});
  }
  if(p.action==='fingerprints'){
   const results=await e.DB.batch<Record<string,unknown>>(list.map(t=>e.DB.prepare('SELECT * FROM '+quote(t.name))));
   const hashes=list.map((t,i)=>{const rows=results[i].results.map(r=>JSON.stringify(Object.fromEntries(Object.keys(r).sort().map(k=>[k,r[k]])))).sort();return {name:t.name,count:rows.length,sha256:createHash('sha256').update(rows.join('\n')).digest('hex')};});
   return Response.json({tables:hashes},{headers});
  }
  return missing();
 }catch{return new Response(null,{status:409,headers});}
}
