import 'server-only';
import sharp from 'sharp';
import {db,rpc} from './db';
import {opaque} from './crypto';
export async function upload(file:File,bucket:'student-verifications'|'item-photos',owner:string|null=null){
 if(!file||file.size===0||file.size>5*1024*1024||!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('5MB 이하 JPG·PNG·WEBP 사진을 선택해주세요.');
 const bytes=await sharp(Buffer.from(await file.arrayBuffer()),{limitInputPixels:20000000}).rotate().resize({width:1600,height:1600,fit:'inside',withoutEnlargement:true}).webp({quality:82}).toBuffer();
 const path=opaque()+'.webp';const client=db();const job=await client.from('upload_jobs').insert({bucket,object_path:path,owner_id:owner});if(job.error)throw Error('업로드를 준비하지 못했어요.');
 const result=await client.storage.from(bucket).upload(path,bytes,{contentType:'image/webp',upsert:false});if(result.error)throw Error('사진을 업로드하지 못했어요.');return path;
}
export async function cleanup(verificationId?:string){
 const client=db();let q=client.from('verification_uploads').select('id,object_path,retry_count').eq('delete_status','DELETION_PENDING');if(verificationId)q=q.eq('verification_id',verificationId);const {data,error}=await q.limit(100);if(error)throw Error('사진 삭제 작업을 확인하지 못했어요.');let pending=0;
 for(const f of data||[]){const removed=await client.storage.from('student-verifications').remove([f.object_path]);if(removed.error){pending++;await client.from('verification_uploads').update({retry_count:f.retry_count+1}).eq('id',f.id);continue;}const mark=await client.from('verification_uploads').update({object_path:null,delete_status:'DELETED',deleted_at:new Date().toISOString()}).eq('id',f.id);if(mark.error)pending++;else await client.from('upload_jobs').delete().eq('object_path',f.object_path);}
 return pending;
}
export async function maintenance(){await rpc('yg_maintenance');const pending=await cleanup();const {data,error}=await db().from('upload_jobs').select('*').eq('linked',false).lt('expires_at',new Date().toISOString()).limit(100);if(error)throw Error('파일 정리 작업 조회 실패');for(const f of data||[]){const result=await db().storage.from(f.bucket).remove([f.object_path]);if(!result.error)await db().from('upload_jobs').delete().eq('id',f.id);}return {pending};}
