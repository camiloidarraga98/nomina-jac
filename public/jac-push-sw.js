/* No private documents, sessions or API responses are cached. */
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('push',event=>{
 let data;try{data=event.data.json();}catch{return;}
 if(!data||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(data.id))return;
 const title=typeof data.title==='string'&&data.title.trim()&&data.title.length<=120?data.title:'JAC';
 const body=typeof data.body==='string'&&data.body.trim()&&data.body.length<=2001?data.body:'Tienes un aviso nuevo. Abre JAC para consultarlo.';
 event.waitUntil(self.registration.showNotification(title,{body,icon:'/jac-app-icon.png',badge:'/jac-app-icon.png',tag:'jac-'+data.id,renotify:false,data:{id:data.id}}));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();const id=event.notification.data?.id;if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id??''))return;
 const url=new URL('/?jac-notice='+encodeURIComponent(id),self.location.origin).href;
 event.waitUntil((async()=>{const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});const existing=windows.find(w=>new URL(w.url).origin===self.location.origin);if(existing){await existing.navigate(url);await existing.focus();}else await self.clients.openWindow(url);})());
});
