# /api/state 안전 진단 패치 — 2026-09-27

## 확인 범위

기준: 전달한 yanggo-finder-github.zip의 소스. 사용자 GitHub main/Vercel 환경에는 직접 접근하지 않았습니다. SQL Editor에서 health와 익명 yg_state가 성공했다는 사용자 결과를 반영했습니다. 실제 Vercel 원인은 아직 확정되지 않았습니다.

기존 응답 configured:true + 일반 연결 실패 안내는 환경변수 형식 검사 이후 try 블록에서 예외가 발생했다는 뜻입니다. year:0은 emptyState 기본값이며 DB에서 읽은 값이 아닙니다. 기존 rpc()가 code/status를 버리고 catch가 전부 같은 안내로 바꾸어 발생 지점을 알 수 없었습니다.

## 기존 실행 순서와 조사 결과

1. configured(): connectionConfig().issues가 비었는지 확인. 실제 키의 유효성/프로젝트 일치는 확인하지 않음.
2. ready(): 서버 Secret Key로 yg_connection_health() RPC 호출. version=8, rlsReady=true, storageReady=true, 정수 year 필요.
3. actor(): yg_session 쿠키가 없으면 null. 쿠키가 있으면 app_sessions 조회. 화면에 로그인하지 않았어도 오래된 쿠키가 있으면 조회가 실행될 수 있음.
4. URL의 year를 읽고 rpc('yg_state', {p_actor:id, p_year:year?Number(year):null}) 호출.
5. claims/assignments의 codeEncrypted가 있으면 decrypt(). 올바른 미로그인 RPC 결과에는 이 목록이 없으므로 복호화는 실행되지 않음.
6. id가 있을 때만 notifications 조회, 미확인 알림 개수 조회, 표시 데이터 변환.
7. JSON 직렬화 후 connected:true. 2~7 중 예외가 나면 이전 코드는 동일한 503 안내를 반환.

SQL Editor 성공은 PostgREST HTTP 경로, API 키, service_role 실행 권한, API 스키마 노출/캐시, Vercel 네트워크까지 검증하지 않습니다. 따라서 서버 health RPC 성공을 아직 가정하지 않습니다. 필요하면 SQL Editor에서 아래를 한 번에 실행하여 service_role 실행 권한을 분리 확인할 수 있습니다(읽기 전용).

```sql
begin;
set local role service_role;
select public.yg_connection_health();
select public.yg_state(null::uuid, null::integer);
rollback;
```

이것도 HTTP API 키/네트워크 성공을 보장하지 않습니다. 오류 후 열린 트랜잭션이 남으면 rollback을 실행하세요. 문제 확인 전 RLS를 끄거나 권한을 일괄 확대하지 않습니다.

## SDK·schema·header

lib/server/db.ts는 connectionConfig().secret을 createServerClient(url,key)에 전달합니다. lib/server/supabase-client.mjs는 @supabase/supabase-js 2.116.0을 사용하고 세션 저장/자동 갱신/URL 세션 감지를 끕니다. 브라우저의 쿠키·Authorization·User-Agent를 Supabase로 전달하지 않습니다.

SDK가 설정한 apikey를 유지하고, 새 sb_secret_/sb_publishable_ 키와 정확히 같은 Bearer 헤더만 제거합니다. 실제 사용자 JWT는 제거하지 않습니다. db.schema 별도 지정이 없어 SDK 기본 public 스키마를 사용합니다. 설치한 SDK를 통과하는 격리 요청 테스트에서 RPC POST의 Content-Profile: public, apikey, API 키 Bearer 제거 및 yg_state 인자를 확인했습니다. 코드에서 헤더/스키마 불일치는 재현되지 않았습니다. 실제 Supabase 호환 여부는 배포 후 응답으로 확인해야 합니다.

공식 근거: https://supabase.com/docs/guides/getting-started/api-keys

## main에 반영할 파일

필수 교체 2개:
- app/api/state/route.ts: 단계/세부 작업 추적, 안전 로그, 진단 응답, UTF-8 Content-Type, 반환 데이터 형태 검증.
- lib/server/db.ts: RPC 오류의 code/status를 보존. 기존 다른 API의 오류 메시지 동작은 유지. 진단 경로에서는 message를 출력하지 않음.

함께 추가 권장:
- tests/state-diagnostics.mjs: 실제 SDK + 격리된 전송/세션 의존성으로 실패 경로 테스트.
- docs/STATE_DIAGNOSTICS.md: 이 안내.

package.json, lock 파일, SQL, 환경변수, UI, Supabase client 코드는 변경하지 않았습니다. 마이그레이션 재실행이나 키 교체가 필요한 패치가 아닙니다. Secret/PIN_PEPPER/DATA_ENCRYPTION_KEY 값을 추가하거나 변경하지 마세요.

## 적용 방법 (iPad)

