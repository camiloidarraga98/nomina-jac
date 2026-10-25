import {database} from '@/db/raw';
import {sectionSql} from './payroll-permissions';
import {decryptMail} from './payroll-mail-core';
import {mailKey} from './payroll-mail';
import {pushCredentials} from './notifications';
import {applePushRequest,webPushRequest,type WebSubscription} from './notifications-core';

export const MEDIA_FOLDER_QUIET_MS=120_000;
const ROOT='jac_r2_root',FOLDER='application/vnd.google-apps.folder';
const now=()=>new Date().toISOString();
export const mediaFolderPushContent=(name:string)=>({title:'¡Nuevas fotos disponibles!',body:`Ya está disponible la carpeta «${name}».`});

// Expressions below contain only our fixed SQL aliases. Reaching the private
// root is mandatory; cycles, missing ancestors, and deletion tombstones fail
// closed. A new connection revision cannot publish an older candidate.
const liveFolder=(n='n')=>`EXISTS(SELECT 1 FROM jac_media_r2_connection c WHERE c.id='jac' AND c.enabled=1 AND c.version=${n}.connection_version) AND EXISTS(
 WITH RECURSIVE ancestors(id,parent_id,depth) AS (
  SELECT id,parent_id,0 FROM jac_media_r2_entries WHERE id=${n}.folder_id AND mime_type='${FOLDER}'
  UNION ALL SELECT p.id,p.parent_id,a.depth+1 FROM jac_media_r2_entries p JOIN ancestors a ON p.id=a.parent_id WHERE p.mime_type='${FOLDER}' AND a.depth<23
 ) SELECT 1 FROM ancestors WHERE parent_id='${ROOT}' AND NOT EXISTS(
  SELECT 1 FROM ancestors a JOIN jac_media_operations d ON d.id='r2-delete:'||a.id AND d.kind IN ('r2-delete-folder','r2-delete-file')
 ))`;
const tree=(n='n')=>`WITH RECURSIVE folders(id) AS (
 SELECT ${n}.folder_id UNION SELECT e.id FROM jac_media_r2_entries e JOIN folders f ON e.parent_id=f.id
 WHERE e.mime_type='${FOLDER}' AND NOT EXISTS(SELECT 1 FROM jac_media_operations d WHERE d.id='r2-delete:'||e.id AND d.kind IN ('r2-delete-folder','r2-delete-file'))
)`;
// Entry timestamps are written when the verified original is published, rather
// than when its potentially long multipart upload began. Thumbnail completion
// also extends the quiet interval. Pending uploads block even if another file
// is already usable; an active finalization/thumbnail lease blocks as well.
const settledFolder=(n='n')=>`EXISTS(${tree(n)} SELECT max(e.modified_at) FROM jac_media_r2_entries e JOIN folders f ON e.parent_id=f.id
 JOIN jac_media_operations o ON o.drive_id=e.id AND o.parent_id=e.parent_id AND o.kind='r2-upload' AND o.connection_version=${n}.connection_version AND o.status='ready' AND o.offset=o.size
 WHERE (e.mime_type LIKE 'image/%' OR e.mime_type LIKE 'video/%') AND e.size>0 AND e.object_key<>''
 AND NOT EXISTS(SELECT 1 FROM jac_media_operations d WHERE d.id='r2-delete:'||e.id AND d.kind IN ('r2-delete-folder','r2-delete-file'))
 HAVING max(e.modified_at)<=?) AND NOT EXISTS(${tree(n)} SELECT 1 FROM jac_media_operations o JOIN folders f ON o.parent_id=f.id
 WHERE o.kind='r2-upload' AND o.connection_version=${n}.connection_version AND ((o.status='pending' AND o.expires_at>?) OR (o.claim<>'' AND o.claim_at>?)))`;
const settledBindings=()=>[new Date(Date.now()-MEDIA_FOLDER_QUIET_MS).toISOString(),now(),new Date(Date.now()-180_000).toISOString()];
const eligibleDevice=`d.enabled=1 AND u.active=1 AND u.password_hash<>'' AND ${sectionSql('u','media')} AND s.id=d.session_id AND s.user_id=u.id AND s.user_version=u.version AND (s.persistent=1 OR s.expires_at>?)`;

