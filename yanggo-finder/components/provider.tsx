'use client';
import {createContext,useContext,useState,useEffect,useCallback,useRef} from 'react';
import {emptyState,type State} from '@/lib/model';
type ContextType={state:State;busy:boolean;loading:boolean;message:string;dismiss:()=>void;refresh:(year?:number)=>Promise<void>;act:(input:Record<string,unknown>|FormData,auth?:boolean)=>Promise<boolean>};
const Context=createContext<ContextType|null>(null);
export function AppProvider({children,publicReadiness=false}:{children:React.ReactNode;publicReadiness?:boolean}){
 const [state,setState]=useState<State>(emptyState),[busy,setBusy]=useState(false),[loading,setLoading]=useState(true),[message,setMessage]=useState('');
 const selectedYear=useRef<number|undefined>(undefined);
 const refresh=useCallback(async(year?:number)=>{try{if(publicReadiness){setState({...emptyState,error:'운영 준비 중이에요. 지금은 화면만 확인할 수 있어요.'});return;}if(year!==undefined)selectedYear.current=year;const queryYear=selectedYear.current;const res=await fetch('/api/state'+(queryYear?'?year='+queryYear:''),{cache:'no-store'});const data=await res.json();setState({...emptyState,...data});}catch{setState({...emptyState,error:'연결을 확인하지 못했어요.'});}finally{setLoading(false)}},[publicReadiness]);
 useEffect(()=>{void refresh();const update=()=>void refresh();window.addEventListener('focus',update);const interval=setInterval(()=>{if(document.visibilityState==='visible')void refresh()},60000);return()=>{window.removeEventListener('focus',update);clearInterval(interval)}},[refresh]);
 async function act(input:Record<string,unknown>|FormData,auth=false){if(busy)return false;setBusy(true);setMessage('');try{const form=input instanceof FormData;const res=await fetch(auth?'/api/auth':'/api/action',{method:'POST',headers:form?undefined:{'Content-Type':'application/json'},body:form?input:JSON.stringify(input)});const result=await res.json();if(!res.ok)throw Error(result.error||'처리하지 못했어요.');selectedYear.current=undefined;await refresh();if(result.warning)setMessage(result.warning);return true;}catch(e){setMessage(e instanceof Error?e.message:'다시 시도해주세요.');return false;}finally{setBusy(false)}}
 return <Context.Provider value={{state,busy,loading,message,dismiss:()=>setMessage(''),refresh,act}}>{children}</Context.Provider>
}
export function useApp(){const value=useContext(Context);if(!value)throw Error('AppProvider required');return value}
