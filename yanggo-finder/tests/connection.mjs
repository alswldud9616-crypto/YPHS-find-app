import {PGlite} from '@electric-sql/pglite';import fs from 'node:fs';import assert from 'node:assert/strict';import {connectionConfig} from '../lib/server/config.mjs';import {storageFixture} from './storage-fixture.mjs';
process.on('uncaughtException',e=>{console.error(e.message,e.where||'');process.exit(1)});
const env={NEXT_PUBLIC_SUPABASE_URL:'https://example.supabase.co',NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_test',SUPABASE_SECRET_KEY:'sb_secret_test',PIN_PEPPER:'a'.repeat(64),DATA_ENCRYPTION_KEY:'b'.repeat(64),CRON_SECRET:'c'.repeat(64),APP_ORIGIN:'https://example.org'};
assert.equal(connectionConfig(env).issues.length,0);assert(connectionConfig({...env,SUPABASE_SECRET_KEY:''}).issues.length);assert(connectionConfig({...env,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:'sb_secret_test'}).issues.length);assert(connectionConfig({...env,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:'x.'+Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')+'.x'}).issues.length);assert(connectionConfig({...env,DATA_ENCRYPTION_KEY:'wrong'}).issues.length);assert(connectionConfig({...env,APP_ORIGIN:'http://example.org'}).issues.length);
// New key, legacy fallback, and conflicting settings never silently select a key.
assert.equal(connectionConfig(env).secret,env.SUPABASE_SECRET_KEY);
assert.equal(connectionConfig({...env,SUPABASE_SECRET_KEY:'',SUPABASE_SERVICE_ROLE_KEY:'sb_secret_legacy'}).secret,'sb_secret_legacy');
assert(connectionConfig({...env,SUPABASE_SERVICE_ROLE_KEY:'sb_secret_other'}).issues.length);
assert.equal(connectionConfig({...env,SUPABASE_SERVICE_ROLE_KEY:env.SUPABASE_SECRET_KEY}).issues.length,0);
assert(connectionConfig({...env,SUPABASE_SECRET_KEY:'sb_publishable_wrong'}).issues.length);
assert(connectionConfig({...env,SUPABASE_SECRET_KEY:'not-a-secret-key'}).issues.length);
// Verify the installed SDK sends new keys as apikey, not JWT Bearer tokens.
const {createServerClient}=await import('../lib/server/supabase-client.mjs');
for(const key of [env.SUPABASE_SECRET_KEY,env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY]){
 let called=false;
 const client=createServerClient(env.NEXT_PUBLIC_SUPABASE_URL,key,{fetch:async(_url,init)=>{called=true;const h=new Headers(init.headers);assert.equal(h.get('apikey'),key);assert.equal(h.has('authorization'),false);return new Response('true',{headers:{'content-type':'application/json'}});}});
 const result=await client.rpc('yg_connection_health');assert.equal(result.error,null);assert(called);
 called=false;const removal=await client.storage.from('student-verifications').remove(['test-only.webp']);assert.equal(removal.error,null);assert(called);
}
const db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);');await db.exec(storageFixture);await db.exec(fs.readFileSync('supabase/production-fresh.sql','utf8'));
const q=(sql,p=[])=>db.query(sql,p);let health=(await q('select yg_connection_health() h')).rows[0].h;assert.equal(health.version,8);assert.equal(health.rlsReady,true);assert.equal(health.storageReady,true);assert.equal(health.year,null);
await q('select yg_initialize_year(2026)');await db.exec('set role service_role');health=(await q('select yg_connection_health() h')).rows[0].h;assert.equal(health.year,2026);await db.exec('reset role');
await q("insert into users(display_name) values('비공개 검증 계정')");await q("insert into storage.buckets(id,name,public) values('unrelated','unrelated',false)");await q("insert into storage.objects(bucket_id,name) values('student-verifications','card.webp'),('item-photos','item.webp'),('unrelated','other.webp')");
// Even accidentally reintroduced broad grants/permissive policies cannot open data.
await db.exec('grant all on users to anon,authenticated;create policy test_open on users for all to anon,authenticated using(true) with check(true);grant all on storage.objects to anon,authenticated;create policy test_open_storage on storage.objects for all to anon,authenticated using(true) with check(true);');
for(const role of ['anon','authenticated']){await db.exec('set role '+role);assert.equal((await q('select * from users')).rows.length,0);assert.equal((await q("update users set display_name='forged' returning id")).rows.length,0);assert.equal((await q('delete from users returning id')).rows.length,0);await assert.rejects(()=>q("insert into users(display_name) values('공격 계정')"));const rows=(await q('select bucket_id from storage.objects')).rows;assert.deepEqual(rows.map(r=>r.bucket_id),['unrelated']);await assert.rejects(()=>q("insert into storage.objects(bucket_id,name) values('student-verifications','forged.webp')"));await assert.rejects(()=>q('select yg_connection_health()'));await db.exec('reset role');}
await db.exec('set role service_role');assert.equal((await q('select * from users')).rows.length,1);await db.exec('reset role');
await q("update storage.buckets set public=true where id='student-verifications'");assert.equal((await q('select yg_connection_health() h')).rows[0].h.storageReady,false);
await db.exec('alter table users disable row level security');assert.equal((await q('select yg_connection_health() h')).rows[0].h.rlsReady,false);
await assert.rejects(()=>db.exec(fs.readFileSync('supabase/production-fresh.sql','utf8')));await db.exec('rollback');
console.log('PASS env validation, fresh SQL, all RLS policies incl broad-grant defense, Storage metadata policy, readiness failure detection, repeat-install guard.');await db.close();
