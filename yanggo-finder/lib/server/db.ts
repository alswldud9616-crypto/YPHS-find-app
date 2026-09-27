import 'server-only';
import {probeHealth,type HealthStep,type TransportObserver} from './health-probe';
import {createServerClient} from './supabase-client.mjs';
import {connectionConfig} from './config.mjs';
export function configured(){return connectionConfig().issues.length===0}
export function db(observe?:TransportObserver){const c=connectionConfig();if(c.issues.length)throw Error('서버 연결 설정이 필요해요.');return createServerClient(c.url,c.secret,{observe})}
export async function rpc(name:string,args:Record<string,unknown>={}){const {data,error,status}=await db().rpc(name,args);if(error)throw Object.assign(new Error(error.message),{code:error.code,status});return data}
export async function ready(onStep?:(step:HealthStep)=>void){return probeHealth(observe=>db(observe),onStep)}
