import {scrypt,randomBytes,createHmac,timingSafeEqual,createCipheriv,createDecipheriv,createHash} from 'node:crypto';
import {promisify} from 'node:util';
const derive=promisify(scrypt);
const pepper=()=>{const p=process.env.PIN_PEPPER;if(!p||p.length<32)throw Error('PIN_PEPPER must contain at least 32 characters');return p};
export const digest=(s:string)=>createHash('sha256').update(s).digest('hex');
export const opaque=()=>randomBytes(32).toString('base64url');
export const privateDigest=(s:string)=>createHmac('sha256',pepper()).update(s).digest('hex');
export async function hashPin(pin:string){if(!/^\d{6}$/.test(pin))throw Error('비밀번호는 숫자 6자리로 입력해주세요.');const salt=randomBytes(16).toString('hex');const key=await derive(privateDigest(pin),salt,64) as Buffer;return `scrypt$${salt}$${key.toString('hex')}`}
export async function verifyPin(pin:string,hash:string){const [,salt,key]=hash.split('$');if(!salt||!key)return false;const calculated=await derive(privateDigest(pin),salt,64) as Buffer;const expected=Buffer.from(key,'hex');return calculated.length===expected.length&&timingSafeEqual(calculated,expected)}
function encKey(){const k=Buffer.from(process.env.DATA_ENCRYPTION_KEY||'','hex');if(k.length!==32)throw Error('DATA_ENCRYPTION_KEY must be 32 bytes hex');return k}
export function encrypt(s:string){const iv=randomBytes(12);const c=createCipheriv('aes-256-gcm',encKey(),iv);return [iv.toString('hex'),Buffer.concat([c.update(s,'utf8'),c.final()]).toString('hex'),c.getAuthTag().toString('hex')].join('.')}
export function decrypt(s:string){const [iv,body,tag]=s.split('.');const c=createDecipheriv('aes-256-gcm',encKey(),Buffer.from(iv,'hex'));c.setAuthTag(Buffer.from(tag,'hex'));return Buffer.concat([c.update(Buffer.from(body,'hex')),c.final()]).toString('utf8')}
export const pickupCode=()=>`YG-${randomBytes(4).toString('hex').toUpperCase()}`;
