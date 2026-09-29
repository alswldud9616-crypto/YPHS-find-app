import {createClient} from '@supabase/supabase-js';

// Temporary, read-only endpoint. No app DB, auth, or health modules.
export const runtime='nodejs';
export const dynamic='force-dynamic';
const headers={'Cache-Control':'no-store','Content-Type':'application/json; charset=utf-8','X-Yanggo-Ping':'direct-sdk-v1'};
const allowedCodes=new Set(['42501','42883','42P01','42703','22P02','57014','53300',
 'PGRST000','PGRST001','PGRST002','PGRST003','PGRST106','PGRST202','PGRST203','PGRST301','PGRST302','PGRST303']);
function safeStatus(value:unknown){return typeof value==='number'&&Number.isInteger(value)&&value>=0&&value<=599?value:null;}

export async function GET(){
 let phase:'env'|'client'|'rpc'|'rpc_result'='env';
 try{
  const url=(process.env.NEXT_PUBLIC_SUPABASE_URL??'').trim();
  const key=(process.env.SUPABASE_SECRET_KEY??'').trim();
  if(!url||!key)return Response.json({ok:false,hasError:true,errorCode:'ENV_MISSING',status:null,phase},{status:503,headers});
  phase='client';
  const supabase=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  phase='rpc';
  const {data,error,status}=await supabase.rpc('yg_connection_health');
  phase='rpc_result';
  if(error)return Response.json({ok:false,hasError:true,
   errorCode:allowedCodes.has(error.code)?error.code:'SDK_ERROR',status:safeStatus(status),phase},{status:502,headers});
  const hasData=data!==null&&data!==undefined;
  if(!hasData)return Response.json({ok:false,hasError:true,errorCode:'EMPTY_DATA',status:safeStatus(status),phase},{status:502,headers});
  return Response.json({ok:true,status:safeStatus(status),hasData:true},{headers});
 }catch(error){
  // Never log/return the original error, URL, key, headers, or stack.
  const name=error instanceof Error?error.name:'';
  const errorCode=name==='TypeError'?'JS_TYPE_ERROR':name==='AbortError'?'JS_ABORT_ERROR':'JS_THROW';
  return Response.json({ok:false,hasError:true,errorCode,status:null,phase},{status:502,headers});
 }
}
