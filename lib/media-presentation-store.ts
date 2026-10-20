import {database} from '@/db/raw';
import {mediaGuardActive,type MediaGuard} from './media-drive';
import {MediaFailure} from './media-core';
export type MediaPresentation={file_id:string;source_key:string;connection_version:number;preview_key:string;stream_uid:string;stream_status:string;stream_host:string;claim:string;claim_at:string;updated_at:string};
let initialized=false;
export async function ensurePresentations(g:MediaGuard){
 if(initialized)return;
 if(!await mediaGuardActive(g))throw new MediaFailure('Tu sesión cambió.',403);
 await database().prepare('SELECT file_id FROM jac_media_presentations LIMIT 0').all();
 initialized=true;
}
export async function presentation(id:string){
 return database().prepare('SELECT * FROM jac_media_presentations WHERE file_id=?').bind(id).first<MediaPresentation>();
}
