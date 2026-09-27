// Isolated SDK/route tests. No Supabase credentials, network, or DB mutations.
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
const require=createRequire(import.meta.url);
const out='.state-diagnostic-test-'+randomUUID()+'.cjs';
const marker='PRIVATE_SENTINEL_DO_NOT_LOG';
Object.assign(process.env,{NEXT_PUBLIC_SUPABASE_URL:'https://example.supabase.co',NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_test',SUPABASE_SECRET_KEY:'sb_secret_test',APP_ORIGIN:'https://example.org',PIN_PEPPER:'a'.repeat(64),DATA_ENCRYPTION_KEY:'b'.repeat(64),CRON_SECRET:'c'.repeat(64)});
delete process.env.SUPABASE_SERVICE_ROLE_KEY;delete process.env.SUPABASE_URL;
const logs=[];const savedError=console.error;const savedFetch=globalThis.fetch;
let scenario;let calls;
const ok=(data)=>Response.json(data);
globalThis.fetch=async(input,init)=>{
 const url=new URL(input);const headers=new Headers(init.headers);
 assert.equal(headers.get('apikey'),'sb_secret_test');
 assert.equal(headers.has('authorization'),false);
 calls.push(url.pathname);
 if(url.pathname.endsWith('/rpc/yg_connection_health')){
  assert.equal(headers.get('content-profile'),'public');
  if(scenario==='health')return Response.json({code:'42501',message:marker,details:marker,hint:marker},{status:403});
  if(scenario==='unknown_code')return Response.json({code:marker,message:marker},{status:401});
  return ok({version:8,year:2026,rlsReady:true,storageReady:scenario!=='health_false'});
 }
 if(url.pathname.endsWith('/rpc/yg_state')){
  assert.equal(headers.get('content-profile'),'public');
  const body=JSON.parse(init.body);assert.equal(body.p_actor,globalThis.__stateActor);assert.equal(body.p_year,null);
  if(scenario==='state')return Response.json({code:'PGRST202',message:marker},{status:404});
  if(scenario==='shape')return ok(null);
  if(scenario==='row')return ok({year:2026,claims:{private:marker}});
  if(scenario==='decrypt')return ok({year:2026,claims:[{codeEncrypted:marker}]});
  return ok({year:2026,role:'STUDENT',user:null,verified:false});
 }
 if(url.pathname.endsWith('/notifications'))return Response.json({code:'42501',message:marker},{status:403});
 throw Error('Unexpected transport route');
};
try{
 await build({entryPoints:['app/api/state/route.ts'],outfile:out,bundle:true,platform:'node',format:'cjs',packages:'external',plugins:[{name:'isolated-auth',setup(b){
  b.onResolve({filter:/^server-only$/},()=>({path:'empty',namespace:'test'}));
  b.onResolve({filter:/^@\/lib\/server\/auth$/},()=>({path:'actor',namespace:'test'}));
  b.onLoad({filter:/.*/,namespace:'test'},a=>({contents:a.path==='empty'?'':`export async function actor(){if(globalThis.__actorFailure)throw new Error('${marker}');return globalThis.__stateActor;}`}));
 }}]});
 const {GET}=require(process.cwd()+'/'+out);
 console.error=(line)=>logs.push(line);
 async function run(name,expectedStage,expectedStep,id=null){
  scenario=name;calls=[];logs.length=0;globalThis.__stateActor=id;globalThis.__actorFailure=name==='session';
  const response=await GET(new Request('https://example.org/api/state'));
  assert.match(response.headers.get('content-type'),/charset=utf-8/i);
  const raw=await response.text();assert(!raw.includes('\uFFFD'));assert(!raw.includes(marker));
  const data=JSON.parse(raw);
  if(!expectedStage){assert.equal(data.connected,true);assert.equal(data.year,2026);assert.equal(logs.length,0);assert.equal(calls.length,2);return;}
  assert.equal(data.connected,false);assert.equal(data.diagnostic.stage,expectedStage);assert.equal(data.diagnostic.step,expectedStep);
  assert.equal(logs.length,1);assert(!logs[0].includes(marker));assert(!logs[0].includes('sb_secret_'));assert(!logs[0].includes(id||marker));
  const log=JSON.parse(logs[0]);assert.equal(log.requestId,data.diagnostic.requestId);
  assert.match(data.error,/운영 서버|서버 연결|데이터베이스/);
  if(name==='health')assert.equal(log.upstreamStatus,403);
  if(name==='unknown_code')assert.equal(log.code,'UNCLASSIFIED');
  if(name==='config')assert.equal(calls.length,0);
  return data;
 }
 await run('success');
 await run('health','health','health_rpc');
 await run('unknown_code','health','health_rpc');
 await run('health_false','health','health_rpc');
 await run('state','state','state_rpc');
 await run('session','state','session');
 await run('shape','postprocess','state_shape');
 await run('row','postprocess','pickup_shape');
 await run('decrypt','postprocess','pickup_decrypt');
 await run('notification','postprocess','notifications','test-user-uuid-private');
 const secret=process.env.SUPABASE_SECRET_KEY;delete process.env.SUPABASE_SECRET_KEY;
 await run('config','config','environment');process.env.SUPABASE_SECRET_KEY=secret;
 console.error=savedError;
 console.log('PASS: route stages, SDK public schema/apikey, anonymous skip, safe logs, UTF-8 JSON. No live Supabase connection.');
}finally{console.error=savedError;globalThis.fetch=savedFetch;await fs.rm(out,{force:true});}
