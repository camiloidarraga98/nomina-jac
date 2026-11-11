import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
// Same-realm pixel arrays avoid measuring a VM boundary for every pixel.
const browser={};new Function('window',await readFile('public/reconciliation/receipt-segmentation.js','utf8'))(browser);
const {detect,validate}=browser.JacReceiptSegmentation;
function image(w,h,bg=190){const data=new Uint8ClampedArray(w*h*4);for(let i=0;i<data.length;i+=4){data[i]=bg;data[i+1]=bg;data[i+2]=bg;data[i+3]=255;}return {width:w,height:h,data};}
function rect(p,cx,cy,x,y,w,h,angle,value){
 const cos=Math.cos(angle),sin=Math.sin(angle),corners=[[x,y],[x+w,y],[x,y+h],[x+w,y+h]].map(([a,b])=>[cx+a*cos-b*sin,cy+a*sin+b*cos]);
 const left=Math.max(0,Math.floor(Math.min(...corners.map(c=>c[0])))),right=Math.min(p.width,Math.ceil(Math.max(...corners.map(c=>c[0]))));
 const top=Math.max(0,Math.floor(Math.min(...corners.map(c=>c[1])))),bottom=Math.min(p.height,Math.ceil(Math.max(...corners.map(c=>c[1]))));
 for(let py=top;py<bottom;py++)for(let px=left;px<right;px++){
  const dx=px+.5-cx,dy=py+.5-cy,lx=dx*cos+dy*sin,ly=-dx*sin+dy*cos;
  if(lx>=x&&lx<x+w&&ly>=y&&ly<y+h){const i=(py*p.width+px)*4;p.data[i]=p.data[i+1]=p.data[i+2]=value;}
 }
 return corners;
}
function scene(rows,columns,{background=190,touching=false,shadow=false}={}){
 const paperW=150,paperH=300,gap=touching?0:30,p=image(columns*(paperW+gap)+60,rows*(paperH+gap)+60,background),marks=[];
 for(let r=0;r<rows;r++)for(let c=0;c<columns;c++){
  const cx=30+paperW/2+c*(paperW+gap),cy=30+paperH/2+r*(paperH+gap)+(touching?0:c%3*4),angle=touching?0:((r+c)%2?2:-2)*Math.PI/180;
  rect(p,cx,cy,-paperW/2,-paperH/2,paperW,paperH,angle,245);
  if(shadow&&r===rows-1&&c===columns-1)rect(p,cx,cy,-paperW/2,110,paperW,40,angle,205);
  // A header, date, long amount and footer, with large internal paragraph gaps.
  for(const [x,y,w,h] of [[-65,-130,130,8],[-63,-109,124,4],[-62,-82,116,5],[-63,-62,120,5],[-64,-40,123,5],[-66,13,132,11],[-62,50,124,5],[-61,70,122,5],[-60,90,120,5],[-69,136,138,4]]){
   marks.push(...rect(p,cx,cy,x,y,w,h,angle,35));
  }
 }
 return {pixels:p,marks};
}
const includes=(b,x,y,p)=>x>=b.x*p.width/1000&&x<=(b.x+b.width)*p.width/1000&&y>=b.y*p.height/1000&&y<=(b.y+b.height)*p.height/1000;

test('ten staggered tilted receipts are found independently, preserving header, date, complete amount and footer',()=>{
 const {pixels,marks}=scene(2,5),result=detect(pixels);assert.equal(result.needsReview,false,result.reason);assert.equal(result.regions.length,10);assert.equal(result.rows,2);assert.equal(result.columns,5);assert.equal(result.coverage,1);
 for(const [x,y] of marks)assert.equal(result.regions.filter(b=>includes(b,x,y,pixels)).length,1,'Every text-block corner remains inside exactly one complete receipt');
 const elevenNarrow=Array.from({length:11},(_,i)=>({x:i%6*100,y:Math.floor(i/6)*500,width:90,height:430}));
 const rejected=validate(pixels,elevenNarrow);assert.equal(rejected.needsReview,true);assert(rejected.coverage<.9,'The incorrect narrow boxes omit visible ink');
});
test('the detector has no fixed receipt count and does not split large gaps inside paragraphs into additional papers',()=>{
 for(const [rows,columns] of [[1,2],[1,4],[2,3],[3,4]]){const {pixels}=scene(rows,columns),result=detect(pixels);assert.equal(result.needsReview,false,result.reason);assert.equal(result.regions.length,rows*columns);}
});
test('an omitted edge receipt, truncated amount, and duplicate region cannot pass text coverage',()=>{
 const {pixels}=scene(2,5),result=detect(pixels);assert.equal(result.needsReview,false);
 assert.equal(validate(pixels,result.regions.slice(0,-1)).needsReview,true,'Entire right-hand receipt cannot disappear');
 const cut=result.regions.map(b=>({...b}));cut[4].width-=40;assert.equal(validate(pixels,cut).needsReview,true,'Last amount digits cannot be discarded');
 assert.equal(validate(pixels,[...result.regions,result.regions[0]]).needsReview,true,'A repeated receipt includes the same text twice');
 assert.equal(validate(pixels,result.regions).needsReview,false);
});
test('touching papers, poor background contrast and shadow hiding the paper edge require review rather than invented crops',()=>{
 for(const opts of [{touching:true},{background:245},{shadow:true}]){const result=detect(scene(2,5,opts).pixels);assert.equal(result.needsReview,true,JSON.stringify(opts));assert.equal(result.regions.length,0);}
});
test('blank images and bright background objects do not become receipt rectangles',()=>{
 const blank=image(400,400);rect(blank,200,200,-80,-130,160,260,0,245);assert.equal(detect(blank).needsReview,true);
 const {pixels}=scene(1,2);rect(pixels,15,15,-6,-6,12,12,0,255);const result=detect(pixels);assert.equal(result.needsReview,false,result.reason);assert.equal(result.regions.length,2);
 assert.equal(validate(pixels,[]).needsReview,true);
});
