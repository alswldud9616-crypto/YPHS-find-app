// Server/CLI only. Never import into a client component.
import {createClient} from '@supabase/supabase-js';
export function createServerClient(url,key,{fetch:transport=globalThis.fetch,observe=(_event)=>{}}={}){
 return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async(input,init)=>{
  observe({kind:'start'});
  try{
  const headers=new Headers(init?.headers);
  // New API keys are not JWTs. Keep the SDK's apikey header, remove only its
  // duplicate API-key Bearer fallback; never strip a real user JWT.
  if((key.startsWith('sb_secret_')||key.startsWith('sb_publishable_'))&&headers.get('authorization')===`Bearer ${key}`)headers.delete('authorization');
  const response=await transport(input,{...init,headers});
  observe({kind:'response',status:response.status});
  return response;
  }catch(error){observe({kind:'error',error});throw error;}
 }}});
}
