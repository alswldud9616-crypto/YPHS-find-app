// Diagnostic metadata only. Never retain/log raw errors, inputs, or payloads.
export type HealthStep='health_client'|'health_rpc_call'|'health_rpc_response'|'health_shape';
export type TransportEvent={kind:'start'}|{kind:'response';status:number}|{kind:'error';error:unknown};
export type TransportObserver=(event:TransportEvent)=>void;
const NAMES=new Set(['Error','TypeError','RangeError','SyntaxError','AbortError','TimeoutError','DOMException']);
const NETWORK=new Set(['ENOTFOUND','EAI_AGAIN','ECONNREFUSED','ECONNRESET','ETIMEDOUT','ENETUNREACH','EHOSTUNREACH','EPIPE','UND_ERR_CONNECT_TIMEOUT','UND_ERR_HEADERS_TIMEOUT','UND_ERR_BODY_TIMEOUT','UND_ERR_SOCKET','CERT_HAS_EXPIRED','DEPTH_ZERO_SELF_SIGNED_CERT','UNABLE_TO_VERIFY_LEAF_SIGNATURE','ERR_TLS_CERT_ALTNAME_INVALID']);
function object(v:unknown):v is Record<string,any>{return v!==null&&typeof v==='object'&&!Array.isArray(v);}
export function classifyException(error:unknown){
 const e=object(error)?error:{};
 const name=typeof e.name==='string'&&NAMES.has(e.name)?e.name:'Unknown';
 let networkCode:string|null=null;let cause=e.cause;
 for(let i=0;i<3&&object(cause);i++,cause=cause.cause){if(typeof cause.code==='string'&&NETWORK.has(cause.code)){networkCode=cause.code;break;}}
 // Only derive a boolean from the message; never return its text.
 return {errorName:name,isTypeError:error instanceof TypeError||name==='TypeError',
  fetchFailed:typeof e.message==='string'&&/fetch failed/i.test(e.message),
  isAbortError:name==='AbortError',networkCode};
}
class HealthProbeError extends Error{
 code:unknown;status:unknown;
 constructor(readonly diagnostic:Record<string,unknown>,code?:unknown,status?:unknown){
  super('Health probe failed');this.name='HealthProbeError';this.code=code;this.status=status;
 }
}
export function healthDiagnostic(error:unknown){return error instanceof HealthProbeError?error.diagnostic:{};}

export async function probeHealth(factory:(observe:TransportObserver)=>any,onStep:(step:HealthStep)=>void=()=>{}){
 let fetchStarted=false;let fetchResponseReceived=false;let fetchResponseStatus:number|null=null;
 let transportFailure:ReturnType<typeof classifyException>|null=null;
 const observe:TransportObserver=event=>{
  if(event.kind==='start')fetchStarted=true;
  else if(event.kind==='response'){fetchResponseReceived=true;fetchResponseStatus=event.status;}
  else transportFailure=classifyException(event.error);
 };
 function fail(kind:string,error?:unknown,code?:unknown,status?:unknown):never{
  const sdkStatus=typeof status==='number'&&Number.isInteger(status)&&status>=0&&status<=599?status:null;
  throw new HealthProbeError({failureKind:kind,...classifyException(error),sdkStatus,
   fetchStarted,fetchResponseReceived,fetchResponseStatus,transportFailure},code,sdkStatus);
 }
 onStep('health_client');let client;
 try{client=factory(observe);}catch(e){fail('client_throw',e);}
 onStep('health_rpc_call');let pending;
 try{pending=client.rpc('yg_connection_health');}catch(e){fail('rpc_call_throw',e);}
 let result;
 try{result=await pending;}catch(e){fail('rpc_await_throw',e);}
 onStep('health_rpc_response');
 if(!object(result))fail('rpc_response_shape');
 if(result.error)fail('sdk_error',result.error,result.error.code,result.status);
 onStep('health_shape');
 const h=result.data;
 if(!object(h)||typeof h.version!=='number'||typeof h.rlsReady!=='boolean'||typeof h.storageReady!=='boolean'||!(h.year===null||Number.isInteger(h.year)))fail('health_shape',undefined,undefined,result.status);
 return h.version===8&&h.rlsReady===true&&h.storageReady===true&&Number.isInteger(h.year);
}