1. ZIP을 파일 앱에서 압축 해제합니다.
2. GitHub 또는 Codespaces에서 기존 프로젝트의 같은 경로에 위 파일을 반영합니다. ZIP 자체를 저장소에 올리지 않습니다. 이후 별도 수정한 내용이 있다면 먼저 비교합니다.
3. Codespaces에서는 프로젝트 폴더에서 아래를 실행할 수 있습니다.

```bash
npm ci
node tests/state-diagnostics.mjs
npm run build
git diff -- app/api/state/route.ts lib/server/db.ts
git add app/api/state/route.ts lib/server/db.ts tests/state-diagnostics.mjs docs/STATE_DIAGNOSTICS.md
git commit -m "Add safe state readiness diagnostics"
git push origin main
```

main 브랜치인지 먼저 확인하고 사용합니다. 보호 브랜치면 PR로 반영합니다. 제공 파일에는 실제 키가 없으며 .env.local은 커밋하지 않습니다.

4. Vercel에서 해당 커밋의 Production 배포가 완료됐는지 확인합니다.
5. 개인정보 보호 탭에서 운영 주소의 /api/state를 엽니다. diagnostic.version=state-v1 또는 X-Yanggo-Diagnostics: state-v1 헤더로 패치 반영을 확인합니다. 성공 응답에는 diagnostic이 없고 헤더만 있습니다.
6. 실패 응답의 diagnostic과 같은 requestId의 Vercel Runtime Log 한 줄을 확인합니다. 원본 요청/쿠키/환경변수 화면은 공유하지 않습니다.

## 예상 실패 응답 (예시이며 실제 결과 아님)

```json
{
  "configured": true,
  "connected": false,
  "year": 0,
  "error": "서버 연결을 확인하지 못했어요. 잠시 후 다시 시도해주세요.",
  "errorCode": "STATE_UNAVAILABLE",
  "diagnostic": {
    "version": "state-v1",
    "requestId": "서버에서-새로-생성한-UUID",
    "stage": "health",
    "step": "health_rpc"
  }
}
```

실제 응답에는 원래 emptyState 필드도 포함됩니다. requestId는 사용자 ID나 세션 토큰이 아니라 요청별 무작위 UUID입니다. 실패 로그 event는 yanggo.state.failed이며 stage/step/requestId와 안전한 code/upstreamStatus만 출력합니다. 서버 오류 message/details/hint/stack, 환경변수, 헤더, URL, 쿠키, RPC 인자/응답 행은 출력하지 않습니다. 모르는 오류 코드는 UNCLASSIFIED, HTTP 상태가 없으면 null입니다. 일반 오류는 503, 기존 config 미설정 응답의 200은 유지했습니다.

| stage / step | 의미 |
|---|---|
| config / environment | 환경변수 검사 실패 |
| health / health_rpc | health RPC 예외 또는 조건 불충족. HEALTH_NOT_READY는 RPC가 반환됐으나 판정 실패 |
| state / session | 쿠키/세션 확인 실패 |
| state / year_parameter | URL/연도 파라미터 처리 실패 |
| state / state_rpc | 서버의 yg_state RPC 실패 |
| postprocess / state_shape | JSON 객체/정수 year가 아닌 반환값 |
| postprocess / pickup_shape | claims/assignments 구조 불일치 |
| postprocess / pickup_decrypt | 수령번호 형식/복호화 실패 |
| postprocess / notifications 또는 unread_count | 로그인 계정의 알림 조회 실패 |
| postprocess / notifications_map 또는 serialize | 데이터 변환/JSON 직렬화 실패 |

HTTP 401은 API 인증 경로 확인, 403/42501은 권한 확인, PGRST202는 RPC 검색·시그니처·스키마 캐시 확인에 도움이 됩니다. 코드 하나만으로 원인을 단정하지 않습니다. UNCLASSIFIED도 stage/step으로 발생 위치를 좁힐 수 있습니다.

## 인코딩 및 검증 범위

변경 파일은 UTF-8이며 application/json; charset=utf-8를 명시했습니다. 실제 NextResponse의 JSON 응답을 읽어 한글 문자열과 replacement character 부재를 검사했습니다. 인코딩 표시가 계속 깨지면 ASCII errorCode/diagnostic으로 먼저 구분할 수 있습니다. 운영 배포의 바이트/헤더는 아직 확인하지 않았으므로 현재 깨짐의 원인이 해결됐다고 단정하지 않습니다.

로컬 검증: 단계별 예외, 비밀값이 들어간 가짜 오류의 로그/응답 비노출, SDK public schema/apikey, 미로그인 경로 알림 생략, UTF-8 JSON 테스트 통과. npm run build(TypeScript 포함) 통과. 실제 Supabase/Vercel 연결 테스트 및 GitHub main push는 수행하지 않았습니다.
