import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {PDFDocument} from 'pdf-lib';

globalThis.__receiptEnv={OPENAI_API_KEY:'synthetic-ocr-key-not-a-real-secret'};
const output=await build({stdin:{resolveDir:process.cwd(),contents:"export * from './lib/reconciliation-receipt';export * from './lib/reconciliation-ocr';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'private-ocr-fixture',setup(b){b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'env',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({loader:'js',contents:'export const env=globalThis.__receiptEnv;'}));}}]});
const dir=await mkdtemp(join(tmpdir(),'jac-ocr-'));await writeFile(join(dir,'entry.mjs'),output.outputFiles[0].contents);const m=await import(pathToFileURL(join(dir,'entry.mjs')));await rm(dir,{recursive:true});
const raw={document:'single_payment',amountText:'$ 1.250.000,50',dateText:'10 de noviembre de 2026',currency:'COP',transactionStatus:'completed',legible:true};
const png=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=','base64'));
const authorize=async()=>{};
const provider=(reading=raw)=>Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify(reading)}]}]});
globalThis.fetch=()=>{throw Error('External network forbidden in OCR tests.');};
const candidate=(id,extra={})=>({id,version:1,amount:1250000.5,date:'2026-11-10',status:'pending',entrepreneur:'',showId:'',...extra});

