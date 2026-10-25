import {database} from '@/db/raw';
import {processMediaPresentations} from './media-stream';
import {cleanupMusic} from './music-store';
import {processMailQueue} from './payroll-mail';
import {importSlackFiles,purgeNoticeAttachments} from './notifications';
import {processBirthdayJobs} from './fans-birthday';
import {processProspectQueue,processProspectReplyQueue} from './crm-prospects-store';
import {processMediaFolderNotifications} from './media-folder-notifications';

// Only work already durably requested by users is eligible. Provider results
// marked uncertain are never reset or resent by this runner.
export async function runMaintenance(){
 const started=Date.now();
 const tasks=[
  ['media',()=>processMediaPresentations()],
  ['media-folder-push',()=>processMediaFolderNotifications()],
  ['music-cleanup',()=>cleanupMusic()],
  ['payroll-mail',()=>processMailQueue()],
  ['crm-prospects',async()=>{await processProspectQueue();await processProspectReplyQueue();}],
  ['notices',()=>importSlackFiles()],
  ['attachments',()=>purgeNoticeAttachments()],
  ['fan-birthday',()=>processBirthdayJobs()],
 ] as const;
 const outcomes=await Promise.allSettled(tasks.map(async([queue,run])=>{await run();return queue;}));
 const queues=outcomes.map((result,index)=>({queue:tasks[index][0],status:result.status==='fulfilled'?'completed':'failed'}));
 const backlog=await database().batch([
  database().prepare("SELECT 'payroll-mail' AS queue,count(*) AS pending,min(b.created_at) AS oldest FROM payroll_mail_jobs j JOIN payroll_mail_batches b ON b.id=j.batch_id WHERE j.status='pending'"),
  database().prepare("SELECT 'crm-prospects' AS queue,count(*) AS pending,min(created_at) AS oldest FROM jac_crm_prospect_deliveries WHERE status='pending'"),
  database().prepare("SELECT 'notices' AS queue,count(*) AS pending,min(created_at) AS oldest FROM jac_slack_files WHERE status='pending'"),
  database().prepare("SELECT 'push' AS queue,count(*) AS pending,min(updated_at) AS oldest FROM jac_push_deliveries WHERE status='pending'"),
  database().prepare("SELECT 'media-folder-push' AS queue,count(*) AS pending,min(updated_at) AS oldest FROM jac_media_folder_push_deliveries WHERE status='pending'"),
  database().prepare("SELECT 'music-cleanup' AS queue,count(*) AS pending,min(created_at) AS oldest FROM jac_music_tracks WHERE status IN ('deleted','cancelled')"),
 ]).then(rows=>rows.flatMap(row=>row.results as {queue:string;pending:number;oldest:string|null}[]).map(row=>({queue:String(row.queue),pending:Number(row.pending),oldestAgeSeconds:typeof row.oldest==='string'?Math.max(0,Math.floor((Date.now()-Date.parse(row.oldest))/1000)):0}))).catch(()=>[]);
 console.log(JSON.stringify({event:'jac-maintenance',durationMs:Date.now()-started,queues,backlog}));
 return {queues,backlog};
}
