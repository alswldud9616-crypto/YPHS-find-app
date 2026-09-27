import {storageFixture} from './storage-fixture.mjs';
// Test-only local PostgREST/Storage adapter. Never imported by production code.
import {PGlite} from '@electric-sql/pglite';import {createServer} from 'node:http';import fs from 'node:fs';
export async function testBackend(){const database=new PGlite();const objects=new Map();await database.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);');
 await database.exec(storageFixture);
for(const name of fs.readdirSync('supabase/migrations').filter(n=>n.endsWith('.sql')).sort())await database.exec(fs.readFileSync('supabase/migrations/'+name,'utf8'));
 const ident=s=>{if(!/^[a-z_][a-z0-9_]*$/.test(s))throw Error('Bad test identifier');return '"'+s+'"'};
 const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://test');let raw=Buffer.alloc(0);for await(const c of req)raw=Buffer.concat([raw,c]);res.setHeader('content-type','application/json');let body=raw.length&&req.headers['content-type']?.includes('application/json')?JSON.parse(raw):{};const parts=url.pathname.split('/').filter(Boolean);let out;
 if(parts[0]==='storage'){
  const bucket=parts[3],path=parts.slice(4).join('/');const key=bucket+'/'+path;
  if(req.method==='POST'){objects.set(key,raw);out={Key:key};}
  else if(req.method==='DELETE'){for(const p of body.prefixes)objects.delete(bucket+'/'+p);out=body.prefixes.map(name=>({name}));}
  else if(objects.has(key)){res.setHeader('content-type','image/webp');res.end(objects.get(key));return;}
  else{res.statusCode=404;out={error:'not found'};}
 }else if(parts[2]==='rpc'){
  const args=Object.entries(body);const sql=`select ${ident(parts[3])}(${args.map(([k],i)=>ident(k)+' => $'+(i+1)).join(',')}) value`;
  const r=await database.query(sql,args.map(([,v])=>v&&typeof v==='object'?JSON.stringify(v):v));out=r.rows[0].value;
 }else if(parts[0]==='rest'){
  const table=parts[2],parameters=[],conditions=[];let from=ident(table),selection=url.searchParams.get('select')||'*';
  const joined=table==='student_verifications'&&selection.includes('users!inner');if(joined){from='student_verifications join users on users.id=student_verifications.user_id';selection='student_verifications.user_id';}
  for(const [k,val] of url.searchParams){if(['select','order','limit'].includes(k))continue;const [op,...tail]=val.split('.');let value=tail.join('.');const column=k==='users.display_name'?'users.display_name':ident(k);
   if(op==='is'&&value==='null'){conditions.push(column+' is null');continue;}
   if(op==='in'){value=value.slice(1,-1).split(',');parameters.push(value);conditions.push(column+' = any($'+parameters.length+')');continue;}
   const operator={eq:'=',gt:'>',lt:'<',gte:'>=',lte:'<='}[op];if(!operator)throw Error('Unsupported filter '+op);parameters.push(value);conditions.push(column+operator+'$'+parameters.length);
  }
  const where=conditions.length?' where '+conditions.join(' and '):'';
  if(req.method==='POST'){const keys=Object.keys(body);out=(await database.query(`insert into ${ident(table)}(${keys.map(ident)}) values(${keys.map((_,i)=>'$'+(i+1))}) returning *`,keys.map(k=>body[k]))).rows;}
  else if(req.method==='PATCH'){const keys=Object.keys(body);const offset=parameters.length;out=(await database.query(`update ${ident(table)} set ${keys.map((k,i)=>ident(k)+'=$'+(offset+i+1)).join(',')}${where} returning *`,[...parameters,...keys.map(k=>body[k])])).rows;}
  else if(req.method==='DELETE')out=(await database.query(`delete from ${ident(table)}${where} returning *`,parameters)).rows;
  else if(req.method==='HEAD'){const n=(await database.query(`select count(*) n from ${from}${where}`,parameters)).rows[0].n;res.setHeader('content-range','0-0/'+n);res.end();return;}
  else {let order='';if(url.searchParams.has('order'))order=' order by '+url.searchParams.get('order').split(',').map(s=>{const [col,dir]=s.split('.');return ident(col)+(dir==='desc'?' desc':' asc')}).join(',');const columns=selection==='*'?'*':joined?selection:selection.split(',').map(ident).join(',');const lim=Number(url.searchParams.get('limit')||10000);out=(await database.query(`select ${columns} from ${from}${where}${order} limit ${lim}`,parameters)).rows;}
  if(req.headers.accept?.includes('vnd.pgrst.object'))out=out[0]||null;
 }else throw Error('Unsupported test route');res.end(JSON.stringify(out));
 }catch(e){res.statusCode=400;res.end(JSON.stringify({message:e.message,details:e.where||''}));}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));return {database,objects,url:'http://127.0.0.1:'+server.address().port,close:async()=>{await new Promise(r=>server.close(r));await database.close()}};
}
