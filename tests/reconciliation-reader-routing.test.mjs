import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const context=vm.createContext({window:{},document:{querySelector:()=>null,addEventListener(){},removeEventListener(){}},AbortController,FormData,File,URL});
for(const file of ['receipt-batch.js','receipt-collection.js'])vm.runInContext(await readFile('public/reconciliation/'+file,'utf8'),context);
const Reader=context.window.JacReceiptCollection;
const receipt=i=>({index:i,row:1,column:i+1,bounds:null,reading:{document:'single_payment',amount:1000000+i,date:'2026-11-01',warnings:[]},matches:[{id:'payment-'+i,version:1,status:'pending',kind:'exact'}],total:1,autoMatchId:'payment-'+i});
function fixture(result){
 const calls=[],handoffs=[];const reader=new Reader({api:async(...args)=>{calls.push(args);return result;},singleReady:(...args)=>handoffs.push(args),busy(){},dirty(){}});
 reader.source=new File(['synthetic'],'original.png',{type:'image/png'});reader.preview=new File(['synthetic'],'preview.jpg',{type:'image/jpeg'});reader.render=()=>{};reader.detailImages=async()=>[];
 reader.crop=async()=>{throw Error('A single receipt must not create a crop');};
 return {reader,calls,handoffs};
}

test('one receipt opens the individual reader even with incomplete enumeration; warnings and candidates survive but auto-assignment does not',async()=>{
 for(const complete of [false,true]){
  const result={receipts:[receipt(0)],complete,warnings:complete?[]:['Confirma la imagen completa.']},f=fixture(result);await f.reader.readImage();
  assert.equal(f.calls.length,1);assert.equal(f.handoffs.length,1);assert.equal(f.handoffs[0][0],f.reader.source);assert.equal(f.handoffs[0][2],f.reader.preview);
  const read=f.handoffs[0][1];assert.equal(read.reading.amount,1000000);assert.equal(read.reading.date,'2026-11-01');assert.equal(read.matches[0].id,'payment-0');assert.equal(read.autoMatchId,complete?'payment-0':null);assert.equal(read.reading.warnings.length,complete?0:1);assert.equal(f.reader.parts.length,0);f.reader.dispose();
 }
});
test('several recovered receipts retain their separate cards and automatic matches',async()=>{
 const f=fixture({receipts:[receipt(0),receipt(1)],complete:true,warnings:[],evidence:'signed'});let crops=0;f.reader.crop=async()=>{crops++;};await f.reader.readImage();assert.equal(f.handoffs.length,0);assert.equal(f.reader.parts.length,2);assert.equal(crops,0);assert(f.reader.parts.every(p=>p.visualKind==='unlocated'));assert.equal(f.reader.parts[0].paymentId,'payment-0');assert.equal(f.reader.parts[1].paymentId,'payment-1');f.reader.dispose();
});
test('explicit individual recovery retains the full image and common fields, and cannot run while saving or after a saved group',async()=>{
 const f=fixture({});const recovered=[];f.reader.h.singleWhole=(...args)=>recovered.push(args);f.reader.shared={showId:'show-existing',entrepreneur:'Ficticio'};f.reader.parts=[{index:0,saved:false}];
 await f.reader.action('batch-single-whole');assert.equal(recovered.length,1);assert.equal(recovered[0][0],f.reader.source);assert.equal(recovered[0][1],f.reader.preview);assert.equal(recovered[0][2].showId,'show-existing');assert.equal(recovered[0][2].entrepreneur,'Ficticio');assert.equal(f.calls.length,0);
 f.reader.busy=true;await f.reader.action('batch-single-whole');f.reader.busy=false;f.reader.parts[0].saved=true;await f.reader.action('batch-single-whole');assert.equal(recovered.length,1);f.reader.dispose();
});
test('view rotations keep receipt bounds in the original frame with reversible edges at all four orientations',()=>{
 const f=fixture({}),bounds={x:40,y:120,width:230,height:610};
 const expected=[{...bounds},{x:270,y:40,width:610,height:230},{x:730,y:270,width:230,height:610},{x:120,y:730,width:610,height:230}];
 for(const [i,angle]of [0,90,180,270].entries()){
  f.reader.rotation=angle;const shown=f.reader.displayBounds(bounds);assert.equal(JSON.stringify(shown),JSON.stringify(expected[i]));assert.equal(JSON.stringify(Reader.originalBounds(shown,angle)),JSON.stringify(bounds));
 }
 f.reader.dispose();
});
