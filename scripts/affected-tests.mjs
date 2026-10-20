// Changes to common persistence/auth/build files need the complete regression
// set. Isolated modules select only their own suites; native CI is independent.
import {execFileSync} from 'node:child_process';
import {spawn} from 'node:child_process';
const files=execFileSync('git',['diff','--name-only',process.env.JAC_DIFF_BASE||'HEAD^','HEAD'],{encoding:'utf8'}).trim().split('\n');
const domains=new Set();let all=false;
for(const file of files){
 if(/^(docs\/|continuidad-|AGENTS|ios\/|macos\/)/.test(file))continue;
 if(/^(db\/|drizzle\/|worker\/|deploy\/|package|vite|scripts\/|\.github\/)/.test(file)||/payroll-(auth|permissions|store|section-guard)/.test(file)){all=true;break;}
 if(/media|fotograf/.test(file))domains.add('media');
 else if(/music|musica/.test(file))domains.add('music');
 else if(/crm/.test(file)){domains.add('crm');domains.add('contracts');}
 else if(/calendar|agenda/.test(file)){domains.add('calendar');domains.add('crm');}
 else if(/notif|notice|slack|push|boarding|itinerar/.test(file))domains.add('notifications');
 else if(/travel|expense/.test(file))domains.add('travel');
 else if(/payroll|show-costs|cop-input|users/.test(file))domains.add('payroll');
 else {all=true;break;}
}
if(!all&&!domains.size){console.log('Sin cambios web que comprobar.');process.exit(0);}
const child=spawn(process.execPath,['scripts/test.mjs',...(all?[]:[...domains])],{stdio:'inherit'});
child.on('exit',code=>{process.exitCode=code??1;});
