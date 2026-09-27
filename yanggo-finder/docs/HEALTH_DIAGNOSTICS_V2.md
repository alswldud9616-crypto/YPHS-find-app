# 기본 Supabase 서버 클라이언트 복구 — state-v3-native

이 문서는 이전 v2 진단 안내를 대체합니다. SQL/RLS/Storage/환경변수/의존성 버전을 변경하지 않습니다. 실제 GitHub main push와 Vercel 배포는 수행하지 않았습니다.

## 코드 점검 결과

v2 custom fetch는 진입 첫 줄에서 observe(start)를 호출했습니다. health-probe의 콜백은 이때 로컬 boolean을 true로 설정합니다. 따라서 제공된 fetchStarted:false만으로 wrapper 내부 Headers 생성이 원인이라고 결론낼 수 없습니다.

설치된 SDK의 fetchWithAuth는 custom fetch 전에 await getAccessToken(), new Headers(), apikey/Authorization 설정을 실행합니다. PostgREST builder는 이 앞 단계의 예외도 error/status:0으로 변환할 수 있습니다. 현재 현장 로그에는 원본 예외 정보가 없어 그중 어느 코드가 원인인지 확정하지 않았습니다.

기존 wrapper는 입력을 URL/string으로 변환하지 않고 input 그대로 전달했습니다. 하지만 init.headers만 복사해 Request 객체 자체의 헤더를 보존하지 못할 수 있는 구조였습니다. SDK RPC는 로컬 테스트에서 URL 문자열+init를 전달하므로 이 결함이 이번 장애를 일으켰다고 재현되지는 않았습니다. 이번 수정에서는 그 위험을 포함한 custom fetch 코드 자체를 제거했습니다.

## 실제 복구 내용

lib/server/supabase-client.mjs는 다음 형태만 사용합니다.

```js
createClient(url.trim(), key.trim(), {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false
  }
})
```

@supabase/supabase-js를 직접 사용합니다. options.global.fetch 주입, native fetch 캡처, Headers/Request 복제, Authorization 수정, 관찰 callback은 없습니다. SDK가 런타임 fetch와 헤더를 관리합니다. Secret Key는 기존 서버 변수에서 읽고 공개하지 않습니다.

lib/server/db.ts의 ready()는 DB 클라이언트를 만들고 다음 호출을 직접 실행합니다.

```ts
const {data,error,status}=await supabase.rpc('yg_connection_health');
```

error가 있으면 안전한 고정 메시지와 code/status만 전달합니다. 성공하면 healthReady(data)로 순수 shape/readiness 검증을 합니다. health-probe.ts는 이제 결과 검증 함수와 단계 타입만 포함하며 요청 실행/예외 래퍼를 포함하지 않습니다.

/api/state는 기존 안전 로그를 유지하고 식별자를 state-v3-native로 바꿉니다. 제거된 fetch 관찰값은 출력하지 않습니다. sdkStatus:0은 보존합니다. 오류 원문·키·헤더·쿠키·개인정보는 출력하지 않습니다.

scripts/check-supabase.mjs도 기본 클라이언트를 사용합니다. 이전 custom fetch의 15초 제한은 SDK의 abortSignal로 적용하여 연결 점검의 제한을 유지합니다. 운영 ready()에는 새 timeout을 추가하지 않았습니다.

## 교체할 파일

운영 코드 4개 모두 교체:
- lib/server/supabase-client.mjs
- lib/server/db.ts
- lib/server/health-probe.ts
- app/api/state/route.ts

함께 수정된 점검/테스트/문서:
- scripts/check-supabase.mjs
- tests/connection.mjs
- tests/health-probe.mjs
- tests/state-diagnostics.mjs
- docs/HEALTH_DIAGNOSTICS_V2.md (현재 문서)

ZIP에는 위 실제 변경 파일만 있습니다. 기존 main에서 별도로 바꾼 내용이 있다면 먼저 비교하세요. package.json/lock/SQL/env 파일은 교체하지 않습니다.

## 검증 및 적용

로컬에서 아래 명령을 통과했습니다.

```bash
node tests/health-probe.mjs
node tests/state-diagnostics.mjs
node tests/connection.mjs
npm run build
```

기본 SDK 생성, trim, RPC 및 Storage 전송, health shape, 연결 오류의 안전 로그, 한글 JSON 응답, TypeScript/production build를 확인했습니다. 테스트에서만 globalThis.fetch를 격리 대역으로 바꾸며 운영 코드에는 해당 처리가 없습니다. 실제 Supabase 인증/네트워크와 Vercel 운영 성공은 아직 확인하지 않았습니다.

iPad에서 압축을 풀고 동일 경로에 반영한 후 main에 커밋합니다. ZIP 파일 자체만 GitHub에 올리지 마세요. Vercel 자동 배포 완료 후 /api/state 응답의 diagnostic.version 또는 X-Yanggo-Diagnostics 헤더가 state-v3-native인지 확인합니다. 성공하면 connected:true이며, 실패하면 기존처럼 stage/step과 안전한 오류 코드가 남습니다.

제공된 로그만으로 래퍼가 근본 원인이라고 확정하거나 이 수정만으로 운영 연결이 완료됐다고 주장하지 않습니다. 이 수정은 사용자가 요청한 기본 SDK 전송 경로로의 실제 복구입니다.
