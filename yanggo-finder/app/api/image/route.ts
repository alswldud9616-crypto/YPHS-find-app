import {requireActor} from '@/lib/server/auth';
import {rpc,db} from '@/lib/server/db';
export const dynamic='force-dynamic';
export async function GET(req:Request){try{const id=await requireActor();const url=new URL(req.url);const file=await rpc('yg_image',{p_actor:id,p_kind:url.searchParams.get('kind'),p_id:url.searchParams.get('id')});if(!file?.path)return new Response(null,{status:404});const {data,error}=await db().storage.from(file.bucket).download(file.path);if(error||!data)return new Response(null,{status:404});return new Response(await data.arrayBuffer(),{headers:{'Content-Type':'image/webp','Cache-Control':'private, no-store, max-age=0','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'"}});}catch{return new Response(null,{status:403});}}
