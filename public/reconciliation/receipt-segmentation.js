/* Local geometry only. No bank model, receipt count, OCR data or network access. */
(() => {
  'use strict';
  const MAX_SIDE=1600,MAX_RECEIPTS=20;
  const uncertain=(reason,regions=[],coverage=0)=>({regions,needsReview:true,reason,coverage});
  function analyze(pixels){
    if(!pixels||!Number.isInteger(pixels.width)||!Number.isInteger(pixels.height)||pixels.width<16||pixels.height<16||!pixels.data||pixels.data.length!==pixels.width*pixels.height*4)return null;
    const scale=Math.min(1,MAX_SIDE/Math.max(pixels.width,pixels.height)),w=Math.max(1,Math.round(pixels.width*scale)),h=Math.max(1,Math.round(pixels.height*scale));
    const gray=new Uint8Array(w*h),histogram=new Uint32Array(256),tile=32,tw=Math.ceil(w/tile),bright=new Uint8Array(tw*Math.ceil(h/tile));
    for(let y=0;y<h;y++)for(let x=0;x<w;x++){
      const source=(Math.min(pixels.height-1,Math.floor(y/scale))*pixels.width+Math.min(pixels.width-1,Math.floor(x/scale)))*4;
      const value=Math.round(.299*pixels.data[source]+.587*pixels.data[source+1]+.114*pixels.data[source+2]);
      gray[y*w+x]=value;histogram[value]++;const t=Math.floor(y/tile)*tw+Math.floor(x/tile);bright[t]=Math.max(bright[t],value);
    }
    let cumulative=0,p90=255;for(let i=0;i<256;i++){cumulative+=histogram[i];if(cumulative>=w*h*.9){p90=i;break;}}
    const ink=new Uint8Array(w*h),dark=Math.min(165,p90-55);let inkCount=0;
    for(let y=0;y<h;y++)for(let x=0;x<w;x++){
      const i=y*w+x;
      // Keep every qualifying mark, including punctuation and amount tails.
      // Texture/shadow which cannot be distinguished safely causes review.
      if(gray[i]<dark&&gray[i]+40<bright[Math.floor(y/tile)*tw+Math.floor(x/tile)]){ink[i]=1;inkCount++;}
    }
    return {w,h,gray,ink,inkCount,paperThreshold:Math.max(165,p90-18)};
  }
  function boxesInPixels(a,regions){
    if(!Array.isArray(regions)||!regions.length||regions.length>MAX_RECEIPTS)return null;
    const boxes=[];
    for(const b of regions){
      if(!b||![b.x,b.y,b.width,b.height].every(Number.isFinite)||b.x<0||b.y<0||b.width<10||b.height<10||b.x+b.width>1000||b.y+b.height>1000)return null;
      boxes.push({left:Math.floor(b.x*a.w/1000),top:Math.floor(b.y*a.h/1000),right:Math.min(a.w,Math.ceil((b.x+b.width)*a.w/1000)),bottom:Math.min(a.h,Math.ceil((b.y+b.height)*a.h/1000))});
    }
    return boxes;
  }
  function check(a,regions){
    const boxes=boxesInPixels(a,regions);if(!boxes)return uncertain('Los límites de los recortes no son válidos.');
    if(a.inkCount<30)return uncertain('No hay suficiente texto visible para comprobar los recortes.');
    const covered=new Uint8Array(a.w*a.h),marks=[];let crossing=0;
    for(const b of boxes){
      let count=0;
      for(let y=b.top;y<b.bottom;y++)for(let x=b.left;x<b.right;x++){const i=y*a.w+x;if(a.ink[i]){covered[i]++;count++;}}
      marks.push(count);
      // A boundary through a connected stroke is a cut character, even if an
      // overlapping neighbouring box happens to cover its remaining pixels.
      for(let y=b.top;y<b.bottom;y++){
        if(b.left>0&&a.ink[y*a.w+b.left-1]&&a.ink[y*a.w+b.left])crossing++;
        if(b.right<a.w&&a.ink[y*a.w+b.right-1]&&a.ink[y*a.w+b.right])crossing++;
      }
      for(let x=b.left;x<b.right;x++){
        if(b.top>0&&a.ink[(b.top-1)*a.w+x]&&a.ink[b.top*a.w+x])crossing++;
        if(b.bottom<a.h&&a.ink[(b.bottom-1)*a.w+x]&&a.ink[b.bottom*a.w+x])crossing++;
      }
    }
    let missing=0,duplicated=0;for(let i=0;i<a.ink.length;i++)if(a.ink[i]){if(!covered[i])missing++;else if(covered[i]>1)duplicated++;}
    const coverage=(a.inkCount-missing)/a.inkCount;
    if(marks.some(n=>n<20))return uncertain('Hay recortes vacíos o sin suficiente texto.',[],coverage);
    if(missing>2)return uncertain('Los recortes dejan texto por fuera de la imagen seleccionada.',[],coverage);
    if(crossing>1||duplicated>2)return uncertain('Hay bordes que cortan texto o incluyen texto de otro recorte.',[],coverage);
    return {regions,needsReview:false,reason:'',coverage};
  }
  function paperComponents(a){
    const {w,h,gray,ink,paperThreshold}=a,seen=new Uint8Array(w*h),queue=new Int32Array(w*h),papers=[];
    const minimumArea=Math.max(160,w*h*.0015);let blankObjects=0;
    for(let start=0;start<gray.length;start++){
      if(seen[start]||gray[start]<paperThreshold)continue;
      let head=0,tail=1,minX=start%w,maxX=minX,minY=Math.floor(start/w),maxY=minY;queue[0]=start;seen[start]=1;
      while(head<tail){
        const i=queue[head++],x=i%w,y=Math.floor(i/w);minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);
        const visit=j=>{if(!seen[j]&&gray[j]>=paperThreshold){seen[j]=1;queue[tail++]=j;}};
        if(x>0)visit(i-1);if(x+1<w)visit(i+1);if(y>0)visit(i-w);if(y+1<h)visit(i+w);
      }
      const width=maxX-minX+1,height=maxY-minY+1,area=width*height;
      // A bright background surrounding all papers is not another receipt.
      if(minX===0&&maxX===w-1&&minY===0&&maxY===h-1)continue;
      if(tail<minimumArea||width<14||height<20||tail/area<.45)continue;
      let marks=0;for(let y=minY;y<=maxY;y++)for(let x=minX;x<=maxX;x++)marks+=ink[y*w+x];
      if(marks<30){if(area>w*h*.015)blankObjects++;continue;}
      papers.push({left:minX,top:minY,right:maxX+1,bottom:maxY+1,area});
      if(papers.length>MAX_RECEIPTS)return {papers,blankObjects};
    }
    return {papers,blankObjects};
  }
  function detect(pixels){
    const a=analyze(pixels);if(!a)return uncertain('No se pudo analizar la imagen.');
    const {papers,blankObjects}=paperComponents(a);
    // Text gaps alone cannot reliably distinguish a new receipt from a large
    // paragraph gap. Never turn such gaps into confident additional receipts.
    if(papers.length<2)return uncertain('No se distinguen los bordes de cada papel. Revisa la foto completa o separa por filas y columnas.');
    if(papers.length>MAX_RECEIPTS)return uncertain('Hay demasiados bloques para separarlos con seguridad.');
    const areas=papers.map(p=>p.area).sort((a,b)=>a-b),median=areas[Math.floor(areas.length/2)];
    if(blankObjects||papers.some(p=>p.area<median*.28||p.area>median*2.4))return uncertain('Hay papeles unidos, tamaños muy distintos u objetos sin texto. Revisa la separación.');
    const pad=Math.max(2,Math.ceil(Math.min(a.w,a.h)*.003));
    const ordered=[...papers].sort((p,q)=>p.top-q.top),rows=[];
    for(const paper of ordered){
      const row=rows.find(r=>Math.abs(paper.top-r.top)<Math.min(paper.bottom-paper.top,r.height)*.3);
      if(row)row.papers.push(paper);else rows.push({top:paper.top,height:paper.bottom-paper.top,papers:[paper]});
    }
    const regions=rows.flatMap(row=>row.papers.sort((p,q)=>p.left-q.left)).map(p=>{
      const x=Math.floor(Math.max(0,p.left-pad)*1000/a.w),y=Math.floor(Math.max(0,p.top-pad)*1000/a.h);
      return {x,y,width:Math.ceil(Math.min(a.w,p.right+pad)*1000/a.w)-x,height:Math.ceil(Math.min(a.h,p.bottom+pad)*1000/a.h)-y};
    });
    const result=check(a,regions);if(result.needsReview)return uncertain(result.reason,[],result.coverage);
    const columns=rows[0].papers.length,sameColumns=rows.every(row=>row.papers.length===columns);
    return {...result,evidence:'paper-components-and-ink-coverage',rows:sameColumns?rows.length:0,columns:sameColumns?columns:0};
  }
  // Coverage is necessary, not proof that an AI rectangle contains one paper.
  // The caller must also validate count/layout and require uncertain reviews.
  function validate(pixels,regions){const a=analyze(pixels);return a?check(a,regions):uncertain('No se pudo comprobar la cobertura de texto.');}
  window.JacReceiptSegmentation={detect,validate};
})();
