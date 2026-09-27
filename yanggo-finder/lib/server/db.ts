import 'server-only';
import {healthReady,type HealthStep} from './health-probe';
import {createServerClient} from './supabase-client.mjs';
import {connectionConfig} from './config.mjs';
export function configured(){return connectionConfig().issues.length===0}
export function db(){
 const c=connectionConfig();
 if(c.issues.length)throw Error('서버 연결 설정이 필요해요.');
 return createServerClient(c.url,c.secret);
}
export async function rpc(name:string,args:Record<string,unknown>={}){
 const {data,error,status}=await db().rpc(name,args);
 if(error)throw Object.assign(new Error(error.message),{code:error.code,status});
 return data;
}
export async function ready(onStep?:(step:HealthStep)=>void){
 onStep?.('health_client');
 const supabase=db();
 onStep?.('health_rpc_call');
 const {data,error,status}=await supabase.rpc('yg_connection_health');
 onStep?.('health_rpc_response');
 if(error)throw Object.assign(new Error('Health RPC failed'),{code:error.code,status});
 onStep?.('health_shape');
 return healthReady(data);
}
