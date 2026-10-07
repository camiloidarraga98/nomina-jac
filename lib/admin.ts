import {getChatGPTUser} from '@/app/chatgpt-auth';
import {isAdminEmail} from './admin-policy';
export async function isAdmin(){return isAdminEmail((await getChatGPTUser())?.email)}
export const privateHeaders={'Cache-Control':'private, no-store, max-age=0','X-Robots-Tag':'noindex, nofollow','Vary':'Cookie'};
