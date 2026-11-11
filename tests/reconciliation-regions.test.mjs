import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const context={window:{},AbortController,document:{addEventListener(){},removeEventListener(){}}};
runInNewContext(await readFile('public/reconciliation/receipt-batch.js','utf8'),context);
const Batch=context.window.JacReceiptBatch,plain=v=>JSON.parse(JSON.stringify(v));
test('rotated detection boxes map to canonical original coordinates for every quarter turn; the storage frame never changes',()=>{
 const original={x:120,y:210,width:180,height:330};
 for(const [rotation,rotated] of [[0,original],[90,{x:460,y:120,width:330,height:180}],[180,{x:700,y:460,width:180,height:330}],[270,{x:210,y:700,width:330,height:180}]])assert.deepEqual(plain(Batch.originalBounds(rotated,rotation)),original);
 assert.deepEqual(plain(Batch.originalBounds({x:0,y:0,width:1000,height:1000},90)),{x:0,y:0,width:1000,height:1000});
});
test('manual grid has no gaps or duplicate pixels after rounding and rejects oversized or incomplete layouts',()=>{
 const b=new Batch({});b.gridDraft={rows:2,columns:4,bounds:{x:37,y:19,width:951,height:979}};const boxes=plain(b.gridBounds());assert.equal(boxes.length,8);
 for(let row=0;row<2;row++){const cells=boxes.slice(row*4,row*4+4);assert.equal(cells[0].x,37);assert.equal(cells[3].x+cells[3].width,988);for(let col=1;col<4;col++)assert.equal(cells[col-1].x+cells[col-1].width,cells[col].x);}
 assert.equal(boxes[0].y+boxes[0].height,boxes[4].y);assert.equal(boxes[4].y+boxes[4].height,998);
 for(const [rows,columns] of [[0,4],[2,0],[5,5],[1.5,4]]){b.gridDraft={...b.gridDraft,rows,columns};assert.equal(b.gridBounds().length,0);}
});

