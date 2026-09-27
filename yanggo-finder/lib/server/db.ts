import 'server-only';
import {createServerClient} from './supabase-client.mjs';
import {connectionConfig} from './config.mjs';
export function configured(){return connectionConfig().issues.length===0}
export function db(){const c=connectionConfig();if(c.issues.length)throw Error('서버 연결 설정이 필요해요.');return createServerClient(c.url,c.secret)}
export async function rpc(name:string,args:Record<string,unknown>={}){const {data,error}=await db().rpc(name,args);if(error)throw Error(error.message);return data}
export async function ready(){const h=await rpc('yg_connection_health');return h.version===8&&h.rlsReady===true&&h.storageReady===true&&Number.isInteger(h.year)}
