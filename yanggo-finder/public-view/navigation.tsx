import {useSyncExternalStore} from 'react';
const subscribe=(fn:()=>void)=>{window.addEventListener('popstate',fn);return()=>window.removeEventListener('popstate',fn)};
export function usePathname(){return useSyncExternalStore(subscribe,()=>window.location.pathname,()=>'/')}
export function useRouter(){return {push:(href:string)=>{history.pushState(null,'',href);window.dispatchEvent(new PopStateEvent('popstate'));window.scrollTo(0,0)},replace:(href:string)=>{history.replaceState(null,'',href);window.dispatchEvent(new PopStateEvent('popstate'))}}}
