// Pure result validation only: no client, fetch, observers, or error wrapping.
export type HealthStep='health_client'|'health_rpc_call'|'health_rpc_response'|'health_shape';
export function healthReady(value:unknown):boolean{
 if(value===null||typeof value!=='object'||Array.isArray(value)){
  throw Object.assign(new Error('Invalid health result'),{code:'HEALTH_SHAPE'});
 }
 const h=value as Record<string,unknown>;
 if(typeof h.version!=='number'||typeof h.rlsReady!=='boolean'||typeof h.storageReady!=='boolean'||!(h.year===null||Number.isInteger(h.year))){
  throw Object.assign(new Error('Invalid health result'),{code:'HEALTH_SHAPE'});
 }
 return h.version===8&&h.rlsReady===true&&h.storageReady===true&&Number.isInteger(h.year);
}
