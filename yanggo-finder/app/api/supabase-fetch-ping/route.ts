// Temporary network diagnostic. Keep this route independent of the Supabase SDK.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const responseHeaders = {'Cache-Control': 'no-store'};
const allowedNetworkCodes = new Set([
  'ENOTFOUND', 'EAI_AGAIN', 'ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT',
  'EHOSTUNREACH', 'ENETUNREACH', 'EPIPE', 'UND_ERR_CONNECT_TIMEOUT',
  'UND_ERR_HEADERS_TIMEOUT', 'UND_ERR_SOCKET', 'CERT_HAS_EXPIRED',
  'UNABLE_TO_VERIFY_LEAF_SIGNATURE',
]);

function safeErrorName(error: unknown) {
  if (error instanceof TypeError) return 'TypeError';
  if (error instanceof Error && error.name === 'AbortError') return 'AbortError';
  if (error instanceof Error && error.name === 'TimeoutError') return 'TimeoutError';
  return 'OtherError';
}

function safeNetworkCode(error: unknown) {
  if (!(error instanceof Error) || !('cause' in error)) return null;
  const cause: unknown = error.cause;
  if (!cause || typeof cause !== 'object' || !('code' in cause)) return null;
  const code: unknown = cause.code;
  return typeof code === 'string' && allowedNetworkCodes.has(code) ? code : null;
}

export async function GET() {
  let fetchStarted = false;
  let responseReceived = false;
  try {
    const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').trim();
    const key = (process.env.SUPABASE_SECRET_KEY ?? '').trim();
    if (!url || !key) {
      return Response.json({ok: false, phase: 'config', fetchStarted,
        responseReceived, httpStatus: null, errorName: 'MissingConfig', networkCode: null},
      {status: 503, headers: responseHeaders});
    }

    fetchStarted = true;
    const response = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/rpc/yg_connection_health`, {
      method: 'POST',
      headers: {apikey: key, 'Content-Type': 'application/json'},
      body: '{}',
      cache: 'no-store',
      redirect: 'manual',
    });
    responseReceived = true;
    // Do not read or return the RPC response body.
    return Response.json({ok: response.ok, phase: 'http_response', fetchStarted,
      responseReceived, httpStatus: response.status, errorName: null, networkCode: null},
    {status: response.ok ? 200 : 502, headers: responseHeaders});
  } catch (error) {
    return Response.json({ok: false, phase: 'fetch_throw', fetchStarted,
      responseReceived, httpStatus: null, errorName: safeErrorName(error),
      networkCode: safeNetworkCode(error)},
    {status: 502, headers: responseHeaders});
  }
}
