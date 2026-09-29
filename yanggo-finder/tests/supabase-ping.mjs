import assert from 'node:assert/strict';
import {build} from 'esbuild';
import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
const path='.supabase-ping-test-'+randomUUID()+'.cjs';
const marker='PRIVATE_SENTINEL_DO_NOT_OUTPUT';
const originalFetch=globalThis.fetch;
const originalUrl=process.env.NEXT_PUBLIC_SUPABASE_URL;
const originalKey=process.env.SUPABASE_SECRET_KEY;
let scenario='success',calls=0;
try{
 const source=await fs.readFile('app/api/supabase-ping/route.ts','utf8');
 assert(!/from ['"]@\/|from ['"]\.\.?\//.test(source));
 assert(!source.includes('console.'));assert(!source.includes('global:'));
 await build({entryPoints:['app/api/supabase-ping/route.ts'],outfile:path,bundle:true,platform:'node',format:'cjs',packages:'external'});
 const {GET}=createRequire(import.meta.url)(process.cwd()+'/'+path);
 process.env.NEXT_PUBLIC_SUPABASE_URL=' https://example.supabase.co\n';
 process.env.SUPABASE_SECRET_KEY=' sb_secret_test\n';
 globalThis.fetch=async(input,init)=>{
  calls++;assert.equal(new URL(input).pathname,'/rest/v1/rpc/yg_connection_health');
  const headers=new Headers(init.headers);assert.equal(headers.get('apikey'),'sb_secret_test');
  assert.equal(headers.get('content-profile'),'public');
  if(scenario==='network')throw new TypeError('fetch failed '+marker);
  if(scenario==='unknown')return Response.json({code:marker,message:marker,details:marker},{status:403});
  if(scenario==='denied')return Response.json({code:'42501',message:marker},{status:403});
  if(scenario==='empty')return Response.json(null);
  return Response.json({version:8,year:2026,rlsReady:true,storageReady:true,private:marker});
 };
 async function run(mode){scenario=mode;calls=0;const r=await GET();const raw=await r.text();assert(!raw.includes(marker));assert(!raw.includes('supabase.co'));assert(!raw.includes('sb_secret'));return {response:r,data:JSON.parse(raw)};}
 let r=await run('success');assert.deepEqual(r.data,{ok:true,status:200,hasData:true});assert.equal(calls,1);
 r=await run('denied');assert.equal(r.data.errorCode,'42501');assert.equal(r.data.status,403);
 r=await run('unknown');assert.equal(r.data.errorCode,'SDK_ERROR');
 r=await run('network');assert.equal(r.data.status,0);assert.equal(r.data.phase,'rpc_result');
 r=await run('empty');assert.equal(r.data.errorCode,'EMPTY_DATA');
 delete process.env.SUPABASE_SECRET_KEY;r=await run('missing');assert.equal(r.data.errorCode,'ENV_MISSING');assert.equal(calls,0);
 process.env.SUPABASE_SECRET_KEY='sb_secret_test';process.env.NEXT_PUBLIC_SUPABASE_URL='invalid';r=await run('invalid');assert.equal(r.data.phase,'client');assert.equal(calls,0);
 console.log('PASS: independent direct-SDK ping, await/trim, success, SDK status 0/403, client throw, missing env, no sensitive response.');
}finally{
 globalThis.fetch=originalFetch;
 if(originalUrl===undefined)delete process.env.NEXT_PUBLIC_SUPABASE_URL;else process.env.NEXT_PUBLIC_SUPABASE_URL=originalUrl;
 if(originalKey===undefined)delete process.env.SUPABASE_SECRET_KEY;else process.env.SUPABASE_SECRET_KEY=originalKey;
 await fs.rm(path,{force:true});
}
