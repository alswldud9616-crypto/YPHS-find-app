import {randomUUID} from 'node:crypto';
import {NextResponse} from 'next/server';
import {configured,rpc,db,ready} from '@/lib/server/db';
import {actor} from '@/lib/server/auth';
import {decrypt} from '@/lib/server/crypto';
import {healthDiagnostic} from '@/lib/server/health-probe';
import {emptyState} from '@/lib/model';

export const dynamic='force-dynamic';
export const runtime='nodejs';
type Stage='config'|'health'|'state'|'postprocess';
// Fixed vocabulary only: NEVER log the original message, details, hint, stack,
// request URL, cookies, headers, environment, RPC arguments, or returned rows.
const SAFE_CODES=new Set(['42501','42883','42P01','42703','22P02','22023','57014','53300','08006',
 'PGRST000','PGRST001','PGRST002','PGRST003','PGRST106','PGRST202','PGRST203','PGRST301','PGRST302','PGRST303',
 'CONFIG_INVALID','HEALTH_NOT_READY','STATE_SHAPE','ROW_SHAPE']);
function safeError(error:unknown){
 const e=error&&typeof error==='object'?error as {code?:unknown;status?:unknown}:{};
 return {
  code:typeof e.code==='string'&&SAFE_CODES.has(e.code)?e.code:'UNCLASSIFIED',
  upstreamStatus:typeof e.status==='number'&&Number.isInteger(e.status)&&e.status>=100&&e.status<=599?e.status:null
 };
}
function invalid(code:string):never{throw Object.assign(new Error('State response validation failed'),{code});}
function record(value:unknown):value is Record<string,any>{return value!==null&&typeof value==='object'&&!Array.isArray(value);}

export async function GET(req:Request){
 const requestId=randomUUID();
 let stage:Stage='config';
 let step='environment';
 let isConfigured=false;
 const headers={'Cache-Control':'no-store','Content-Type':'application/json; charset=utf-8','X-Yanggo-Diagnostics':'state-v2'};
 function failure(error:unknown,message:string,status=503){
  const diagnostic={version:'state-v2',requestId,stage,step};
  console.error(JSON.stringify({event:'yanggo.state.failed',...diagnostic,...safeError(error),...healthDiagnostic(error)}));
  return NextResponse.json({...emptyState,configured:isConfigured,connected:false,
   error:message,errorCode:'STATE_UNAVAILABLE',diagnostic},{status,headers});
 }
 try{
  isConfigured=configured();
  if(!isConfigured)return failure({code:'CONFIG_INVALID'},'운영 서버 연결을 준비하고 있어요.',200);

  stage='health';step='health_client';
  if(!await ready(next=>{step=next;}))return failure({code:'HEALTH_NOT_READY'},'데이터베이스·저장소·학년도 설정을 확인하고 있어요.');

  stage='state';step='session';
  const id=await actor(); // No yg_session cookie => null, no app_sessions query.
  step='year_parameter';
  const year=new URL(req.url).searchParams.get('year');
  step='state_rpc';
  const data=await rpc('yg_state',{p_actor:id,p_year:year?Number(year):null});

  stage='postprocess';step='state_shape';
  if(!record(data)||!Number.isInteger(data.year))invalid('STATE_SHAPE');
  for(const key of ['claims','assignments']){
   step='pickup_shape';
   const rows=data[key];
   if(rows==null)continue;
   if(!Array.isArray(rows))invalid('ROW_SHAPE');
   for(const row of rows){
    if(!record(row))invalid('ROW_SHAPE');
    if(row.codeEncrypted){
     step='pickup_decrypt';
     if(typeof row.codeEncrypted!=='string')invalid('ROW_SHAPE');
     row.code=decrypt(row.codeEncrypted);
    }
    delete row.codeEncrypted;
   }
  }
  if(id){
   step='notifications';
   const {data:notices,error,status}=await db().from('notifications').select('id,message,read_at')
    .eq('recipient_id',id).order('created_at',{ascending:false}).limit(100);
   if(error)throw {code:error.code,status};
   if(notices!==null&&!Array.isArray(notices))invalid('ROW_SHAPE');
   step='unread_count';
   const unread=await db().from('notifications').select('id',{count:'exact',head:true})
    .eq('recipient_id',id).is('read_at',null);
   if(unread.error)throw {code:unread.error.code,status:unread.status};
   data.unreadCount=unread.count||0;
   step='notifications_map';
   data.notices=(notices||[]).map(n=>({id:n.id,text:n.message,read:!!n.read_at}));
  }
  step='serialize';
  return NextResponse.json({...emptyState,...data,configured:true,connected:true},{headers});
 }catch(error){
  return failure(error,'서버 연결을 확인하지 못했어요. 잠시 후 다시 시도해주세요.');
 }
}
