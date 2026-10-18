import {env} from 'cloudflare:workers';

// The independent deployment must never trust Sites identity headers supplied
// by a visitor. Its only login is JAC's existing session/password mechanism.
export function directCloudflare(){return env.JAC_HOSTING==='cloudflare';}
