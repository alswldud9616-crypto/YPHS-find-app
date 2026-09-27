# Health 단계 진단 v2 — 2026-09-27

이 패치는 state-v1 진단에 이어 적용합니다. SQL, RLS, Storage, Supabase 설정, 환경변수, SDK 버전은 변경하지 않습니다. 실제 GitHub/Vercel에는 직접 반영하지 않았습니다.

## 현재 로그로 알 수 있는 것

configured:true, health/health_rpc, UNCLASSIFIED, upstreamStatus:null만으로 HTTP 응답 전 실패를 확정할 수 없습니다. 기존 logger는 100~599만 upstreamStatus로 기록하여 SDK status:0도 null로 바꿨습니다. SDK fetch 예외는 반환형 error로 바뀔 수 있고, HTTP 200 뒤 data:null이면 기존 ready()의 h.version 접근에서 TypeError가 날 수 있습니다. 모두 종전 로그와 양립합니다. 현장의 원인은 새 진단 결과로 확인해야 합니다.

## 확인한 코드

- @supabase/supabase-js **2.116.0**의 독립 createClient 사용. @supabase/ssr 미사용.
- 서버 URL/Secret Key는 connectionConfig에서 읽고 URL과 키 모두 trim() 처리합니다. 시작·끝 공백/개행은 이미 제거됩니다. 문자열 내부 개행/공백은 trim()이 제거하지 않습니다. 이번 패치는 값을 고치거나 출력하지 않습니다.
- auth: persistSession:false, autoRefreshToken:false, detectSessionInUrl:false가 이미 적용돼 있습니다. 앱 전용 세션을 사용하는 서버의 고권한 클라이언트이므로 적절하며 그대로 유지합니다. 새 Secret Key 호환성을 위해 옵션을 추가로 변경해야 한다는 근거는 없습니다.
- SDK public 스키마, apikey, 새 API 키 Bearer 중복 제거를 그대로 유지합니다. 브라우저 쿠키/헤더를 전달하지 않습니다.
- 설치된 실제 SDK를 사용한 격리 테스트에서 sb_secret_ 테스트 형식으로 생성 및 RPC 전송 성공을 확인했습니다. 실제 Secret Key 유효성/프로젝트 연결 성공을 뜻하지는 않습니다.
- 공식 API 키 문서도 서버 createClient에 Secret Key를 전달하는 방식을 안내합니다: https://supabase.com/docs/guides/getting-started/api-keys

## 필수 반영 파일 (4개 모두 함께)

1. app/api/state/route.ts — state-v2 표시, ready() 단계 콜백, 안전 진단 메타데이터 로그.
2. lib/server/db.ts — ready()가 probeHealth를 호출. 일반 rpc()는 이전 동작 유지.
3. lib/server/health-probe.ts — 신규. 생성/호출/await/SDK error/health shape 분리, 오류 정보 허용 목록 처리.
4. lib/server/supabase-client.mjs — 기존 클라이언트 생성·헤더·auth 옵션 유지. 선택적 관찰 콜백으로 fetch 진입/응답/예외만 관찰. 원래 예외는 SDK에 다시 throw. 별도 요청, timeout, retry 변경 없음.

테스트 파일 tests/health-probe.mjs, tests/state-diagnostics.mjs와 이 문서도 함께 포함합니다. .env 또는 API Key는 없습니다.

## 진단 단계 및 failureKind (서버 로그)

| step | failureKind | 의미 |
|---|---|---|
| health_client | client_throw | 설정을 읽고 createClient를 생성하는 factory에서 JS throw |
| health_rpc_call | rpc_call_throw | .rpc('yg_connection_health') 호출 자체에서 동기 throw |
| health_rpc_call | rpc_await_throw | SDK thenable/promise를 await하는 중 JS throw |
| health_rpc_response | sdk_error | SDK가 {error,...}를 반환함. HTTP 오류라고 단정하지 않음 |
| health_rpc_response | rpc_response_shape | SDK 반환 envelope가 객체가 아님 |
| health_shape | health_shape | data가 null/배열/잘못된 필드 형식 |
| health_shape | 없음, code=HEALTH_NOT_READY | 형식은 맞지만 version/RLS/Storage/정수 year 조건 불충족 |

