// Folder notification destinations are local, opaque IDs. Access is checked by
// the authenticated gallery API; a notification never grants folder access.
export function mediaNotificationFolder(value:unknown):string|undefined{
 return typeof value==='string'&&/^r2_[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value)?value:undefined;
}
export function mediaFolderHref(value?:string){
 const id=mediaNotificationFolder(value);
 return '/fotografia'+(id?'?carpeta='+encodeURIComponent(id):'');
}