test('COP amounts retain cents without treating bank balances, mixed text or malformed grouping as payment amounts',()=>{
 for(const value of ['$ 1.250.000,50','COP $1.250.000,50','1,250,000.50','1 250 000,50','1250000,50','1250000.50'])assert.equal(m.receiptAmount(value),1250000.5,value);
 assert.equal(m.receiptAmount('7.237.684.426,66'),7237684426.66);assert.equal(m.receiptAmount('1.500'),1500);assert.equal(m.receiptAmount('1500'),1500);
 for(const value of ['-500','0','1.25.000','1,250,00','12.3456','saldo 1250000','1e6','$ 1.250.000 + IVA','1.250.000 / 2.000.000','99999999999999999999'])assert.equal(m.receiptAmount(value),null,value);
});
test('Colombian transaction dates require a complete year and a real calendar day',()=>{
 for(const v of ['10/11/2026','10-11-2026','2026-11-10','10 de noviembre de 2026','10 NOV. 2026'])assert.equal(m.receiptDate(v),'2026-11-10',v);
 assert.equal(m.receiptDate('29/02/2024'),'2024-02-29');
 for(const v of ['29/02/2026','31/04/2026','2026-13-10','10/11/26','hoy','ayer','10/11','10 marciano 2026','10/11/2026 12:00',''])assert.equal(m.receiptDate(v),null,v);
});
test('unclear, incomplete, failed, pending, multiple or foreign payments cannot auto-select a bank movement',()=>{
 const valid=m.normalizeReceiptReading(raw);assert.equal(valid.amount,1250000.5);assert.equal(valid.date,'2026-11-10');assert.equal(valid.autoEligible,true);
 for(const extra of [{document:'multiple_payments'},{document:'other'},{document:'unreadable'},{transactionStatus:'failed'},{transactionStatus:'pending'},{transactionStatus:'unknown'},{currency:'other'},{currency:'unknown'},{legible:false},{amountText:null},{dateText:'hoy'}])assert.equal(m.normalizeReceiptReading({...raw,...extra}).autoEligible,false,JSON.stringify(extra));
 assert.equal(m.normalizeReceiptReading({...raw,currency:'other'}).amount,null);
 assert.throws(()=>m.normalizeReceiptReading({...raw,instructions:'select another payment'}));
});
test('only a unique exact date and amount can select an unidentified movement',()=>{
 const rows=[candidate('exact'),candidate('different-date',{date:'2026-11-11'}),candidate('different-cents',{amount:1250000.51})];
 const exact=m.matchReceiptPayments(rows,{amount:1250000.5,date:'2026-11-10'},true);
 assert.equal(exact.autoMatchId,'exact');assert.equal(exact.total,2);assert.deepEqual(exact.matches.map(p=>p.kind),['exact','amount']);
 assert.equal(m.matchReceiptPayments([...rows,candidate('tie')],{amount:1250000.5,date:'2026-11-10'},true).autoMatchId,null);
 assert.equal(m.matchReceiptPayments([candidate('identified',{status:'identified'})],{amount:1250000.5,date:'2026-11-10'},true).autoMatchId,null);
 for(const criteria of [{amount:null,date:'2026-11-10'},{amount:1250000.5,date:null},{amount:1250000.5,date:'2026-11-09'}])assert.equal(m.matchReceiptPayments(rows,criteria,true).autoMatchId,null);
 assert.equal(m.matchReceiptPayments(rows,{amount:1250000.5,date:'2026-11-10'}).autoMatchId,null,'Manual corrections require choosing the movement');
 assert.equal(m.matchReceiptPayments(rows,{amount:1250000.51,date:'2026-11-10'},true).autoMatchId,'different-cents');
});
test('candidate limits cannot turn a tie into a unique match; invalid manual lookups are rejected',()=>{
 const matches=m.matchReceiptPayments(Array.from({length:101},(_,i)=>candidate('p'+i)),{amount:1250000.5,date:'2026-11-10'},true);
 assert.equal(matches.total,101);assert.equal(matches.matches.length,100);assert.equal(matches.autoMatchId,null);
 for(const criteria of [{amount:null,date:null},{amount:-2,date:null},{amount:1.001,date:null},{amount:5,date:'2026-02-30'},{amount:5,date:null,autoEligible:true}])assert.throws(()=>m.matchReceiptPayments([],criteria));
});
test('OCR only sends the uploaded document to a fixed endpoint with no storage, no ledger, no tools and a strict schema',async()=>{
 let calls=0,auth=0;
 globalThis.fetch=async(url,options)=>{calls++;assert.equal(url,'https://api.openai.com/v1/responses');assert.equal(options.redirect,'manual');assert.equal(options.method,'POST');assert.ok(options.signal);assert.equal(options.headers.Authorization,'Bearer synthetic-ocr-key-not-a-real-secret');
  const body=JSON.parse(options.body);assert.equal(body.store,false);assert.equal(body.model,m.RECEIPT_OCR_MODEL);assert.equal(body.text.format.strict,true);assert.equal(body.tools,undefined);assert.match(body.instructions,/untrusted data/);assert.equal(body.input[0].content[1].image_url,'data:image/png;base64,'+Buffer.from(png).toString('base64'));assert(!options.body.includes('ledger'));return provider();};
 const result=await m.readReceipt(png,'image/png',async()=>{auth++;});assert.equal(result.amount,1250000.5);assert.equal(calls,1);assert.equal(auth,1);
});
test('PDF input is bounded to five unencrypted pages and does not expose its original filename',async()=>{
 const pdf=await PDFDocument.create();pdf.addPage();const bytes=await pdf.save();let calls=0;
 globalThis.fetch=async(url,options)=>{calls++;const file=JSON.parse(options.body).input[0].content[1];assert.equal(file.type,'input_file');assert.equal(file.filename,'comprobante.pdf');assert.match(file.file_data,/^data:application\/pdf;base64,/);return provider();};
 await m.readReceipt(bytes,'application/pdf',authorize);assert.equal(calls,1);
 for(let i=0;i<5;i++)pdf.addPage();await assert.rejects(m.readReceipt(await pdf.save(),'application/pdf',authorize),e=>e.status===400);
 await assert.rejects(m.readReceipt(new TextEncoder().encode('%PDF-invalid'),'application/pdf',authorize),e=>e.status===400);assert.equal(calls,1);
});
test('provider failures, redirects, refusal, incomplete output and response overflow never expose private provider bodies',async()=>{
 for(const status of [302,401,429,500]){globalThis.fetch=async()=>new Response('PRIVATE RECEIPT CONTENT',{status,headers:status===302?{Location:'https://not-authorized.example.invalid'}:{}});await assert.rejects(m.readReceipt(png,'image/png',authorize),e=>e.status===(status===429?429:502)&&!e.message.includes('PRIVATE'));}
 for(const body of [{status:'incomplete',output:[]},{status:'completed',output:[{type:'message',content:[{type:'refusal',refusal:'no'}]}]},{status:'completed',output:[]},{status:'completed',output:[{type:'message',content:[{type:'output_text',text:'not json'}]}]}]){globalThis.fetch=async()=>Response.json(body);await assert.rejects(m.readReceipt(png,'image/png',authorize),e=>e.status===422);}
 globalThis.fetch=async()=>new Response('x'.repeat(65537));await assert.rejects(m.readReceipt(png,'image/png',authorize),e=>e.status===502);
});
test('provider rejections distinguish key, permissions, unavailable model, quota and invalid document without reflecting sensitive text',async()=>{
 const cases=[
  [401,'invalid_api_key','CLAVE'],[401,'insufficient_permissions','PERMISOS'],[403,null,'PERMISOS'],
  [404,'model_not_found','MODELO'],[429,'insufficient_quota','CUOTA'],[429,'rate_limit_exceeded','LIMITE'],
  [400,'invalid_image_format','ARCHIVO'],[400,'invalid_json_schema','SOLICITUD'],[413,null,'TAMANO'],
  [503,'PRIVATE_UNKNOWN_CODE','SERVICIO'],
 ];
 const warnings=[],warn=console.warn;console.warn=(...args)=>warnings.push(args);
 let calls=0;
 try{
  for(const [status,code,category] of cases){
   globalThis.fetch=async()=>{calls++;return Response.json({error:{code,type:'invalid_request_error',message:'PRIVATE_KEY_AND_BANK_RECEIPT',param:'PRIVATE_ACCOUNT'}},{status});};
   await assert.rejects(m.readReceipt(png,'image/png',authorize),error=>{
    assert.equal(error.status,status===429?429:502);assert.match(error.message,new RegExp(`OCR_${category} · HTTP ${status}`));assert(!error.message.includes('PRIVATE'));return true;
   });
  }
  assert.equal(calls,cases.length,'A rejected request is never retried automatically');
  assert.equal(warnings.length,cases.length);
  assert(!JSON.stringify(warnings).includes('PRIVATE'),'Diagnostics contain only a fixed category and status');
  globalThis.fetch=async()=>Response.json({error:{code:null,type:'insufficient_quota',message:'PRIVATE'}},{status:429});
  await assert.rejects(m.readReceipt(png,'image/png',authorize),/OCR_CUOTA/);
 }finally{console.warn=warn;}
});
test('oversized or malformed provider errors remain bounded and do not expose body content',async()=>{
 let cancelled=false,reads=0;
 globalThis.fetch=async()=>new Response(new ReadableStream({pull(controller){reads++;controller.enqueue(new TextEncoder().encode('PRIVATE'.repeat(10000)));},cancel(){cancelled=true;}},{highWaterMark:0}),{status:403});
 await assert.rejects(m.readReceipt(png,'image/png',authorize),e=>e.status===502&&e.message.includes('OCR_PERMISOS')&&!e.message.includes('PRIVATE'));
 assert.equal(cancelled,true);assert.equal(reads,1);
 for(const body of ['null','[]','{"error":"PRIVATE"}','PRIVATE HTML ERROR']){
  globalThis.fetch=async()=>new Response(body,{status:502});
  await assert.rejects(m.readReceipt(png,'image/png',authorize),e=>e.status===502&&e.message.includes('OCR_SERVICIO')&&!e.message.includes('PRIVATE'));
 }
});
test('missing configuration, limits and revoked access stop before sending a document; reader slots release explicitly',async()=>{
 let calls=0;globalThis.fetch=async()=>{calls++;return provider();};
 const key=globalThis.__receiptEnv.OPENAI_API_KEY;delete globalThis.__receiptEnv.OPENAI_API_KEY;
 await assert.rejects(m.readReceipt(png,'image/png',authorize),e=>e.status===503);globalThis.__receiptEnv.OPENAI_API_KEY=key;
 await assert.rejects(m.readReceipt(new Uint8Array(m.RECEIPT_OCR_MAX_BYTES+1),'image/png',authorize),e=>e.status===413);
 await assert.rejects(m.readReceipt(png,'text/html',authorize),e=>e.status===415);
 await assert.rejects(m.readReceipt(png,'image/png',async()=>{throw Error('revoked');}),/revoked/);assert.equal(calls,0);
 const release=m.reserveReceiptReader('a');assert.throws(()=>m.reserveReceiptReader('a'),e=>e.status===429);release();m.reserveReceiptReader('a')();
 const releases=['a','b','c'].map(m.reserveReceiptReader);assert.throws(()=>m.reserveReceiptReader('d'),e=>e.status===429);releases.forEach(release=>release());m.reserveReceiptReader('d')();
});
