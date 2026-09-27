import type {AnchorHTMLAttributes} from 'react';
import {useRouter} from './navigation';
export default function Link({href,children,onClick,...props}:AnchorHTMLAttributes<HTMLAnchorElement>&{href:string}){const router=useRouter();return <a {...props} href={href} onClick={e=>{onClick?.(e);if(e.defaultPrevented||e.button||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey)return;e.preventDefault();router.push(href)}}>{children}</a>}
