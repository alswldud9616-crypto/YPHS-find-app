# 독립 Supabase ping — direct-sdk-v1

운영 코드 추가 파일은 `app/api/supabase-ping/route.ts` 하나입니다. `tests/supabase-ping.mjs`는 격리 테스트입니다. 기존 앱 파일, SQL/RLS/Storage, 환경변수와 패키지 버전은 변경하지 않았습니다. GitHub main에서 나중에 수정한 파일도 덮어쓰지 않습니다.

## 기존 코드 점검

- `lib/server/supabase-client.mjs`는 실제로 `@supabase/supabase-js`의 `createClient(url.trim(),key.trim(),{auth:...})`를 호출합니다.
- `lib/server/config.mjs`는 `SUPABASE_SECRET_KEY`와 `NEXT_PUBLIC_SUPABASE_URL`을 정확히 읽고 trim합니다. 비어 있으면 `configured()`에서 거부합니다. 실제 Vercel 값은 확인하지 못했습니다.
- `ready()`는 `db()`로 클라이언트를 만들고 `await supabase.rpc('yg_connection_health')`를 호출합니다. 성공으로 빠지는 조기 반환이나 Promise 자체를 SDK 응답처럼 검사하는 코드는 없습니다.
- `lib/server/health-probe.ts`는 순수 반환값 검증만 하며 요청을 mock/stub/fallback으로 바꾸지 않습니다.
- `app/`와 `lib/` 운영 코드에 테스트 fetch 주입 분기는 없습니다. 테스트 대역은 테스트 파일 실행 때만 사용합니다.
- 이전 `health_rpc_response`는 SDK가 결과를 반환했다는 뜻입니다. Supabase HTTP 응답을 받았다는 증거는 아닙니다.

## 독립 route

이 route는 `db.ts`, `ready()`, `health-probe.ts`, `supabase-client.mjs`, `config.mjs`, `auth.ts`를 import하지 않습니다. 서버에서 URL/Secret Key 두 값을 직접 trim한 뒤 기본 `createClient`와 `await supabase.rpc('yg_connection_health')`만 호출합니다. 응답에는 키, URL, 원본 오류 message/stack, health 데이터나 개인정보를 넣지 않습니다. 임의 RPC 선택이나 쓰기 작업은 없습니다.

정상 예: `{"ok":true,"status":200,"hasData":true}`.
실패 예: `{"ok":false,"hasError":true,"errorCode":"SDK_ERROR","status":0,"phase":"rpc_result"}`.

- `phase=env`: 두 값 중 하나가 trim 후 비어 있음
- `phase=client`: createClient() 중 throw
- `phase=rpc`: 호출/await 중 throw
- `phase=rpc_result`: SDK error 반환 또는 data가 비어 있음

오류 코드는 허용된 DB/API 코드 또는 고정된 `ENV_MISSING`, `SDK_ERROR`, `EMPTY_DATA`, `JS_TYPE_ERROR`, `JS_ABORT_ERROR`, `JS_THROW`만 노출합니다. JSON의 `status:0`은 외부 HTTP 상태가 아닙니다. 임시 경로는 배포된 누구나 호출할 수 있으므로 운영 진단 후 route 파일을 삭제하고 다시 배포하세요.

## 적용과 해석

iPad에서 ZIP을 풀고 GitHub main의 같은 경로에 세 새 파일을 추가합니다. ZIP 자체만 업로드하지 않습니다. Vercel 자동 배포 후 Production 도메인의 `/api/supabase-ping`에서 헤더 `X-Yanggo-Ping: direct-sdk-v1`을 확인하고 `/api/state` 결과와 비교합니다.

Ping 성공은 독립 RPC가 데이터를 반환했다는 의미입니다. 이 경로는 DB readiness 값까지 검사하지 않아 앱 로직 버그를 바로 증명하지 않습니다. Ping 실패와 Vercel External APIs 0 표시도 환경변수 오류로만 확정할 수 없습니다. `phase`, `errorCode`, `status`와 두 경로의 결과를 함께 확인해야 합니다.

검증: `node tests/supabase-ping.mjs` 및 `npm run build` 통과. 실제 Supabase/Vercel 운영 연결은 아직 확인하지 않았습니다.
