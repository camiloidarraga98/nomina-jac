import {database} from '@/db/raw';
import {mediaGuardActive,type MediaGuard} from './media-drive';
import {MediaFailure} from './media-core';
export type MediaPresentation={file_id:string;source_key:string;connection_version:number;preview_key:string;stream_uid:string;stream_status:string;stream_host:string;claim:string;claim_at:string;updated_at:string};
let initialized=false;
export async function ensurePresentations(g:MediaGuard){
 if(initialized)return;
 if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión cambió.',403);
 await database().prepare("CREATE TABLE IF NOT EXISTS jac_media_presentations(file_id TEXT PRIMARY KEY NOT NULL,source_key TEXT NOT NULL,connection_version INTEGER NOT NULL,preview_key TEXT NOT NULL DEFAULT '',stream_uid TEXT NOT NULL DEFAULT '',stream_status TEXT NOT NULL DEFAULT '',stream_host TEXT NOT NULL DEFAULT 'videodelivery.net',claim TEXT NOT NULL DEFAULT '',claim_at TEXT NOT NULL DEFAULT '',updated_at TEXT NOT NULL)").run();
 initialized=true;
}
export async function presentation(id:string){
 const exists=await database().prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='jac_media_presentations'").first();
 return exists?database().prepare('SELECT * FROM jac_media_presentations WHERE file_id=?').bind(id).first<MediaPresentation>():null;
}
