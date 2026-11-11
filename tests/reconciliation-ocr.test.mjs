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
test('thermal receipt month-first dates retain the printed day and agree with independent day-first readings',async()=>{
 for(const [i,month] of ['ENE','FEB','MAR','ABR','MAY','JUN','JUL','AGO','SEP','OCT','NOV','DIC'].entries()){
  const expected=`2026-${String(i+1).padStart(2,'0')}-07`;
  for(const text of [`${month} 07 2026`,`${month.toLowerCase()}. 7, 2026`,`7 ${month} 2026`])assert.equal(m.receiptDate(text),expected,text);
 }
 for(const text of ['ENE 00 2026','ENE 32 2026','FEB 29 2026','ABR 31 2026','ENE 07 26','ENE 07','JAN 07 2026','ENE 07 2026 16:13:35','ENE 07 2026 / FEB 07 2026'])assert.equal(m.receiptDate(text),null,text);
 assert.equal(m.receiptDate('02/01/2026'),'2026-01-02');
 let calls=0;
 globalThis.fetch=async()=>provider({...raw,dateText:calls++===0?'ENE 07 2026':'07/01/2026'});
 const result=await m.readReceipt(png,'image/png',authorize);
 assert.equal(calls,2);assert.equal(result.date,'2026-01-07');assert.equal(result.autoEligible,true);
 calls=0;globalThis.fetch=async()=>provider({...raw,dateText:calls++===0?'ENE 07 2026':'07/04/2026'});
 const disagreement=await m.readReceipt(png,'image/png',authorize);assert.equal(disagreement.date,null);assert.equal(disagreement.autoEligible,false);
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
 const result=await m.readReceipt(png,'image/png',async()=>{auth++;});assert.equal(result.amount,1250000.5);assert.equal(calls,2);assert.equal(auth,2);
});
test('PDF input is bounded to five unencrypted pages and does not expose its original filename',async()=>{
 const pdf=await PDFDocument.create();pdf.addPage();const bytes=await pdf.save();let calls=0;
 globalThis.fetch=async(url,options)=>{calls++;const file=JSON.parse(options.body).input[0].content[1];assert.equal(file.type,'input_file');assert.equal(file.filename,'comprobante.pdf');assert.match(file.file_data,/^data:application\/pdf;base64,/);return provider();};
 await m.readReceipt(bytes,'application/pdf',authorize);assert.equal(calls,2);
 for(let i=0;i<5;i++)pdf.addPage();await assert.rejects(m.readReceipt(await pdf.save(),'application/pdf',authorize),e=>e.status===400);
 await assert.rejects(m.readReceipt(new TextEncoder().encode('%PDF-invalid'),'application/pdf',authorize),e=>e.status===400);assert.equal(calls,2);
});
test('independent verification clears conflicting dates and amounts instead of choosing a plausible payment',async()=>{
 let calls=0;const requests=[];
 globalThis.fetch=async(url,options)=>{calls++;requests.push(JSON.parse(options.body));return provider(calls===1?{...raw,dateText:'14/08/2026'}:{...raw,dateText:'19/03/2026'});};
 const result=await m.readReceipt(png,'image/png',authorize);
 assert.equal(calls,2);assert.equal(result.date,null);assert.equal(result.dateText,null);assert.equal(result.amount,1250000.5);assert.equal(result.autoEligible,false);
 assert.match(result.warnings.join(' '),/no coinciden en la fecha/);
 assert(!JSON.stringify(requests[1]).includes('14/08/2026'),'The verification never receives the first answer');
 assert.notEqual(requests[0].instructions,requests[1].instructions);
 assert.deepEqual(requests[0].input[0].content[1],requests[1].input[0].content[1],'Both readings use only the same selected receipt');
 const first=m.normalizeReceiptReading(raw);
 const amounts=m.verifyReceiptReadings(first,m.normalizeReceiptReading({...raw,amountText:'1.250.000,51'}));
 assert.equal(amounts.amount,null);assert.equal(amounts.amountText,null);assert.equal(amounts.date,'2026-11-10');assert.equal(amounts.autoEligible,false);
 const same=m.verifyReceiptReadings(first,m.normalizeReceiptReading({...raw,amountText:'1250000.50',dateText:'2026-11-10'}));
 assert.equal(same.autoEligible,true);assert.equal(same.amount,1250000.5);assert.equal(same.date,'2026-11-10');
 for(const extra of [{legible:false},{document:'multiple_payments'},{currency:'unknown'},{transactionStatus:'pending'},{dateText:null}])assert.equal(m.verifyReceiptReadings(first,m.normalizeReceiptReading({...raw,...extra})).autoEligible,false);
});
test('verification is bounded, cancelled or revoked access prevents the second request and failures are not retried',async()=>{
 let calls=0,checks=0;const controller=new AbortController();
 globalThis.fetch=async()=>{calls++;controller.abort();return provider();};
 await assert.rejects(m.readReceipt(png,'image/png',authorize,controller.signal),e=>e.status===502);assert.equal(calls,1);
 calls=0;globalThis.fetch=async()=>{calls++;return provider();};
 await assert.rejects(m.readReceipt(png,'image/png',async()=>{if(++checks===2)throw Error('access-revoked');}),/access-revoked/);assert.equal(calls,1);
 calls=0;globalThis.fetch=async()=>{calls++;return calls===1?provider():Response.json({error:{code:'invalid_api_key'}},{status:401});};
 await assert.rejects(m.readReceipt(png,'image/png',authorize),/OCR_CLAVE/);assert.equal(calls,2);
 calls=0;globalThis.fetch=async()=>{calls++;return provider({...raw,document:'multiple_payments'});};
 const ambiguous=await m.readReceipt(png,'image/png',authorize);assert.equal(calls,1);assert.equal(ambiguous.autoEligible,false);
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
test('401 with no code distinguishes missing grants and IP restrictions without falsely declaring an invalid key',async()=>{
 const prefix='You have insufficient permissions for this operation. Missing scopes: ';
 const cases=[
  [{type:'invalid_request_error',code:null,message:prefix+'api.responses.write. PRIVATE_ACCOUNT'},'PERMISO_RESPONSES','Responses → Write'],
  [{type:'invalid_request_error',message:prefix+'model.request PRIVATE_KEY'},'PERMISO_MODELO','Model capabilities → Request'],
  [{type:'invalid_request_error',message:prefix+'api.model.request, api.responses.write. PRIVATE_KEY'},'PERMISO_MODELO','Request y Responses'],
  [{type:'invalid_request_error',message:prefix+'PRIVATE_UNKNOWN_SCOPE'},'PERMISOS','permiso'],
  [{type:'ip_not_authorized',message:'PRIVATE_IP'},'IP','dirección IP'],
  [{code:'ip_not_authorized',message:'PRIVATE_IP'},'IP','dirección IP'],
  [{type:'invalid_api_key',message:'PRIVATE_KEY'},'CLAVE','no es válida'],
  [{code:null,type:'invalid_request_error',message:'PRIVATE_UNKNOWN_REASON'},'AUTENTICACION','sin indicar una causa reconocida'],
  [{message:'PRIVATE_DOCUMENT says Missing scopes: api.responses.write'},'AUTENTICACION','sin indicar una causa reconocida'],
 ];
 const warnings=[],warn=console.warn;console.warn=(...args)=>warnings.push(args);let calls=0;
 try{
  for(const [error,category,explanation] of cases){
   globalThis.fetch=async()=>{calls++;return Response.json({error},{status:401});};
   await assert.rejects(m.readReceipt(png,'image/png',authorize),failure=>{
    assert.equal(failure.status,502);assert(failure.message.includes(`OCR_${category} · HTTP 401`));
    assert(failure.message.includes(explanation));assert(!failure.message.includes('PRIVATE'));return true;
   });
  }
  assert.equal(calls,cases.length);assert.equal(warnings.length,cases.length);
  assert(!JSON.stringify(warnings).includes('PRIVATE'));
  // A phrase inside an unrelated error does not override its HTTP meaning.
  globalThis.fetch=async()=>Response.json({error:{message:prefix+'api.responses.write'}},{status:500});
  await assert.rejects(m.readReceipt(png,'image/png',authorize),/OCR_SERVICIO/);
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

const edges=regions=>regions.map(r=>({left:r.x,top:r.y,right:r.x+r.width,bottom:r.y+r.height}));
const eightRegions=Array.from({length:8},(_,i)=>({x:i%4*250+5,y:Math.floor(i/4)*500+5,width:240,height:490}));
test('region detection uses coordinate edges and verifies incomplete proposals against the full photo before returning corrected rectangles',async()=>{
 let calls=0,auth=0;
 globalThis.fetch=async(url,options)=>{calls++;assert.equal(url,'https://api.openai.com/v1/responses');const body=JSON.parse(options.body);assert.equal(body.store,false);assert.equal(body.text.format.name,'jac_receipt_regions');assert.equal(body.text.format.strict,true);assert.equal(body.input[0].content[1].image_url,'data:image/png;base64,'+Buffer.from(png).toString('base64'));assert.match(body.instructions,/untrusted/);
  if(calls===2){assert.match(body.input[0].content[0].text,/CORRIGE/);assert.match(body.input[0].content[0].text,/left/);}
  return provider({receipts:edges(calls===1?eightRegions.slice(0,6):eightRegions),moreReceipts:false,complete:true});};
 const result=await m.detectReceiptRegions(png,'image/png',async()=>{auth++;},undefined,{expectedCount:8});assert.deepEqual(result.regions,eightRegions);assert.equal(result.needsReview,false);assert.equal(calls,2);assert.equal(auth,3);
});
test('mismatched receipt counts, overlapping regions and incomplete paper remain explicitly unverified; malformed edges and excess receipts are rejected',async()=>{
 for(const [regions,complete] of [[eightRegions.slice(0,6),true],[[eightRegions[0],eightRegions[0]],true],[eightRegions,false]]){
  globalThis.fetch=async()=>provider({receipts:edges(regions),moreReceipts:false,complete});const result=await m.detectReceiptRegions(png,'image/png',authorize,undefined,{expectedCount:8});assert.equal(result.needsReview,true);assert.ok(result.warnings.length);
 }
 globalThis.fetch=async()=>provider({receipts:[{left:900,top:0,right:500,bottom:1000}],moreReceipts:false,complete:true});await assert.rejects(m.detectReceiptRegions(png,'image/png',authorize),e=>e.status===422);
 globalThis.fetch=async()=>provider({receipts:edges(eightRegions),moreReceipts:true,complete:true});await assert.rejects(m.detectReceiptRegions(png,'image/png',authorize),e=>e.status===422);
 await assert.rejects(m.detectReceiptRegions(png,'application/pdf',authorize),e=>e.status===415);
});
test('count and orientation are read independently from bounds and receipt data; cancellation and revocation prevent geometry verification',async()=>{
 let calls=0;
 globalThis.fetch=async(url,options)=>{calls++;const body=JSON.parse(options.body);assert.equal(body.text.format.name,'jac_receipt_layout');assert.equal(body.store,false);assert.equal(body.input[0].content.length,2);return provider({count:8,rotation:270,rows:2,columns:4,moreReceipts:false});};
 const layout=await m.inspectReceiptLayout(png,'image/png',authorize);assert.equal(layout.count,8);assert.equal(layout.rotation,270);assert.equal(calls,1);
 globalThis.fetch=async()=>provider({count:8,rotation:270,rows:2,columns:3,moreReceipts:false});await assert.rejects(m.inspectReceiptLayout(png,'image/png',authorize),e=>e.status===422);
 let auth=0;calls=0;globalThis.fetch=async()=>{calls++;return provider({receipts:edges(eightRegions),moreReceipts:false,complete:true});};
 await assert.rejects(m.detectReceiptRegions(png,'image/png',async()=>{if(++auth===2)throw Error('revoked');}),/revoked/);assert.equal(calls,1);
 const controller=new AbortController();calls=0;globalThis.fetch=async()=>{calls++;controller.abort();return provider({receipts:edges(eightRegions),moreReceipts:false,complete:true});};
 await assert.rejects(m.detectReceiptRegions(png,'image/png',authorize,controller.signal),e=>e.status===502);assert.equal(calls,1);
});
