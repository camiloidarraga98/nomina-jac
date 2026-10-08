// Dates are civil days in Colombia; never use the browser/device timezone.
export const BOARDING_CHANNELS=[{id:'C0C7QKT2FJQ',name:'#pases-camilo'},{id:'C0C8FAPHTCG',name:'#pases-jhon-alex'},{id:'C0C7K0QCMKQ',name:'#pases-alex'}] as const;
export function boardingToday(at=new Date()){return new Intl.DateTimeFormat('en-CA',{timeZone:'America/Bogota',year:'numeric',month:'2-digit',day:'2-digit'}).format(at);}
export function validBoardingDate(s:string){if(!/^20\d{2}-\d{2}-\d{2}$/.test(s))return false;const d=new Date(s+'T12:00:00Z');return !Number.isNaN(d.valueOf())&&d.toISOString().slice(0,10)===s;}
const months=['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
// Without a year use the closest occurrence to receipt day (previous/current/next year).
// Invalid or multiple dates require a corrected filename, never silent guessing.
export function boardingFilenameDate(filename:string,at=new Date()):string|null{
 const text=filename.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 const matches=[...text.matchAll(/(?:^|[^\d])(\d{1,2})\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)(?:\s+(?:de\s+)?(20\d{2}))?(?=$|[^a-z0-9])/g)];
 if(matches.length!==1)return null;const [,day,month,year]=matches[0],m=month==='setiembre'?9:months.indexOf(month)+1;
 const y=Number(boardingToday(at).slice(0,4)),build=(n:number)=>String(n)+'-'+String(m).padStart(2,'0')+'-'+day.padStart(2,'0');
 if(year){const date=build(Number(year));return validBoardingDate(date)?date:null;}
 const reference=new Date(boardingToday(at)+'T12:00:00Z').valueOf();
 return [y-1,y,y+1].map(build).filter(validBoardingDate).sort((a,b)=>Math.abs(Date.parse(a)-reference)-Math.abs(Date.parse(b)-reference)||b.localeCompare(a))[0]??null;
}
export function boardingDateLabel(s:string){return new Intl.DateTimeFormat('es-CO',{dateStyle:'full',timeZone:'America/Bogota'}).format(new Date(s+'T12:00:00Z'));}
