import {build} from 'esbuild';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import fs from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
const out='.health-probe-test-'+randomUUID()+'.cjs';
const marker='PRIVATE_SENTINEL_DO_NOT_LOG';
try{
 await build({entryPoints:['lib/server/health-probe.ts'],outfile:out,bundle:true,platform:'node',format:'cjs'});
 const {probeHealth,healthDiagnostic,classifyException}=createRequire(import.meta.url)(process.cwd()+'/'+out);
 async function failure(factory,kind,expectedStep){
  let step;let error;
  try{await probeHealth(factory,s=>{step=s;});}catch(e){error=e;}
  assert(error);assert.equal(step,expectedStep);
  const safe=healthDiagnostic(error);assert.equal(safe.failureKind,kind);assert(!JSON.stringify(safe).includes(marker));return safe;
 }
 let d=await failure(()=>{throw new TypeError(marker,{cause:{code:'ENOTFOUND',hostname:marker}});},'client_throw','health_client');
 assert(d.isTypeError);assert.equal(d.networkCode,'ENOTFOUND');assert.equal(d.fetchStarted,false);
 await failure(()=>({rpc(){throw new RangeError(marker);}}),'rpc_call_throw','health_rpc_call');
 d=await failure(()=>({rpc(){return Promise.reject(new DOMException(marker,'AbortError'));}}),'rpc_await_throw','health_rpc_call');assert(d.isAbortError);
 await failure(()=>({rpc(){return Promise.resolve(null);}}),'rpc_response_shape','health_rpc_response');
 await failure(()=>({rpc(){return Promise.resolve({data:null,error:null,status:200});}}),'health_shape','health_shape');
 const e=new Error(marker);e.name=marker;e.cause={code:marker};assert.equal(classifyException(e).errorName,'Unknown');assert.equal(classifyException(e).networkCode,null);
 assert.equal(await probeHealth(()=>({rpc:()=>({data:{version:8,year:null,rlsReady:true,storageReady:true},error:null,status:200})})),false);
 assert.equal(await probeHealth(()=>({rpc:()=>({data:{version:8,year:2026,rlsReady:true,storageReady:true},error:null,status:200})})),true);
 console.log('PASS: client/call/await/SDK-envelope/health-shape boundaries; names/cause allowlists; no raw errors.');
}finally{await fs.rm(out,{force:true});}
