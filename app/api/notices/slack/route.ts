import {waitUntil} from 'cloudflare:workers';
import {pushCredentials,queueSlackFiles,importSlackFiles} from '@/lib/notifications';
import {BOARDING_CHANNELS} from '@/lib/boarding-passes';
import {ITINERARY_CHANNEL,ITINERARY_TEAM,verifySlack} from '@/lib/notifications-core';
export const dynamic='force-dynamic';
export async function POST(req:Request){
 try{
  const raw=await req.text();if(raw.length>250000)return new Response(null,{status:413});const credentials=await pushCredentials();
  if(!credentials.slack||!await verifySlack(raw,req.headers.get('x-slack-request-timestamp')??'',req.headers.get('x-slack-signature')??'',credentials.slack.signingSecret))return new Response(null,{status:401});
  const body=JSON.parse(raw);if(body.team_id&&body.team_id!==ITINERARY_TEAM)return new Response(null,{status:403});
  if(body.type==='url_verification'&&typeof body.challenge==='string'&&body.challenge.length<=200)return Response.json({challenge:body.challenge});
  const e=body.event;if(body.type!=='event_callback'||body.team_id!==ITINERARY_TEAM||e?.type!=='message'||(e.channel!==ITINERARY_CHANNEL&&!BOARDING_CHANNELS.some(c=>c.id===e.channel))||e.subtype==='message_changed'||e.subtype==='message_deleted')return Response.json({ok:true});
  const ids=[...new Set((Array.isArray(e.files)?e.files:[]).filter((f:{id?:unknown;mimetype?:unknown})=>typeof f.id==='string'&&/^F[A-Z0-9]{6,30}$/.test(f.id)&&(f.mimetype==='application/pdf'||(e.channel!==ITINERARY_CHANNEL&&['image/jpeg','image/png'].includes(String(f.mimetype))))).map((f:{id:string})=>f.id))].slice(0,5) as string[];
  await queueSlackFiles(ids,e.channel);if(ids.length)waitUntil(importSlackFiles().catch(()=>{}));return Response.json({ok:true});
 }catch{return new Response(null,{status:503});}
}
