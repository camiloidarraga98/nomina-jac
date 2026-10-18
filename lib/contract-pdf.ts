import {PDFDocument,PDFDict,PDFName,PDFHexString,beginText,endText,setFontAndSize,setTextMatrix,showText,setFillingColor,rgb,type PDFPage,type PDFRef} from 'pdf-lib';
import master from './contract-template.json';
import {contractInput,contractMoney,contractMoneyWords,contractDate,contractTime,type ContractInput} from './contract-core';

type Run={text:string;bold?:boolean};
type Font={ref:PDFRef;glyphs:Record<string,(string|number)[]>};
type Fonts={regular:Font;bold:Font};
const normal=(text:string):Run=>({text}),bold=(text:string):Run=>({text,bold:true});
const ink=rgb(31/255,43/255,52/255);
const fontNames=new WeakMap<PDFPage,Map<PDFRef,PDFName>>();
function width(text:string,font:Font,size:number){return [...text].reduce((n,c)=>{const g=font.glyphs[c];if(!g)throw Error(`El contrato contiene un carácter no admitido: ${c}`);return n+Number(g[1])*size/1000;},0);}
function put(page:PDFPage,text:string,x:number,y:number,size:number,font:Font){
 let names=fontNames.get(page);if(!names){names=new Map();fontNames.set(page,names);}let name=names.get(font.ref);if(!name){name=page.node.newFontDictionary('ContractArial',font.ref);names.set(font.ref,name);}
 page.pushOperators(beginText(),setFillingColor(ink),setFontAndSize(name,size),setTextMatrix(1,0,0,1,x,y),showText(PDFHexString.of([...text].map(c=>{const code=font.glyphs[c]?.[0];if(!code)throw Error('Carácter no admitido en el contrato.');return String(code);}).join(''))),endText());
}
function wrap(runs:Run[],fonts:Fonts,size:number,maxWidth:number){
 const tokens=runs.flatMap(r=>r.text.split(/(\s+)/).filter(Boolean).map(text=>({...r,text}))),lines:Run[][]=[];let line:Run[]=[],used=0;
 for(const token of tokens){const space=/^\s+$/.test(token.text),w=width(token.text,token.bold?fonts.bold:fonts.regular,size);if(!space&&w>maxWidth)throw Error('Un dato contiene una palabra demasiado larga para la plantilla.');if(!space&&used+w>maxWidth&&line.length){while(line.length&&/^\s+$/.test(line.at(-1)!.text))line.pop();lines.push(line);line=[];used=0;}if(!line.length&&space)continue;line.push(token);used+=w;}
 while(line.length&&/^\s+$/.test(line.at(-1)!.text))line.pop();if(line.length)lines.push(line);return lines;
}
function paragraph(page:PDFPage,runs:Run[],fonts:Fonts,y:number,maxLines:number,label:string){
 let size=10.15,lines=wrap(runs,fonts,size,516);while(lines.length>maxLines&&size>8.55){size=Math.round((size-.1)*100)/100;lines=wrap(runs,fonts,size,516);}
 if(lines.length>maxLines)throw Error(`Los datos de ${label} son demasiado extensos para las cuatro páginas de la plantilla. Abrevia el sitio o la razón social sin omitir su identidad.`);
 lines.forEach((line,i)=>{const used=line.reduce((n,r)=>n+width(r.text,r.bold?fonts.bold:fonts.regular,size),0),spaces=line.filter(r=>/^\s+$/.test(r.text)).length,extra=i<lines.length-1&&spaces?(516-used)/spaces:0;let x=48;for(const r of line){const font=r.bold?fonts.bold:fonts.regular;put(page,r.text,x,y-i*13.5,size,font);x+=width(r.text,font,size)+(/^\s+$/.test(r.text)?extra:0);}});
 return y-lines.length*13.5;
}
function signatureLine(page:PDFPage,text:string,y:number,font:Font){let size=9.3;while(width(text,font,size)>246&&size>7.05)size-=.1;if(width(text,font,size)>246)throw Error('El nombre de la empresa o representante es demasiado largo para el bloque de firma de la plantilla.');put(page,text,441-width(text,font,size)/2,y,size,font);}
function dataRuns(v:ContractInput){
 const company=v.company.toLocaleUpperCase('es-CO'),rep=v.representative.toLocaleUpperCase('es-CO'),town=`${v.municipality}-${v.department}`,date=contractDate(v.eventDate),capital=date[0].toLocaleUpperCase('es-CO')+date.slice(1),time=contractTime(v.showTime),amount=(n:number)=>`${contractMoneyWords(n)} M/CTE. ($ ${contractMoney(n)})`;
 return {company,rep,intro:[normal('Entre los suscritos, de una parte '),bold('JAC MUSIC ESTUDIOS S.A.S'),normal(' con '),bold('NIT 901.334.092-1'),normal(' y en calidad de representante Legal el señor '),bold('JONNY ALEXANDER CASTAÑO PUERTA'),normal(' identificado con cédula de ciudadanía '),bold('Nº18.517.940 DE DOSQUEBRADAS'),normal(' quien actúa en nombre del artista '),bold('JHON ALEX CASTAÑO'),normal(' y su agrupación musical”, en adelante se denominará '),bold('EL CONTRATISTA'),normal('; y de la otra '),bold(company),normal(' con '),bold('NIT '+v.nit),normal(' quien obrando en calidad de representante el señor '),bold(rep),normal(' identificado con cédula de ciudadanía '),bold('No. '+v.identity),normal(' en adelante se denominará, para todos los efectos del presente contrato '),bold('EL CONTRATANTE'),normal(', ha decidido comparecer a la firma del presente documento con el fin de celebrar un acuerdo de presentación artística que tendrá como finalidad la prestación de los servicios de '),bold('EL ARTISTA'),normal(', en un evento que tendrá lugar el día '),bold(capital),normal(' en '),bold(v.venue),normal(' en el Municipio de '),bold(town),normal(` hora de presentación ${time} Lo anterior de conformidad con las siguientes cláusulas:`)],
 object:[normal('Mediante el presente documento, '),bold('EL ARTISTA'),normal(' se compromete a prestar sus servicios profesionales a '),bold('EL CONTRATANTE'),normal(', realizando una presentación en el '),bold(v.venue),normal(' del Municipio de '),bold(town),normal(` el día ${date}. La hora de la presentación es a las ${time} `),bold('Desde esta hora empieza a correr el tiempo en tarima.'),normal(' (La hora de presentación es show central, NO se cierra concierto)')],
 price:[bold('EL CONTRATANTE'),normal(' deberá pagar a '),bold('EL ARTISTA'),normal(' la suma de '),bold(`${contractMoneyWords(v.price)} M/CTE. ($ ${contractMoney(v.price)})`),normal(', libres de impuestos y retenciones como contraprestación por los servicios antes descritos mediante transferencia o consignación, los cuales deben consignarse de la siguiente manera:')],
 deposit:[normal('A la fecha han consignado el Valor de '),bold(amount(v.deposited)),normal(`. El ${contractDate(v.halfDeadline,true,v.halfDeadline.slice(0,4)!==v.eventDate.slice(0,4))} se completara el `),bold('50%'),normal(' del valor del contrato.')],
 final:[normal('El restante para completar el '),bold('100%'),normal(' sobre el valor del contrato, es decir la suma de '),bold(amount(v.price/2)),normal(' deberá ser consignada 5 días antes de la presentación.')],
 };
}
export async function contractPdf(input:unknown){
 const v=contractInput.parse(input),pdf=await PDFDocument.load(master.template),pack=await PDFDocument.load(master.fontPack);
 const [fontPage]=await pdf.copyPages(pack,[0]),resources=fontPage.node.Resources()!.lookup(PDFName.of('Font'),PDFDict);
 const fonts:Fonts={regular:{ref:resources.get(PDFName.of(master.fonts.regular.resource)) as PDFRef,glyphs:master.fonts.regular.glyphs},bold:{ref:resources.get(PDFName.of(master.fonts.bold.resource)) as PDFRef,glyphs:master.fonts.bold.glyphs}};
 const pages=pdf.getPages(),r=dataRuns(v);paragraph(pages[0],r.intro,fonts,657.85,11,'la presentación');paragraph(pages[0],r.object,fonts,446.05,4,'el objeto');
 let y=paragraph(pages[1],r.price,fonts,205.75,4,'el precio')-8;y=paragraph(pages[1],r.deposit,fonts,y,3,'el abono')-9;paragraph(pages[1],r.final,fonts,y,3,'el pago final');
 // Keep the last paragraph clear of the original footer even with long amounts.
 const finalLines=wrap(r.final,fonts,10.15,516).length;if(y-(finalLines-1)*13.5<73)throw Error('Los importes ocupan demasiado espacio en la plantilla. Revisa los datos.');
 [r.company,'NIT '+v.nit,r.rep,'C.C '+v.identity].forEach((text,i)=>signatureLine(pages[3],text,373.3-i*15.7,fonts.bold));
 pdf.setTitle(`Contrato JAC - ${v.municipality}`);pdf.setAuthor('JAC Music');pdf.setSubject('Contrato de presentación artística');pdf.setKeywords([]);
 return pdf.save();
}