Supabase의 .rpc()는 builder를 반환하며 실제 요청이 await 시점에 실행될 수 있습니다. health_rpc_call이라는 이름이 곧 HTTP 전송을 증명하지 않습니다. factory의 config 재검사 역시 health_client 안에 포함되며 이 위치만으로 createClient 내부 오류라고 단정하지 않습니다.

## 새 로그 필드

- errorName: Error/TypeError/RangeError/SyntaxError/AbortError/TimeoutError/DOMException만 허용. 나머지는 Unknown. SDK error가 일반 객체라면 Unknown일 수 있음.
- isTypeError / fetchFailed / isAbortError: boolean만 출력. fetchFailed는 메시지에서 해당 표현 여부만 계산.
- networkCode: cause를 최대 3단계 확인하여 허용된 네트워크/TLS 코드만 기록. 임의의 code 문자열은 버림.
- sdkStatus: SDK가 제공한 숫자 상태. **0을 보존**. SDK 응답이 없으면 null.
- fetchStarted: 공통 fetch wrapper 진입 여부. true가 DNS/TCP 성공이나 서버 도달을 의미하지 않음.
- fetchResponseReceived: transport가 Response 객체를 반환했는지. 본문 해석 성공까지 의미하지 않음.
- fetchResponseStatus: 수신한 Response의 HTTP 상태. 없으면 null.
- transportFailure: SDK가 원본 예외를 감추기 전에 기록한 안전 분류. 원본 Error/message/stack/cause 객체는 보관하지 않음.

여러 시도가 있을 경우 fetchResponseReceived는 한 번이라도 받은 여부이고 status/transportFailure는 각각 마지막 관찰값입니다. 임의 로그 문자열이나 원본 네트워크 메시지를 출력하지 않습니다. 어떤 실패에서도 URL/key/Authorization/cookie/PIN/암호화 키/개인정보/스택을 기록하지 않습니다. 응답에는 version/requestId/stage/step만 추가하고 세부 예외 분류는 서버 로그에만 둡니다.

## 예시 (실제 운영 결과 아님)

SDK가 fetch 실패를 error 응답으로 바꾼 경우:

```json
{
  "version":"state-v2",
  "stage":"health",
  "step":"health_rpc_response",
  "failureKind":"sdk_error",
  "sdkStatus":0,
  "upstreamStatus":null,
  "fetchStarted":true,
  "fetchResponseReceived":false,
  "fetchResponseStatus":null,
  "transportFailure":{
    "errorName":"TypeError",
    "isTypeError":true,
    "fetchFailed":true,
    "isAbortError":false,
    "networkCode":"ENOTFOUND"
  }
}
```

실제 로그에는 event/requestId/code 및 다른 안전 분류 필드도 포함됩니다. 이 경우 반환형은 SDK error이고 내부 원인은 관찰된 TypeError입니다. ENOTFOUND 등은 진단 증거이며 특정 설정 변경을 자동으로 정당화하지 않습니다.

## 적용·확인

iPad에서 압축을 풀고 프로젝트의 동일 경로에 4개 필수 파일을 반영합니다. GitHub main에서 다른 변경을 했다면 비교 후 반영합니다. 신규 health-probe.ts를 누락하지 마세요. 테스트 파일과 문서도 추가합니다.

Codespaces에서 선택적으로:

```bash
npm ci
node tests/health-probe.mjs
node tests/state-diagnostics.mjs
npm run build
```

main에 commit/push한 후 Vercel 해당 커밋의 Production 배포 완료를 확인합니다. 개인정보 보호 탭에서 /api/state를 열고 diagnostic.version이 state-v2인지 확인합니다. X-Yanggo-Diagnostics 헤더도 state-v2입니다. 기존 v1이라면 최신 배포가 아닙니다.

실패 응답 diagnostic과 동일 requestId의 yanggo.state.failed 로그를 확인합니다. 로그 원본이 아닌 환경변수 화면이나 키는 공유하지 않습니다. 연결 성공 시 기존 정상 응답을 유지하며 실패 로그를 남기지 않습니다.

## 검증

로컬: client 동기 throw / rpc 동기 throw / await reject / AbortError / SDK 반환 error / fetch TypeError+안전 cause / HTTP 200 뒤 null health / 정상 응답 / 비허용 name·cause 제거 / 민감 문자열 비노출 / UTF-8 응답을 테스트했습니다. 설치된 SDK를 통과하는 라우트 테스트와 production build(TypeScript 포함)를 수행했습니다. 실제 Vercel 연결은 아직 확인하지 않았습니다.
