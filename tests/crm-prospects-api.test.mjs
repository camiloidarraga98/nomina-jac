import test,{beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';

const fixture={user:null,active:true,calls:[],brochure:null,error:null};
globalThis.__prospectApi=fixture;
const output=await build({stdin:{resolveDir:process.cwd(),contents:"export {GET,POST} from './app/api/crm/prospects/route';export {ProspectMailFailure} from '@/lib/crm-prospects-mail';"},bundle:true,platform:'node',format:'esm',write:false,plugins:[{name:'private-prospect-api-fixtures',setup(b){
 b.onResolve({filter:/^@\/lib\/(payroll-access|crm-access|crm-store|crm-prospects-store|crm-prospects-oauth|crm-prospects-mail)$/},args=>({path:args.path,namespace:'fixture'}));
 b.onLoad({filter:/.*/,namespace:'fixture'},args=>({loader:'js',contents:args.path.endsWith('payroll-access')?"export const payrollUser=async()=>globalThis.__prospectApi.user;export const payrollHeaders={'Cache-Control':'private, no-store, max-age=0','Vary':'Cookie','X-Content-Type-Options':'nosniff'};":args.path.endsWith('crm-access')?"export const crmGuard=()=>({sql:'fixture',bindings:[]});":args.path.endsWith('crm-store')?"export const guardActive=async()=>globalThis.__prospectApi.active;":args.path.endsWith('crm-prospects-mail')?"export class ProspectMailFailure extends Error{constructor(message,status=502){super(message);this.status=status;}}":args.path.endsWith('crm-prospects-oauth')?"export const startProspectMailOauth=async()=>{globalThis.__prospectApi.calls.push('connectTracking');return {url:'https://accounts.google.com/fixture',cookie:'fixture-state=opaque; HttpOnly; Secure; SameSite=Lax'};};":`
 const run=async(name,...args)=>{globalThis.__prospectApi.calls.push(name);if(globalThis.__prospectApi.error)throw globalThis.__prospectApi.error;return {operation:name,ok:true};};
 export const prospectsFeed=(...args)=>run('feed',...args),prospectDetail=(...args)=>run('detail',...args),prospectBatch=(...args)=>run('batch',...args),saveProspect=(...args)=>run('saveProspect',...args),previewProspects=(...args)=>run('preview',...args),queueProspectBatch=(...args)=>run('queueBatch',...args),cancelProspectBatch=(...args)=>run('cancelBatch',...args),checkProspectReplies=(...args)=>run('checkReplies',...args),markProspectReply=(...args)=>run('markReply',...args);
 export const prospectBrochure=async()=>{globalThis.__prospectApi.calls.push('brochure');return globalThis.__prospectApi.brochure;};
 `}));
}}]});
const api=await import('data:text/javascript;base64,'+Buffer.from(output.outputFiles[0].contents).toString('base64'));
const base='https://crm.example.invalid';
const owner={id:'fixture-admin',email:'owner@example.invalid',username:'fixture',displayName:'Ficticio',fullName:null,isOwner:true,permissions:[]};
const request=(method='GET',query='',body,headers={})=>new Request(base+'/api/crm/prospects'+query,{method,headers:{...(method==='POST'?{Origin:base,'Content-Type':'application/json'}:{}),...headers},...(body===undefined?{}:{body:typeof body==='string'?body:JSON.stringify(body)})});
beforeEach(()=>{fixture.user={...owner};fixture.active=true;fixture.calls=[];fixture.brochure=null;fixture.error=null;});

test('prospect API refuses anonymous, legacy and non-CRM access before touching private data or mail',async()=>{
 for(const user of [null,{...owner,legacy:true},{...owner,isOwner:false},{...owner,mediaOnly:true}]){
  fixture.user=user;
  for(const req of [request(),request('GET','?brochure=fixture'),request('POST','',{action:'queueBatch',record:{id:crypto.randomUUID()}})]){
   const response=await api[req.method](req);assert([401,403].includes(response.status));assert.match(response.headers.get('cache-control'),/private, no-store/);
  }
 }
 assert.deepEqual(fixture.calls,[]);
});

test('prospect writes require exact origin, bounded valid JSON and an active CRM guard',async()=>{
 for(const headers of [{Origin:'https://other.example.invalid'},{Origin:''},{'sec-fetch-site':'cross-site'}])assert.equal((await api.POST(request('POST','',{action:'queueBatch'},headers))).status,403);
 for(const [body,headers,status] of [['{',{},400],['[]',{},400],['{}',{},400],[JSON.stringify({action:'preview'}),{'Content-Type':'text/plain'},400],['x',{'Content-Length':'65537'},413],['x'.repeat(65537),{},413]])assert.equal((await api.POST(request('POST','',body,headers))).status,status);
 fixture.active=false;assert.equal((await api.POST(request('POST','',{action:'queueBatch',record:{}}))).status,403);
 assert.deepEqual(fixture.calls,[]);
});

test('preview and queue are separate explicit operations and unsupported actions cannot reach mail',async()=>{
 for(const action of ['saveProspect','preview','queueBatch','cancelBatch','checkReplies','markReply']){
  const response=await api.POST(request('POST','',{action,record:{fixture:true}}));assert.equal(response.status,200);assert.equal((await response.json()).operation,action);
 }
 const calls=fixture.calls.slice();
 for(const action of ['send','__proto__','constructor'])assert.equal((await api.POST(request('POST','',{action}))).status,400);
 assert.deepEqual(fixture.calls,calls);
 const connection=await api.POST(request('POST','',{action:'connectTracking'}));assert.equal(connection.status,200);assert.match(connection.headers.get('set-cookie'),/HttpOnly; Secure/);assert.equal((await connection.json()).url,'https://accounts.google.com/fixture');
});

test('private feed, detail, batch and brochure routes preserve download headers and revalidate access',async()=>{
 for(const [query,operation] of [['','feed'],['?id=fixture','detail'],['?batch=fixture','batch']]){
  const response=await api.GET(request('GET',query));assert.equal(response.status,200);assert.equal((await response.json()).operation,operation);
 }
 const bytes=new TextEncoder().encode('%PDF-1.4\nSYNTHETIC ONLY\n%%EOF');
 for(const download of [false,true]){
  fixture.brochure={object:{body:new Blob([bytes]).stream()},filename:'Fixture.pdf',size:bytes.length};
  const response=await api.GET(request('GET','?brochure=fixture'+(download?'&download=1':'')));assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),'application/pdf');assert.match(response.headers.get('content-disposition'),download?/^attachment;/:/^inline;/);assert.equal(response.headers.get('cross-origin-resource-policy'),'same-origin');assert.deepEqual(new Uint8Array(await response.arrayBuffer()),bytes);
 }
 let cancelled=0;fixture.brochure={object:{body:new ReadableStream({cancel(){cancelled++;}})},size:0};fixture.active=false;
 assert.equal((await api.GET(request('GET','?brochure=fixture'))).status,403);assert.equal(cancelled,1);
});

test('Gmail permission errors retain their actionable message without being mistaken for revoked CRM access',async()=>{
 fixture.error=new api.ProspectMailFailure('Vuelve a autorizar el seguimiento de respuestas.',403);
 const response=await api.POST(request('POST','',{action:'checkReplies'}));assert.equal(response.status,409);assert.equal((await response.json()).error,'Vuelve a autorizar el seguimiento de respuestas.');
});
