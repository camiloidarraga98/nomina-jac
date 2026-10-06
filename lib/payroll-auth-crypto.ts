import {randomBytes,scryptSync,timingSafeEqual,createHmac,createHash} from 'node:crypto';
export const SESSION_SECONDS=12*60*60;
export const randomToken=()=>randomBytes(32).toString('base64url');
export const tokenHash=(value:string)=>createHash('sha256').update(value).digest('hex');
export function passwordIssue(password:string){return password.length===0?'Ingresa una contraseña.':null;}
// scrypt parameters follow OWASP's 16 MiB / p=5 profile; the pepper is stored outside D1.
function digest(password:string,salt:string,pepper:string){if(pepper.length<32)throw new Error('Authentication secret unavailable');const key=scryptSync(password,salt,32,{N:16384,r:8,p:5,maxmem:64*1024*1024});return createHmac('sha256',pepper).update(key).digest();}
export function hashPassword(password:string,pepper:string){const issue=passwordIssue(password);if(issue)throw new Error(issue);const salt=randomBytes(16).toString('base64url');return `scrypt-v1:${salt}:${digest(password,salt,pepper).toString('base64url')}`;}
export function verifyPassword(password:string,stored:string,pepper:string){const [format,salt,hash]=stored.split(':');if(format!=='scrypt-v1'||!salt||!hash)return false;const expected=Buffer.from(hash,'base64url'),actual=digest(password,salt,pepper);return actual.length===expected.length&&timingSafeEqual(actual,expected);}
export function sessionCookie(token:string,secure=true,maxAge=SESSION_SECONDS){return `${secure?'__Host-jac_session':'jac_session'}=${token}; Path=/; HttpOnly; ${secure?'Secure; ':''}SameSite=Lax; Max-Age=${maxAge}`;}
export function sessionToken(cookie:string,secure=true){const name=secure?'__Host-jac_session':'jac_session';return cookie.split(';').map(x=>x.trim()).find(x=>x.startsWith(name+'='))?.slice(name.length+1)||'';}
