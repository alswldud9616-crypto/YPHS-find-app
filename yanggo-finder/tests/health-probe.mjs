import {build} from 'esbuild';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import fs from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
const out='.health-probe-test-'+randomUUID()+'.cjs';
try{
 await build({entryPoints:['lib/server/health-probe.ts'],outfile:out,bundle:true,platform:'node',format:'cjs'});
 const {healthReady}=createRequire(import.meta.url)(process.cwd()+'/'+out);
 for(const value of [null,[],undefined,{year:2026}])assert.throws(()=>healthReady(value),{code:'HEALTH_SHAPE'});
 assert.equal(healthReady({version:8,year:2026,rlsReady:true,storageReady:true}),true);
 assert.equal(healthReady({version:8,year:null,rlsReady:true,storageReady:true}),false);
 assert.equal(healthReady({version:8,year:2026,rlsReady:false,storageReady:true}),false);
 console.log('PASS: pure health shape validation; no transport wrapper.');
}finally{await fs.rm(out,{force:true});}
