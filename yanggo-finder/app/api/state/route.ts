import {NextResponse} from 'next/server';
import {configured,rpc,db,ready} from '@/lib/server/db';
import {actor} from '@/lib/server/auth';
import {decrypt} from '@/lib/server/crypto';
import {emptyState} from '@/lib/model';
export const dynamic='force-dynamic';
export async function GET(req:Request){if(!configured())return NextResponse.json({...emptyState,error:'운영 서버 연결을 준비하고 있어요.'},{headers:{'Cache-Control':'no-store'}});try{
 if(!await ready())return NextResponse.json({...emptyState,configured:true,error:'데이터베이스·저장소·학년도 설정을 확인하고 있어요.'},{status:503,headers:{'Cache-Control':'no-store'}});
 const id=await actor();const year=new URL(req.url).searchParams.get('year');
 const data=await rpc('yg_state',{p_actor:id,p_year:year?Number(year):null});
 for(const key of ['claims','assignments'])for(const row of data[key]||[]){if(row.codeEncrypted)row.code=decrypt(row.codeEncrypted);delete row.codeEncrypted;}
 if(id){const {data:notices,error}=await db().from('notifications').select('id,message,read_at').eq('recipient_id',id).order('created_at',{ascending:false}).limit(100);if(error)throw error;const unread=await db().from('notifications').select('id',{count:'exact',head:true}).eq('recipient_id',id).is('read_at',null);if(unread.error)throw unread.error;data.unreadCount=unread.count||0;data.notices=(notices||[]).map(n=>({id:n.id,text:n.message,read:!!n.read_at}));}
 return NextResponse.json({...emptyState,...data,configured:true,connected:true},{headers:{'Cache-Control':'no-store'}});
 }catch{return NextResponse.json({...emptyState,configured:true,error:'서버 연결을 확인하지 못했어요. 잠시 후 다시 시도해주세요.'},{status:503,headers:{'Cache-Control':'no-store'}});}}
