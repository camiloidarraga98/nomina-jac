import {database} from '@/db/raw';
import {CrmFailure} from './crm-core';
import type {CrmGuard} from './crm-access';

type Contact={id:string;name:string;version:number};
type ShowContact=CrmGuard&{id:string;name:string;create:boolean};
const normalized=(name:string)=>name.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('es').replace(/\s+/g,' ').trim();

// Resolve first; publish the contact only inside the batch that saves the show.
export async function resolveShowContact(name:string,selectedID:string):Promise<ShowContact>{
 const db=database();
 if(selectedID){
  const contact=await db.prepare('SELECT id,name,version FROM jac_crm_contacts WHERE id=?').bind(selectedID).first<Contact>();
  if(!contact)throw new CrmFailure('Ese empresario no está disponible.');
  return {...contact,create:false,sql:'EXISTS(SELECT 1 FROM jac_crm_contacts WHERE id=? AND version=?)',bindings:[contact.id,contact.version]};
 }
 const clean=name.replace(/\s+/g,' ').trim();
 if(!clean)return {id:'',name:'',create:false,sql:'1=1',bindings:[]};
 const contacts=(await db.prepare('SELECT id,name,version FROM jac_crm_contacts ORDER BY id LIMIT 1001').all<Contact>()).results;
 if(contacts.length>1000)throw new CrmFailure('Hay demasiados empresarios para este listado.',413);
 const existing=contacts.find(c=>normalized(c.name)===normalized(clean));
 if(!existing&&contacts.length===1000)throw new CrmFailure('El directorio alcanzó el límite de empresarios.',413);
 // Contact writes always increment version and contacts cannot be deleted.
 // Check this snapshot in the transaction so two simultaneous shows cannot
 // both create a new card. A changed directory is resolved again locally.
 return {id:existing?.id??crypto.randomUUID(),name:existing?.name??clean,create:!existing,
  sql:'(SELECT count(*) FROM jac_crm_contacts)=? AND (SELECT COALESCE(sum(version),0) FROM jac_crm_contacts)=?',
  bindings:[contacts.length,contacts.reduce((n,c)=>n+c.version,0)]};
}

export function createShowContact(contact:ShowContact,showID:string,nonce:string,stamp:string,actorID:string){
 if(!contact.create)return [];
 const db=database(),saved='EXISTS(SELECT 1 FROM jac_crm_shows WHERE id=? AND write_nonce=?)';
 return [
  db.prepare(`INSERT INTO jac_crm_contacts(id,name,write_nonce,created_at,updated_at) SELECT ?,?,?,?,? WHERE ${saved}`).bind(contact.id,contact.name,nonce,stamp,stamp,showID,nonce),
  db.prepare(`INSERT INTO jac_crm_audit(id,show_id,actor_id,action,data,created_at) SELECT ?,?,?,?,?,? WHERE ${saved}`).bind(crypto.randomUUID(),'contact:'+contact.id,actorID,'contact-created-from-show',JSON.stringify({showId:showID}),stamp,showID,nonce)
 ];
}
