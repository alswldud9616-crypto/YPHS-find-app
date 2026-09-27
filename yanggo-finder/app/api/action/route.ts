import {NextResponse} from 'next/server';
import {rpc,configured,ready} from '@/lib/server/db';
import {requireActor,sameOrigin,limit} from '@/lib/server/auth';
import {pickupCode,encrypt,digest} from '@/lib/server/crypto';
import {upload,cleanup} from '@/lib/server/uploads';
export const runtime='nodejs';
export async function POST(req:Request){try{
 if(!configured())return NextResponse.json({error:'운영 서버 연결 후 이용할 수 있어요.'},{status:503});sameOrigin(req);if(!await ready())return NextResponse.json({error:'운영 데이터베이스 설정을 확인해주세요.'},{status:503});if(Number(req.headers.get('content-length')||0)>6*1024*1024)throw Error('파일 크기를 확인해주세요.');const id=await requireActor();await limit('actions:'+id,120);
 let p:Record<string,unknown>;if(req.headers.get('content-type')?.includes('multipart/form-data')){const form=await req.formData();p=Object.fromEntries([...form.entries()].filter(([k])=>k!=='photo'));if(!['SUBMIT','DIRECT_REGISTER'].includes(String(p.type)))throw Error('지원하지 않는 업로드예요.');const verified=await rpc('yg_verified',{a:id});if(!verified)throw Error('재학생 인증이 필요해요.');if(p.type==='DIRECT_REGISTER'&&!await rpc('yg_manager',{a:id}))throw Error('분실물 직접 등록 권한이 없어요.');p.path=await upload(form.get('photo') as File,'item-photos',id);}
 else {if(Number(req.headers.get('content-length')||0)>16000)throw Error('입력 내용이 너무 길어요.');p=await req.json();}
 // Never accept client-generated verification hashes/ciphertexts or actor IDs.
 delete p.codeHash;delete p.codeEncrypted;delete p.actor;
 if(p.type==='DECIDE'&&p.decision==='APPROVED'){const code=pickupCode();p.codeHash=digest(code);p.codeEncrypted=encrypt(code);}
 if(p.type==='COMPLETE'){await limit('pickup-code:'+id+':'+String(p.id),5);p.codeHash=digest(String(p.code||'').trim().toUpperCase());delete p.code;}
 const result=await rpc('yg_action',{p_actor:id,p_action:p.type,p});let warning='';
 if(p.type==='VERIFY')try{if(await cleanup(result.verificationId))warning='인증 처리는 완료됐지만 사진 삭제를 재시도 중이에요.';}catch{warning='인증 처리는 완료됐지만 사진 삭제 상태를 다시 확인해야 해요.';}
 return NextResponse.json({ok:true,warning});
 }catch(e){const msg=e instanceof Error?e.message:'처리하지 못했어요.';return NextResponse.json({error:msg.includes('duplicate key')?'중복된 요청이나 예약이에요. 새로고침 후 확인해주세요.':msg},{status:400});}}
