// Temporary diagnostic: native fetch only. Remove after investigating production.
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
  const rawUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  const rawKey = process.env.SUPABASE_SECRET_KEY ?? '';
  const url = rawUrl.trim();
  const secret = rawKey.trim();

  // Inspect the original value; length and prefix describe the trimmed request value.
  const result = {
    ok: false,
    phase: 'url_parse',
    urlParseOk: false,
    isHttps: false,
    urlHasUsername: false,
    urlHasPassword: false,
    urlHasPath: false,
    urlHasQuery: false,
    urlHasHash: false,
    secretPresent: secret.length > 0,
    secretHasExpectedPrefix: secret.startsWith('sb_secret_'),
    secretLength: secret.length,
    secretChangedByTrim: rawKey !== secret,
    secretHasNonAscii: /[^\x00-\x7F]/.test(rawKey),
    secretHasCrLf: /[\r\n]/.test(rawKey),
    secretHasWhitespace: /\s/.test(rawKey),
    secretHasHeaderControl: /[\x00-\x1F\x7F]/.test(rawKey),
    headerConstructOk: false,
    requestConstructOk: false,
    fetchStarted: false,
    responseReceived: false,
    httpStatus: null as number | null,
    errorName: null as string | null,
    networkCode: null as string | null,
  };

  const reply = (status: number) => Response.json(result, {status, headers: responseHeaders});
  let baseUrl: URL;
  try {
    baseUrl = new URL(url);
    result.urlParseOk = true;
    result.isHttps = baseUrl.protocol === 'https:';
    result.urlHasUsername = baseUrl.username !== '';
    result.urlHasPassword = baseUrl.password !== '';
    result.urlHasPath = baseUrl.pathname !== '/';
    result.urlHasQuery = baseUrl.search !== '';
    result.urlHasHash = baseUrl.hash !== '';
  } catch (error) {
    result.errorName = safeErrorName(error);
    return reply(502);
  }

  // Never send a server key to an invalid URL or to an origin with embedded credentials.
  if (!result.isHttps || result.urlHasUsername || result.urlHasPassword ||
      result.urlHasPath || result.urlHasQuery || result.urlHasHash) {
    result.errorName = 'InvalidUrl';
    return reply(502);
  }

  result.phase = 'header_construct';
  if (!result.secretPresent) {
    result.errorName = 'MissingConfig';
    return reply(503);
  }
  let headers: Headers;
  try {
    headers = new Headers({apikey: secret, 'Content-Type': 'application/json'});
    result.headerConstructOk = true;
  } catch (error) {
    result.errorName = safeErrorName(error);
    return reply(502);
  }

  result.phase = 'request_construct';
  let request: Request;
  try {
    const rpcUrl = new URL('/rest/v1/rpc/yg_connection_health', baseUrl);
    request = new Request(rpcUrl, {
      method: 'POST', headers, body: '{}', cache: 'no-store', redirect: 'manual',
    });
    result.requestConstructOk = true;
  } catch (error) {
    result.errorName = safeErrorName(error);
    return reply(502);
  }

  result.phase = 'fetch';
  try {
    result.fetchStarted = true;
    const response = await fetch(request);
    result.responseReceived = true;
    result.httpStatus = response.status;
    result.ok = response.ok;
    result.phase = 'http_response';
    // Do not read or expose the response body, headers, request URL, or API key.
    return reply(response.ok ? 200 : 502);
  } catch (error) {
    result.errorName = safeErrorName(error);
    result.networkCode = safeNetworkCode(error);
    return reply(502);
  }
}
