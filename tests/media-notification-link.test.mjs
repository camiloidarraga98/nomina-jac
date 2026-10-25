import test,{before} from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
let links,navigation;
before(async()=>{
 const compiled=await build({stdin:{contents:"export * from './lib/media-notification-link';export * from './lib/payroll-navigation';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
 links=navigation=await import('data:text/javascript;base64,'+Buffer.from(compiled.outputFiles[0].contents).toString('base64'));
});
test('los enlaces de Fotografía aceptan solo una carpeta privada y conservan su destino para iniciar sesión',()=>{
 const id='r2_77777777-7777-4777-8777-777777777777';assert.equal(links.mediaNotificationFolder(id),id);assert.equal(links.mediaFolderHref(id),'/fotografia?carpeta='+id);
 for(const value of [undefined,null,{},[id],'jac_r2_root','../archivo','//evil.invalid',id+'?extra=1','r2_'+id]){assert.equal(links.mediaNotificationFolder(value),undefined);assert.equal(links.mediaFolderHref(value),'/fotografia');}
 const login='/acceso?returnTo='+encodeURIComponent(links.mediaFolderHref(id));assert.equal(new URL(login,'https://fixture.invalid').searchParams.get('returnTo'),links.mediaFolderHref(id));
});
test('una cuenta solo de Fotografía puede activar sus avisos sin recibir otros módulos',()=>{
 const user={isOwner:false,sections:['media']};assert.equal(navigation.canViewSection(user,'notificaciones'),true);assert.equal(navigation.canViewSection(user,'fotografia'),true);
 for(const view of ['itinerarios','alertas','conexiones','quincena','crm'])assert.equal(navigation.canViewSection(user,view),false);
 assert.equal(navigation.canViewSection({...user,sections:[]},'notificaciones'),false);assert.equal(navigation.canViewSection({...user,sections:['music']},'notificaciones'),false);
});
