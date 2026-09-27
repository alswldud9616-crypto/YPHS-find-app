import {maintenance} from '@/lib/server/uploads';
import {timingSafeEqual} from 'node:crypto';
export const runtime='nodejs';
export async function GET(req:Request){const expected=process.env.CRON_SECRET;const received=req.headers.get('authorization');if(!expected||!received||Buffer.byteLength(received)!==Buffer.byteLength('Bearer '+expected)||!timingSafeEqual(Buffer.from(received),Buffer.from('Bearer '+expected)))return Response.json({error:'Unauthorized'},{status:401});try{return Response.json({ok:true,...await maintenance()});}catch{return Response.json({error:'Maintenance failed'},{status:500});}}
