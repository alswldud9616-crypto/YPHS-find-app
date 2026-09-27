import {NextResponse} from 'next/server';
import {cookies} from 'next/headers';
import {db,configured,rpc,ready} from '@/lib/server/db';
import {actor,session,sameOrigin,limit,networkKey,COOKIE} from '@/lib/server/auth';
import {hashPin,verifyPin,digest,privateDigest} from '@/lib/server/crypto';
import {upload} from '@/lib/server/uploads';
export const runtime='nodejs';
export async function POST(req:Request){try{
 if(!configured())return NextResponse.json({error:'서버 연결 설정 후 이용할 수 있어요.'},{status:503});sameOrigin(req);if(!await ready())return NextResponse.json({error:'운영 데이터베이스 설정을 확인해주세요.'},{status:503});if(Number(req.headers.get('content-length')||0)>6*1024*1024)throw Error('파일 크기를 확인해주세요.');
 const form=await req.formData();const action=String(form.get('action'));await limit('auth-net:'+networkKey(req),200);
 if(action==='logout'){const jar=await cookies();const token=jar.get(COOKIE)?.value;if(token)await db().from('app_sessions').delete().eq('token_hash',digest(token));jar.delete(COOKIE);return NextResponse.json({ok:true});}
 const name=String(form.get('name')||'').trim().normalize('NFC'),number=String(form.get('number')||'').trim(),pin=String(form.get('pin')||'');
 if(action==='reverify'){const id=await actor();if(!id)throw Error('로그인이 필요해요.');await limit('reverify:'+id,3);const path=await upload(form.get('photo') as File,'student-verifications',id);const user=await db().from('users').select('display_name').eq('id',id).single();if(user.error)throw Error('계정 확인 오류');await rpc('yg_signup',{p_name:user.data.display_name,p_number:number,p_hash:'',p_path:path,p_actor:id});return NextResponse.json({ok:true});}
 if(!/^\d{5}$/.test(number)||name.length<2||name.length>40||!/^\d{6}$/.test(pin))throw Error('이름·학번·6자리 비밀번호를 확인해주세요.');
 await limit('identity:'+name+':'+number,5);
 if(action==='signup'){
  const path=await upload(form.get('photo') as File,'student-verifications');const id=await rpc('yg_signup',{p_name:name,p_number:number,p_hash:await hashPin(pin),p_path:path});await session(id);return NextResponse.json({ok:true});
 }
 if(action!=='login')throw Error('지원하지 않는 요청이에요.');
 // An old number remains usable for annual re-verification. Multiple matching
 // accounts never choose silently; all PIN matches are checked, ambiguity fails.
 const {data:identities,error}=await db().from('student_verifications').select('user_id,users!inner(display_name)').eq('student_number',number).eq('users.display_name',name).order('school_year',{ascending:false}).limit(20);
 if(error)throw Error('로그인 정보를 확인하지 못했어요.');const ids=[...new Set((identities||[]).map(i=>i.user_id))];
 const {data:credentials,error:ce}=ids.length?await db().from('pin_credentials').select('*').in('user_id',ids):{data:[],error:null};if(ce)throw Error('로그인 정보를 확인하지 못했어요.');let matched:string[]=[];
 for(const c of credentials||[])if(await verifyPin(pin,c.pin_hash))matched.push(c.user_id);
 if(!credentials?.length)await hashPin(pin); // comparable work for unknown accounts
 if(matched.length!==1)throw Error('이름·학번·비밀번호를 확인해주세요.');
 await session(matched[0]);await db().from('login_limits').delete().eq('key',privateDigest('identity:'+name+':'+number));return NextResponse.json({ok:true});
 }catch(e){const msg=e instanceof Error?e.message:'요청을 처리하지 못했어요.';return NextResponse.json({error:msg.includes('duplicate key')?'이미 신청된 학번이에요. 로그인하거나 학생복지부에 문의해주세요.':msg},{status:400});}}
