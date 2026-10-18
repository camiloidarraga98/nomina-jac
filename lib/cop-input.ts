// COP editing is text; persisted show amounts remain numbers in pesos.
export function copText(value:number):string {
 const [whole,fraction]=value.toFixed(2).split('.');
 const cents=fraction.replace(/0+$/,'');
 return whole.replace(/\B(?=(\d{3})+(?!\d))/g,'.')+(cents?','+cents:'');
}
export function editCop(text:string,caret=text.length):{text:string;value:number;caret:number}|null {
 if(!/^[\d.,]*$/.test(text))return null;
 const raw=text.replaceAll('.','');
 if(!/^\d*(?:,\d{0,2})?$/.test(raw))return null;
 if(!raw)return {text:'',value:0,caret:0};
 const [integer,fraction]=raw.split(',');
 const whole=integer.replace(/^0+(?=\d)/,'')||'0';
 const normalized=whole.replace(/\B(?=(\d{3})+(?!\d))/g,'.')+(fraction!==undefined?','+fraction:'');
 const value=Number(whole+(fraction?'.'+fraction:''));
 if(!Number.isFinite(value))return null;
 // Keep the caret beside the same digit when grouping inserts/removes dots.
 const before=text.slice(0,caret).replaceAll('.','').length;
 const removed=integer.length-whole.length;
 let remaining=Math.max(0,before-removed),position=0;
 while(position<normalized.length&&remaining>0){if(normalized[position]!=='.')remaining--;position++;}
 return {text:normalized,value,caret:position};
}
export function copPaste(text:string):string|null {
 const clean=text.trim().replace(/^(?:COP\s*)?\$\s*/i,'').replace(/^COP\s+/i,'').replace(/\s+COP$/i,'').trim();
 // Accept Colombian grouping/decimal comma and ungrouped decimal-point amounts.
 if(/^(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?$/.test(clean))return clean.replaceAll('.','');
 if(/^\d+\.\d{1,2}$/.test(clean))return clean.replace('.',',');
 return null;
}
