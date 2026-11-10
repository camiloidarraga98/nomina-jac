import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const context={window:{},document:{addEventListener(){},removeEventListener(){}}};
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
