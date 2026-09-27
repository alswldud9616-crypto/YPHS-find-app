import App from '@/components/app';
import {configured,rpc} from '@/lib/server/db';
import {actor} from '@/lib/server/auth';
import {redirect} from 'next/navigation';
export const dynamic='force-dynamic';
export default async function Page(){if(!configured())redirect('/my');{const id=await actor();if(!id||!await rpc('yg_deliverer',{a:id}))redirect('/my');}return <App/>}
