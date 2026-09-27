// School operator only. Uses server secrets; never called by a web endpoint.
// Reads a single JSON object from stdin, never a PIN or role from URL arguments.
import {createServerClient} from '../lib/server/supabase-client.mjs';
import {connectionConfig} from '../lib/server/config.mjs';
let input='';for await(const chunk of process.stdin)input+=chunk;const p=JSON.parse(input);
const config=connectionConfig();if(config.issues.length)throw Error('Missing/invalid settings: '+config.issues.join(', '));
const db=createServerClient(config.url,config.secret);
async function rpc(name,args){const {data,error}=await db.rpc(name,args);if(error)throw Error(error.message);return data;}
if(p.mode==='initialize-year')await rpc('yg_initialize_year',{p_year:p.year});
else if(p.mode==='first-super')await rpc('yg_bootstrap_super',{p_user:p.userId,p_identity_reviewed:p.identityReviewed===true});
else if(p.mode==='candidate')await rpc('yg_action',{p_actor:p.superId,p_action:'ALLOWLIST_ADD',p:{name:p.name,number:p.number,role:p.role,head:!!p.head,deliver:true}});
else if(p.mode==='first-verifier')await rpc('yg_bootstrap_first_verifier',{p_super:p.superId,p_verification:p.verificationId,p_identity_reviewed:p.identityReviewed===true});
else if(p.mode==='super-role'){
 if(p.confirm!==true)throw Error('Explicit operator confirmation required.');
 await rpc('yg_operator_super_role',{p_actor:p.superId,p_target:p.userId,p_grant:p.grant===true});
}else throw Error('Unsupported operation. See README bootstrap procedure.');
// Approval immediately attempts deletion. A failed deletion remains queued.
const {data:pending,error}=await db.from('verification_uploads').select('id,object_path,retry_count').eq('delete_status','DELETION_PENDING').limit(100);if(error)throw error;
let failed=0;for(const f of pending||[]){const removed=await db.storage.from('student-verifications').remove([f.object_path]);if(removed.error){failed++;await db.from('verification_uploads').update({retry_count:f.retry_count+1}).eq('id',f.id);continue;}
 const mark=await db.from('verification_uploads').update({object_path:null,delete_status:'DELETED',deleted_at:new Date().toISOString()}).eq('id',f.id);if(mark.error)failed++;else await db.from('upload_jobs').delete().eq('object_path',f.object_path);
}
console.log('Operation completed. Pending photo deletion retries:',failed);