// Synthetic pixels only: no real receipts/accounting data enter the repository.
function pixels(width,height){
 const data=new Uint8ClampedArray(width*height*4);data.fill(240);
 return {width,height,data,mark(x,y,w,h,value=35){for(let r=y;r<y+h;r++)for(let c=x;c<x+w;c++){const i=(r*width+c)*4;data[i]=data[i+1]=data[i+2]=value;data[i+3]=255;}}};
}
const includes=(b,p,w,h)=>p.x>=b.x*w/1000&&p.y>=b.y*h/1000&&p.x+p.width<=(b.x+b.width)*w/1000&&p.y+p.height<=(b.y+b.height)*h/1000;
test('pixel separation recovers full amount and date from truncated AI rectangles on two widely spaced receipts',()=>{
 const p=pixels(1600,1168),marks=[{x:105,y:355,width:445,height:18},{x:100,y:680,width:450,height:22},{x:1135,y:315,width:330,height:18},{x:1035,y:640,width:465,height:22}];
 for(const m of marks)p.mark(m.x,m.y,m.width,m.height);
 const bad=[{x:20,y:180,width:330,height:700},{x:390,y:110,width:460,height:720}];
 assert.equal(includes(bad[1],marks[3],p.width,p.height),false,'Reported failure: amount ends outside the proposed crop');
 const result=Batch.partitionRegions(p,{rows:1,columns:2,count:2},bad);
 assert.equal(result.needsReview,false);assert.equal(result.regions.length,2);
 for(let i=0;i<marks.length;i++)assert.equal(includes(result.regions[Math.floor(i/2)],marks[i],p.width,p.height),true,'Every date and final amount digit survives');
 assert.equal(result.regions[0].x,0);assert.equal(result.regions[1].x+result.regions[1].width,1000);
 assert.equal(includes(result.regions[0],marks[2],p.width,p.height),false);assert.equal(includes(result.regions[1],marks[1],p.width,p.height),false);
});
test('nonuniform columns and staggered rows are separated at real gaps, without slicing a receipt into an equal grid',()=>{
 const p=pixels(1200,900),proposals=[],marks=[],columns=[[150,380],[430,620],[660,830],[870,1140]];
 for(let r=0;r<2;r++)for(let c=0;c<4;c++){
  const [x,end]=columns[c],y=(r?470:60)+c*12;
  const a={x,y,width:end-x,height:18},b={x,y:y+310,width:end-x,height:18};marks.push([a,b]);p.mark(x,y,a.width,18);p.mark(x,y+310,b.width,18);
  proposals.push({x:(x+15)/1.2,y:y/.9,width:(end-x-30)/1.2,height:310/.9});
 }
 const result=Batch.partitionRegions(p,{rows:2,columns:4,count:8},proposals);
 assert.equal(result.needsReview,false);assert.equal(result.regions.length,8);
 for(let i=0;i<8;i++)for(const m of marks[i])assert.equal(includes(result.regions[i],m,p.width,p.height),true,`Receipt ${i+1} retains its full text`);
 for(let i=0;i<8;i++)for(let j=0;j<8;j++)if(i!==j)assert.equal(includes(result.regions[i],marks[j][0],p.width,p.height),false,'Other receipt header excluded');
});
test('count conflicts, uncertain grids, blank cells and separators crossing ink cannot silently enable OCR',()=>{
 const p=pixels(800,500),proposals=[{x:10,y:10,width:450,height:950},{x:510,y:10,width:450,height:950}];
 assert.equal(Batch.partitionRegions(p,{rows:1,columns:2,count:2},proposals).needsReview,true,'Blank paper is not evidence of two receipts');
 assert.equal(Batch.partitionRegions(p,{rows:0,columns:0,count:2},proposals).needsReview,true);
 assert.equal(Batch.partitionRegions(p,{rows:1,columns:3,count:3},proposals).needsReview,true);
 assert.deepEqual(plain(Batch.partitionRegions(p,{rows:1,columns:3,count:3},proposals).regions),[],'Count mismatch never exposes raw AI crops');
 p.mark(10,150,780,20);p.mark(10,250,780,20);
 assert.equal(Batch.partitionRegions(p,{rows:1,columns:2,count:2},proposals).needsReview,true,'Continuous text across the proposed gap requires review');
});
test('light table and paper edges are not mistaken for payment text in regular receipt grids',()=>{
 const p=pixels(800,600),proposals=[];p.mark(0,0,800,600,200);
 for(let r=0;r<2;r++)for(let c=0;c<4;c++){
  const x=c*200,y=r*300;p.mark(x+4,y+4,192,292,255);
  for(const dy of [50,90,200,250])p.mark(x+15,y+dy,170,8);
  proposals.push({x:c*250+10,y:r*500+10,width:230,height:480});
 }
 const result=Batch.partitionRegions(p,{rows:2,columns:4,count:8},proposals);
 assert.equal(result.needsReview,false);assert.equal(result.regions.length,8);
});
test('single-receipt count hands off the original without region requests, and reviewing crops starts pending reads',async()=>{
 const source={name:'synthetic.jpg'},calls=[];
 class FlowBatch extends Batch {static rotatedCanvas(image){return image;}analysisPixels(){return pixels(10,10);}}
 const b=new FlowBatch({single:file=>calls.push(file)});b.source=source;b.preview={size:100};b.layout={count:1,rows:1,columns:1,rotation:0};b.orientationVerified=true;
 await b.detectRegions();assert.deepEqual(calls,[source]);
 b.parts=[{index:0,bounds:{x:0,y:0,width:400,height:1000},read:false},{index:1,bounds:{x:600,y:0,width:400,height:1000},read:true}];b.needsReview=true;b.render=()=>{};
 b.readParts=async parts=>{assert.equal(b.needsReview,false);assert.deepEqual(parts.map(p=>p.index),[0]);calls.push('read');};
 await b.action('batch-confirm-crops');assert.deepEqual(calls,[source,'read']);
});
test('local ten-receipt separation overrides an unsafe eleven-piece estimate and cannot be read until the conflict is reviewed',async()=>{
 const boxes=Array.from({length:10},(_,i)=>({x:i%5*200,y:Math.floor(i/5)*500,width:190,height:490}));
 context.window.JacReceiptSegmentation={detect:()=>({regions:boxes,needsReview:false})};
 class FlowBatch extends Batch {static rotatedCanvas(image){return image;}analysisPixels(){return pixels(10,10);}render(){}async crop(){}async readParts(){throw Error('Conflicting count must be reviewed first');}}
 try{for(const count of [1,11]){
  const b=new FlowBatch({single:()=>{throw Error('Ten receipts must not use the single-reader');},api:()=>{throw Error('Safe local geometry does not need model rectangles');}});
  b.layout={count,rows:0,columns:0,rotation:0};b.orientationVerified=true;
  await b.detectRegions();assert.equal(b.parts.length,10);assert.equal(b.needsReview,true);assert.deepEqual(plain(b.parts.map(p=>p.bounds)),boxes);
 }}finally{delete context.window.JacReceiptSegmentation;}
});

test('verified orientation replaces an incorrect angle and swaps grid axes only for a quarter turn',async()=>{
 const b=new Batch({});b.layout={count:8,rows:2,columns:4,rotation:90};
 b.setOrientation(270);assert.equal(b.rotation,270);assert.equal(b.layout.rows,2);assert.equal(b.layout.columns,4);
 b.setOrientation(0);assert.equal(b.layout.rows,4);assert.equal(b.layout.columns,2);
 b.parts=[{paymentId:'synthetic',version:1}];b.setBusy=()=>{throw Error('Must not start reading or saving before orientation review');};
 await b.readParts(b.parts);await b.save();
});
