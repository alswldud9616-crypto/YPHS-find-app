import 'server-only';
import {cookies} from 'next/headers';
import {db,rpc} from './db';
import {digest,opaque,privateDigest} from './crypto';
export const COOKIE='yg_session';
export async function actor(){const token=(await cookies()).get(COOKIE)?.value;if(!token)return null;const {data,error}=await db().from('app_sessions').select('user_id').eq('token_hash',digest(token)).gt('expires_at',new Date().toISOString()).maybeSingle();if(error)throw Error('로그인 정보를 확인하지 못했어요.');return data?.user_id||null}
export async function requireActor(){const id=await actor();if(!id)throw Error('로그인이 필요해요.');return id as string}
export async function session(user:string){const token=opaque();const {error}=await db().from('app_sessions').insert({user_id:user,token_hash:digest(token),expires_at:new Date(Date.now()+12*3600000).toISOString()});if(error)throw Error('로그인을 완료하지 못했어요.');(await cookies()).set(COOKIE,token,{httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'strict',path:'/',maxAge:43200});}
export function sameOrigin(req:Request){if(!process.env.APP_ORIGIN||req.headers.get('origin')!==new URL(process.env.APP_ORIGIN).origin)throw Error('요청한 주소를 확인해주세요.');}
export async function limit(key:string,maximum=5){const allowed=await rpc('yg_rate_limit',{p_key:privateDigest(key),p_max:maximum});if(!allowed)throw Error('시도 횟수를 초과했어요. 15분 후 다시 시도해주세요.');}
export function networkKey(req:Request){return process.env.VERCEL?req.headers.get('x-vercel-forwarded-for')?.split(',')[0]||'shared':'shared';}
