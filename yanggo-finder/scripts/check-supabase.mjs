// Read-only diagnostics. Does not create users, upload photos, or mutate the DB.
import {createServerClient} from '../lib/server/supabase-client.mjs';import {connectionConfig} from '../lib/server/config.mjs';
const c=connectionConfig();if(c.issues.length){console.error('Missing or invalid settings:',c.issues.join(', '));process.exit(1);}
const server=createServerClient(c.url,c.secret),publicClient=createServerClient(c.url,c.publishable);
const {data:h,error}=await server.rpc('yg_connection_health').abortSignal(AbortSignal.timeout(15000));if(error){console.error('FAIL server connection or migrations (code '+(error.code||'network')+'). Verify keys and apply migration 008.');process.exit(1);}
for(const [name,ok]of [['schema version 8',h.version===8],['table RLS policies',h.rlsReady],['private buckets and Storage policies',h.storageReady],['current school year',Number.isInteger(h.year)]]){console.log((ok?'PASS ':'FAIL ')+name);if(!ok)process.exitCode=1;}
// Seeded categories exist on every installation. Permission denied is expected.
const probe=await publicClient.from('categories').select('id').limit(1).abortSignal(AbortSignal.timeout(15000));
if(probe.error?.code==='42501')console.log('PASS publishable key valid; direct database access denied');else{console.error('FAIL publishable key or database access boundary (code '+(probe.error?.code||'unexpected access')+').');process.exitCode=1;}
console.log('This is a connection/configuration check only. Complete docs/ACCEPTANCE_TEST.md before opening the service.');
