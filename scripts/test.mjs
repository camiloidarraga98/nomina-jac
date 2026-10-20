import {mkdir,readdir} from 'node:fs/promises';
import {spawn} from 'node:child_process';
await mkdir('work/local',{recursive:true});
const domains=process.argv.slice(2);
if(domains.some(domain=>!/^[-a-z0-9]+$/.test(domain)))throw new Error('Usa nombres de módulos, por ejemplo payroll, media o music.');
const files=(await readdir('tests')).filter(file=>file.endsWith('.test.mjs')&&(!domains.length||domains.some(domain=>file===domain+'.test.mjs'||file.startsWith(domain+'-')))).sort();
if(!files.length)throw new Error('No se encontraron pruebas para esos módulos.');
const child=spawn(process.execPath,['--test','--test-concurrency=3',...files.map(file=>'tests/'+file)],{stdio:'inherit'});
child.on('exit',(code,signal)=>{if(signal)process.kill(process.pid,signal);else process.exitCode=code??1;});
