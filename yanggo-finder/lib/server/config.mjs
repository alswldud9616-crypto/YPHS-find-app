// Imported only by server modules and operator scripts. Never by a client component.
export function connectionConfig(env=process.env){
 const url=(env.NEXT_PUBLIC_SUPABASE_URL||env.SUPABASE_URL||'').trim().replace(/\/$/,'');
 const publishable=(env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||'').trim();
 const primary=(env.SUPABASE_SECRET_KEY||'').trim();
 const legacy=(env.SUPABASE_SERVICE_ROLE_KEY||'').trim();
 const secret=primary||legacy;const issues=[];
 if(primary&&legacy&&primary!==legacy)issues.push('SUPABASE_SECRET_KEY / SUPABASE_SERVICE_ROLE_KEY (mismatch; keep only the new variable)');
 if(primary&&!primary.startsWith('sb_secret_'))issues.push('SUPABASE_SECRET_KEY (expected sb_secret_ key)');
 for(const [name,value] of Object.entries({NEXT_PUBLIC_SUPABASE_URL:url,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:publishable,SUPABASE_SECRET_KEY:secret,APP_ORIGIN:env.APP_ORIGIN,PIN_PEPPER:env.PIN_PEPPER,DATA_ENCRYPTION_KEY:env.DATA_ENCRYPTION_KEY,CRON_SECRET:env.CRON_SECRET}))if(!value)issues.push(name);
 for(const [name,value]of [['NEXT_PUBLIC_SUPABASE_URL',url],['APP_ORIGIN',env.APP_ORIGIN]]){if(!value)continue;try{const u=new URL(value);if(!['http:','https:'].includes(u.protocol)||u.username||u.password||u.search||u.hash||u.pathname!=='/'||u.protocol!=='https:'&&!['localhost','127.0.0.1','[::1]'].includes(u.hostname))issues.push(name);}catch{issues.push(name)}}
 if(env.NEXT_PUBLIC_SUPABASE_URL&&env.SUPABASE_URL&&env.SUPABASE_URL.replace(/\/$/,'')!==url)issues.push('SUPABASE_URL (legacy mismatch)');
 if(env.PIN_PEPPER&&env.PIN_PEPPER.length<32)issues.push('PIN_PEPPER');
 if(env.DATA_ENCRYPTION_KEY&&!/^[a-fA-F0-9]{64}$/.test(env.DATA_ENCRYPTION_KEY))issues.push('DATA_ENCRYPTION_KEY');
 if(env.CRON_SECRET&&env.CRON_SECRET.length<32)issues.push('CRON_SECRET');
 let publicRole='';try{publicRole=JSON.parse(Buffer.from(publishable.split('.')[1]||'','base64url').toString()).role||'';}catch{}
 if(publishable.startsWith('sb_secret_')||publicRole==='service_role'||publishable&&publishable===secret)issues.push('NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (must not be a server key)');
 if(secret.startsWith('sb_publishable_'))issues.push('SUPABASE_SECRET_KEY (must be a server key)');
 return {url,publishable,secret,issues:[...new Set(issues)]};
}
