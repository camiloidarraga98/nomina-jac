// Local migration operator. Private RSA key, capability and decrypted content
// live only in this process. Never write them, pass them as arguments, or log.
import {generateKeyPairSync,randomBytes,privateDecrypt,createDecipheriv,createHash,constants} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createInterface} from 'node:readline';
import {spawn,spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {unzipSync} from 'fflate';

const target='https://jac-nomina.jacmusic.workers.dev';
const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:3072});
const recipient={...publicKey.export({format:'jwk'}),alg:'RSA-OAEP-256',key_ops:['encrypt'],ext:true};
const token=randomBytes(32).toString('base64url');
const expires=new Date(Date.now()+110*60*1000).toISOString();
const wrangler=resolve('node_modules/wrangler/bin/wrangler.js');
const config=resolve('deploy/cloudflare/wrangler.json');
const hash=b=>createHash('sha256').update(b).digest('hex');
const canonical=rows=>rows.map(r=>JSON.stringify(Object.fromEntries(Object.keys(r).sort().map(k=>[k,r[k]])))).sort().join('\n');
let configured=false;
if(process.stdin.isTTY){spawnSync('stty',['-echo'],{stdio:'inherit'});process.on('exit',()=>spawnSync('stty',['echo'],{stdio:'inherit'}));}
function report(value){process.stdout.write(JSON.stringify(value)+'\n');}
function open(bytes){
 const envelope=JSON.parse(Buffer.from(bytes).toString('utf8'));
 if(envelope.format!=='jac-transfer-v1')throw Error('Formato de copia no válido.');
 const raw=privateDecrypt({key:privateKey,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(envelope.key,'base64'));
 const encrypted=Buffer.from(envelope.data,'base64'),decipher=createDecipheriv('aes-256-gcm',raw,Buffer.from(envelope.iv,'base64'));
 decipher.setAuthTag(encrypted.subarray(-16));const clear=Buffer.concat([decipher.update(encrypted.subarray(0,-16)),decipher.final()]);raw.fill(0);
 try{return JSON.parse(clear.toString('utf8'));}finally{clear.fill(0);}
}
async function secretBulk(values){
 await new Promise((resolvePromise,reject)=>{
  const child=spawn(process.execPath,[wrangler,'secret','bulk','--config',config],{cwd:process.cwd(),stdio:['pipe','pipe','pipe'],env:{...process.env,WRANGLER_SEND_METRICS:'false',WRANGLER_LOG:'none',WRANGLER_WRITE_LOGS:'false'}});
  // Deliberately consume without logging third-party output around secrets.
  child.stdout.on('data',()=>{});child.stderr.on('data',()=>{});child.on('error',()=>reject(Error('No pudimos abrir Wrangler.')));
  child.on('exit',code=>code===0?resolvePromise():reject(Error('Cloudflare no confirmó los secretos; código '+code+'.')));
  child.stdin.end(JSON.stringify(values));
 });
}
async function api(body,query='',extra={},binary=false){
 const response=await fetch(target+'/_jac/transfer'+query,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':binary?'application/octet-stream':'application/json',...extra},body:binary?body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(120000)});
 if(!response.ok)throw Error('El destino rechazó el traslado; HTTP '+response.status+'. No se modificó el origen.');return response.json();
}
async function configure(){await secretBulk({JAC_TRANSFER_TOKEN:token,JAC_TRANSFER_EXPIRES:expires});configured=true;}
async function restore(path){
 if(!configured)throw Error('Primero configura el destino.');
 const zipped=await readFile(path);if(zipped.length>270*1024*1024)throw Error('Copia demasiado extensa.');
 const entries=unzipSync(zipped,{filter:file=>file.originalSize<=32*1024*1024});zipped.fill(0);
 const db=open(entries['database.json']),secrets=open(entries['secrets.json']);
 if(db.kind!=='database'||secrets.kind!=='secrets'||Object.keys(secrets.values).sort().join(',')!=='PAYROLL_AUTH_KEY,PAYROLL_MAIL_KEY')throw Error('Copia incompleta.');
 if(Object.values(secrets.values).some(v=>typeof v!=='string'||v.length<32))throw Error('Las claves de ejecución están incompletas.');
 const inventory=await api({action:'tables'});
 const sourceNames=db.tables.map(t=>t.name).sort(),targetNames=inventory.tables.map(t=>t.name).sort();
 if(JSON.stringify(sourceNames)!==JSON.stringify(targetNames))throw Error('Los esquemas de origen y destino no coinciden.');
 await secretBulk(secrets.values);for(const key of Object.keys(secrets.values))delete secrets.values[key];
 await api({action:'clear',confirmation:'jac-nomina-staging'});
 let rowCount=0;
 for(const table of db.tables){
  for(let offset=0;offset<table.rows.length;offset+=20){const rows=table.rows.slice(offset,offset+20);await api({action:'rows',table:table.name,rows});rowCount+=rows.length;}
 }
 await api({action:'sequences',sequences:db.sequences});
 const fingerprints=await api({action:'fingerprints'});
 for(const table of db.tables){const actual=fingerprints.tables.find(t=>t.name===table.name);if(!actual||actual.count!==table.rows.length||actual.sha256!==hash(canonical(table.rows)))throw Error('La comprobación de integridad de la base no coincide.');}
 report({phase:'database',tables:db.tables.length,rows:rowCount,integrity:true});
 const groups=new Map();
 for(const [name,bytes] of Object.entries(entries)){
  const match=/^objects\/(\d+)\/(\d+)\.json$/.exec(name);if(!match)continue;
  const group=groups.get(match[1])||[];group.push({offset:Number(match[2]),bytes});groups.set(match[1],group);
 }
 let files=0,totalBytes=0;
 for(const chunks of groups.values()){
  chunks.sort((a,b)=>a.offset-b.offset);const parts=[];let metadata,offset=0;
  for(const chunk of chunks){const item=open(chunk.bytes);if(item.kind!=='object'||item.offset!==offset||chunk.offset!==offset||metadata&&(metadata.key!==item.key||metadata.etag!==item.etag||metadata.size!==item.size))throw Error('Documento incompleto o modificado.');metadata??=item;const part=Buffer.from(item.bytes,'base64');parts.push(part);offset+=part.length;}
  if(!metadata||offset!==metadata.size)throw Error('El tamaño del documento no coincide.');
  const bytes=Buffer.concat(parts),sha256=hash(bytes),meta=Buffer.from(JSON.stringify({httpMetadata:metadata.httpMetadata,customMetadata:metadata.customMetadata})).toString('base64');
  const result=await api(bytes,'?action=object&key='+encodeURIComponent(metadata.key),{'Content-Length':String(bytes.length),'X-JAC-SHA256':sha256,'X-JAC-Metadata':meta},true);
  if(result.size!==bytes.length||result.sha256!==sha256)throw Error('No se confirmó la integridad del documento.');
  files++;totalBytes+=bytes.length;bytes.fill(0);parts.forEach(p=>p.fill(0));report({phase:'documents',files,bytes:totalBytes});
 }
 const manifest=JSON.parse(Buffer.from(entries['manifest.json']).toString('utf8'));
 if(files!==manifest.files)throw Error('Faltan documentos en la copia.');
 report({phase:'complete',tables:db.tables.length,rows:rowCount,files,bytes:totalBytes,keys:2,stagingOnly:true});
}
report({ready:true,publicKey:recipient,expires,fingerprint:hash(JSON.stringify(recipient))});
for await(const line of createInterface({input:process.stdin,crlfDelay:Infinity})){
 try{
  const command=JSON.parse(line);
  if(command.action==='configure'){await configure();report({configured:true});}
  else if(command.action==='import'&&typeof command.path==='string')await restore(command.path);
  else if(command.action==='inventory')report(await api({action:'tables'}));
  else if(command.action==='stop')break;
  else throw Error('Comando no válido.');
 }catch(error){report({error:error.message});}
}