export async function publishMediaFolderNotifications(){
 const db=database();
 await db.prepare(`UPDATE jac_media_folder_notifications AS n SET status='disabled' WHERE status='waiting' AND NOT (${liveFolder()})`).run();
 const candidates=(await db.prepare(`SELECT n.id FROM jac_media_folder_notifications n WHERE n.status='waiting' AND ${liveFolder()} AND ${settledFolder()} ORDER BY n.created_at,n.id LIMIT 12`).bind(...settledBindings()).all<{id:string}>()).results;
 for(const {id} of candidates){
  const stamp=now();
  // Revalidate and snapshot devices in one D1 transaction. The publication
  // token prevents a concurrent/replayed cron from adding later recipients.
  const publication=crypto.randomUUID();
  await db.batch([
   db.prepare(`UPDATE jac_media_folder_notifications AS n SET status=?,published_at=? WHERE n.id=? AND n.status='waiting' AND ${liveFolder()} AND ${settledFolder()}`).bind(publication,stamp,id,...settledBindings()),
   db.prepare(`INSERT OR IGNORE INTO jac_media_folder_push_deliveries(id,event_id,device_id,user_id,user_version,session_id,updated_at)
    SELECT n.id||'|'||d.id,n.id,d.id,u.id,u.version,d.session_id,? FROM jac_media_folder_notifications n CROSS JOIN jac_push_devices d
    JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN payroll_sessions s ON s.id=d.session_id
    WHERE n.id=? AND n.status=? AND ${eligibleDevice}`).bind(stamp,id,publication,stamp),
   db.prepare("UPDATE jac_media_folder_notifications SET status='published' WHERE id=? AND status=?").bind(id,publication),
  ]);
 }
}

type Delivery={id:string;event_id:string;device_id:string;user_id:string;platform:string;data:string};
export async function dispatchMediaFolderPush(){
 const db=database();
 // A lost provider response is terminal, just as for itinerary/alert pushes.
 await db.prepare("UPDATE jac_media_folder_push_deliveries SET status='uncertain',updated_at=? WHERE status='sending' AND updated_at<?").bind(now(),new Date(Date.now()-120_000).toISOString()).run();
 const rows=(await db.prepare(`SELECT p.id,p.event_id,p.device_id,p.user_id,d.platform,d.data FROM jac_media_folder_push_deliveries p JOIN jac_push_devices d ON d.id=p.device_id WHERE p.status='pending' ORDER BY p.updated_at,p.id LIMIT 24`).all<Delivery>()).results;
 if(!rows.length)return;
 const keys=await pushCredentials();
 // Keep four outgoing requests in flight within Workers' connection limit.
 for(let start=0;start<rows.length;start+=4)await Promise.all(rows.slice(start,start+4).map(async row=>{
  const claimed=await db.prepare("UPDATE jac_media_folder_push_deliveries SET status='sending',updated_at=? WHERE id=? AND status='pending'").bind(now(),row.id).run();if(claimed.meta.changes!==1)return;
  let state='uncertain';
  const active=()=>db.prepare(`SELECT n.folder_id,e.name,(${settledFolder()}) AS settled FROM jac_media_folder_push_deliveries p
   JOIN jac_media_folder_notifications n ON n.id=p.event_id AND n.status='published' JOIN jac_media_r2_entries e ON e.id=n.folder_id
   JOIN jac_push_devices d ON d.id=p.device_id AND d.user_id=p.user_id AND d.user_version=p.user_version AND d.session_id=p.session_id
   JOIN payroll_users u ON u.id=d.user_id AND u.version=d.user_version JOIN payroll_sessions s ON s.id=d.session_id
   WHERE p.id=? AND p.status='sending' AND d.id=? AND d.data=? AND d.platform=? AND ${eligibleDevice} AND ${liveFolder()}`).bind(...settledBindings(),row.id,row.device_id,row.data,row.platform,now()).first<{folder_id:string;name:string;settled:number}>();
  try{
   const folder=await active();
   if(!folder)state='disabled';else if(!folder.settled)state='pending';else{
    const data=await decryptMail<Record<string,string>|WebSubscription>(row.data,mailKey());
    // Preserve the configured environment-specific key and legacy Sandbox
    // fallback. A Sandbox-only key can never send to Production.
    const apple=row.platform==='ios'?((data as Record<string,string>).environment==='sandbox'?keys.apnsSandbox??keys.apns:keys.apns):undefined;
    if(row.platform==='ios'?!apple:row.platform!=='web'||!keys.web)state='unconfigured';else{
     const target={kind:'media_folder' as const,folderId:folder.folder_id},content=mediaFolderPushContent(folder.name);
     const request=row.platform==='ios'?await applePushRequest((data as Record<string,string>).token,(data as Record<string,string>).environment,apple!,row.event_id,content,target):await webPushRequest(data as WebSubscription,keys.web!,JSON.stringify({id:row.event_id,...target,...content}));
     // Signing/encryption can yield. Recheck pending uploads, tombstones,
     // connection revision, account grants and the exact session before I/O.
     const current=await active();
     if(!current)state='disabled';else if(!current.settled)state='pending';else{
      const response=await fetch(request.url,request.options);state=response.ok?'sent':response.status===404||response.status===410?'expired':'failed';
      await response.body?.cancel();
      if(state==='expired')await db.prepare('UPDATE jac_push_devices SET enabled=0 WHERE id=? AND data=?').bind(row.device_id,row.data).run();
     }
    }
   }
  }catch{/* The provider may have accepted it; never silently resend. */}
  await db.prepare("UPDATE jac_media_folder_push_deliveries SET status=?,updated_at=? WHERE id=? AND status='sending'").bind(state,now(),row.id).run();
 }));
}

export async function processMediaFolderNotifications(){await publishMediaFolderNotifications();await dispatchMediaFolderPush();}
