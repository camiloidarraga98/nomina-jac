import type {AccessUser} from './payroll-permissions';
const editors=['camilo@mac2you.co','info@jacmusic.co','contabilidad@jacmusic.co'];
// Authentication already verifies an active, current session. Calendar editing is
// independent of payroll modification and is available to administrators, Luisa and Paula.
export function canEditAgenda(user:AccessUser){return !user.legacy&&!user.itinerariesOnly&&(user.isOwner||editors.includes(user.email.trim().toLowerCase()));}
