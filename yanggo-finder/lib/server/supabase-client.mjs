// Server/CLI only. The SDK owns fetch, Request, and headers.
import {createClient} from '@supabase/supabase-js';
export function createServerClient(url,key){
 return createClient(url.trim(),key.trim(),{
  auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}
 });
}
