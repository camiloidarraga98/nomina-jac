// Counts transport bytes only. Server confirmation and file completion remain
// separate, so a full socket buffer never marks an unconfirmed file as saved.
export class MediaUploadMeter {
 private sent=new Map<string,number>();private samples:{at:number;bytes:number}[]=[];
 record(key:string,loaded:number,now=performance.now()) {const previous=this.sent.get(key)||0,value=Math.max(previous,loaded);this.sent.set(key,value);if(value>previous)this.samples.push({at:now,bytes:value-previous});}
 finish(key:string){this.sent.delete(key);}
 rate(now=performance.now()){this.samples=this.samples.filter(x=>now-x.at<4000);if(!this.samples.length)return 0;return this.samples.reduce((n,x)=>n+x.bytes,0)/Math.max(.5,Math.min(4,(now-this.samples[0].at)/1000+.5));}
 reset(){this.sent.clear();this.samples=[];}
}
