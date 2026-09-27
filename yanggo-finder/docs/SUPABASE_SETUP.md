# 양고 찾기 — Supabase 연결 준비 및 운영 전환

2026-09-23 · v0.4.0

**현재 실제 Supabase에는 연결하지 않았습니다.** 이 문서는 연결 코드·SQL·로컬 테스트 결과와 사용자가 직접 해야 할 설정을 구분합니다. DB 비밀번호나 서버 키를 채팅·공개 코드에 붙이지 마세요.

## 1. 먼저 알아둘 연결 구조

기존 UI → Next.js 서버 API → Supabase PostgreSQL / Private Storage.

- 모든 학생과 관리자는 동일한 이름·학번·6자리 PIN 가입/로그인을 사용합니다.
- PIN 해시는 `pin_credentials`, 서버 세션 해시는 `app_sessions`에 저장됩니다. PIN 원문은 저장하지 않습니다.
- **Supabase Auth 이메일/비밀번호 계정을 만드는 앱이 아닙니다.** 가입 결과는 Dashboard의 Authentication Users가 아니라 `public.users`, `student_verifications`에서 확인합니다.
- 학생은 브라우저에서 DB를 직접 읽거나 쓰지 않습니다. 서버가 HttpOnly 세션을 확인하고 DB 업무 함수가 현재 학년도·역할·소유권을 다시 검사합니다.
- Publishable Key는 연결 점검에서 공개 접근 차단을 검증하는 데 사용합니다. 앱 브라우저에 Supabase 클라이언트를 새로 넣거나 private 테이블을 공개하지 않습니다.
- 따라서 **URL + Publishable Key만으로 서비스 전체를 켤 수 없습니다.** 서버 전용 키, PIN/수령번호 비밀값, migration, 학년도 설정도 필요합니다.

현재 공개된 `chatgpt.site`는 동일 UI의 **정적 운영 준비 화면**입니다. 거기에 키만 추가하면 작동하는 구조가 아닙니다. 실제 운영은 현재 저장소의 Next.js 서버를 Vercel 등 Node.js 지원 호스트에 배포해야 합니다. 프론트엔드를 새로 만들 필요는 없습니다.

## 2. 기능별 실제 연결 위치

| 기능 | 서버/API 및 SQL 처리 | DB/Storage |
|---|---|---|
| 이름·가입 계정 | `/api/auth` signup → `yg_signup` | `users.display_name`, UUID |
| 학번·학생증 상태 | 가입/재인증 → `yg_signup`, 승인 → `yg_action VERIFY` | `student_verifications`: 학년도·학번·상태·승인자·시각 |
| 6자리 비밀번호 | `hashPin` / `verifyPin`: salt + pepper + scrypt | `pin_credentials.pin_hash` |
| 로그인·실패 제한 | `/api/auth` login/logout, `yg_rate_limit` | `app_sessions`, `login_limits` |
| 학생증 제출·열람·삭제 | 서버 `upload`, `/api/image`, `cleanup` | `student-verifications` private bucket, `verification_uploads`, `upload_jobs` |
| 사용자 role | `yg_role`, `yg_verified`, `yg_verifier` | `council_roles`: school_year·is_head·can_deliver·기간·revoked_at |
| 관리자 후보 | `ALLOWLIST_ADD/DISABLE`, 승인 트리거 | `admin_allowlist`, claimed_user_id·activated_at |
| 권한 추가·회수 | `ROLE`, `yg_role_scope`, 서버 전용 최고관리자 절차 | `council_roles`, `audit_logs`, `notifications` |
| 등록 요청·보완 | `/api/action` SUBMIT/RESUBMIT/SUPPLEMENT | `item_submission_requests` |
| 실물 확인·공식 승인 | RECEIVE/PUBLISH, DIRECT_REGISTER | `items`, `item_private_details`, `item_history` |
| 공식 목록·상세 | `/api/state` → `yg_state` | `items`, `categories`, `locations` |
| 분실물 사진 | 서버 upload + 승인 이미지 API | `item-photos` private bucket, `item_images` |
| 찾아가기·추가 특징 | CLAIM/ANSWER/DECIDE | `claim_requests.private_answer`, status, feedback |
| 수령번호 | 서버 생성·해시·AES-GCM 암호화, 반환 시 제거 | `claim_requests.pickup_code_hash/ciphertext` |
| 임원 가능 시간 | AVAILABILITY/REMOVE_AVAILABILITY | `staff_availability`, `pickup_slots` |
| 예약·배정 | RESERVE/CANCEL, 10분 슬롯 잠금·복지부 우선 | `pickup_schedules`, `pickup_slots` |
| 수령 완료 | COMPLETE: 담당자·번호·실물 전달 검증 | 물품/예약/요청 상태, `item_history`, 알림 |
| 미수령·재예약 | NO_SHOW: 예약 종료 시각 검증 | 기존 예약 유지, 물품 보관, 새 예약 가능 |
| 장기 미수령 | `yg_state`에서 공식 승인 후 14일 계산 | `items.approved_at`, 상태; 삭제 없음 |
| 알림·읽음·임박 | `yg_notify`, READ, `yg_maintenance` | `notifications` (앱 내부 알림); outbox는 외부 알림 확장용으로 미사용 |
| 학년도·인수인계 | YEAR, 연도 조회 | `school_years`, `year_transfers`, `item_history`, 역할·후보 만료 |
| 관리 기록 | `yg_log`, 역할 변경 감사 기록 | `audit_logs`: actor·대상·시각·학년도·details |
| 연결 판정 | 서버 `ready()` → `yg_connection_health` | schema version 8, 테이블 RLS, Storage, 현재 학년도 |

모든 주요 사용자 작업은 실제 Supabase CRUD/RPC를 호출합니다. 화면의 검색어·탭·사진 미리보기·로딩은 React state지만 영속 데이터 저장소로 사용하지 않습니다. `components/`, `app/`, `lib/`의 운영 코드에 Mock 레코드·localStorage·시연 계정은 없습니다. `tests/`의 격리된 데이터는 테스트 실행 때만 생성하며 프로덕션에 import하지 않습니다. 관리자/장기 미수령 통계도 DB 결과에서 계산합니다.

## 3. 사용자가 직접 설정할 순서

### A. Supabase 프로젝트 생성 및 SQL 실행

1. 학교가 인수인계할 수 있는 계정으로 새 Supabase 프로젝트를 만듭니다.
2. 다음 **한 가지 방법만** 선택합니다.

**새 빈 프로젝트 / SQL Editor 방식:** `supabase/production-fresh.sql` 전체를 SQL Editor에서 한 번 실행합니다. 001~008 migration을 한 트랜잭션으로 적용하며 fake 계정·분실물·관리자 명단은 넣지 않습니다. 기존 `public.users`가 있으면 중단합니다. 오류가 나면 문제를 확인한 후 다시 실행하고, 일부 테이블을 지워 우회하지 마세요.

**기존 DB / migration 방식:** `supabase/migrations/`에서 이미 반영된 파일을 제외하고 이름 순서대로 적용합니다. 001~007까지 적용돼 있다면 008만 적용합니다. Supabase CLI 프로젝트 연결을 사용 중이면 같은 파일들을 `supabase db push`로 적용합니다. SQL Editor 설치는 CLI의 `supabase_migrations` 실행 이력을 자동 작성하지 않습니다. 나중에 CLI로 바꿀 때는 적용 이력을 확인·동기화한 후 사용하고 전체를 다시 실행하지 마세요.

3. 두 bucket이 private인지 확인합니다. `student-verifications`, `item-photos`. 승인 사진도 서버 권한을 거쳐 제공합니다.

### B. 환경변수 설정 (2026-09-26 공식 문서 기준)

대시보드에서 복사할 값은 **같은 프로젝트의 세 값**입니다.

- [ ] 프로젝트를 열고 상단 **Connect**를 누릅니다. 프레임워크에서 Next.js를 선택하고 표시된 **Project URL** (`https://…supabase.co`)을 `NEXT_PUBLIC_SUPABASE_URL`에 복사합니다. `postgresql://…` DB 연결 문자열이 아닙니다.
- [ ] **Settings → API Keys → Publishable and secret API keys**를 엽니다. Publishable key의 **값** (`sb_publishable_…`)을 `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`에 복사합니다. Connect의 공개 키도 같은 용도로 사용할 수 있습니다.
- [ ] 같은 탭에서 Secret key를 확인하고 **값** (`sb_secret_…`)을 `SUPABASE_SECRET_KEY`에 복사합니다. 키 이름 `default` 또는 키 ID가 아니라 전체 키 값입니다. 새 키가 없다면 **Create new API keys**로 생성합니다. Legacy 탭의 `anon`/`service_role`은 새 설치에 사용하지 않습니다.
- [ ] 이 값들은 아래 명령으로 만든 로컬 `.env.local` 또는 실제 Next.js 호스팅의 **서버 환경변수/Secrets 설정**에 직접 입력합니다. Supabase SQL Editor, 소스 코드, `.env.example`, 채팅에는 넣지 않습니다.
- [ ] `APP_ORIGIN`은 개발 시 `http://localhost:3000`, 배포 시 **Next.js 서버의 실제 HTTPS 주소**로 설정합니다. Supabase URL이 아닙니다. 기존 정적 시연 URL을 운영 서버 주소로 사용하지 않습니다.

이 프로젝트의 `SUPABASE_SECRET_KEY`는 단일 문자열입니다. Edge Functions용 `SUPABASE_SECRET_KEYS` JSON과 혼동하지 마세요. 현재 앱은 Next.js 서버 API를 사용하며 Supabase Edge Functions 설정은 필요하지 않습니다.



프로젝트 디렉터리에서:

```bash
npm ci
npm run setup:env
```

`setup:env`는 `.env.local`이 없을 때만 생성하고, 세 비밀값을 각각 무작위로 넣습니다. 기존 파일이나 암호화 키를 덮어쓰지 않습니다. 비밀값을 화면에 출력하지 않습니다. 파일에서 다음 세 값을 직접 채웁니다.

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://사용할-프로젝트.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=프로젝트의-Publishable-Key
SUPABASE_SECRET_KEY=서버-전용-키
```

| 환경변수 | 구분·설정 |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | 프로젝트 URL. 공개 가능 |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | 공개 키. 서버 키를 넣으면 설정 검증에서 거부 |
| `SUPABASE_SECRET_KEY` | 서버 전용. `sb_secret_` 형식의 Secret Key. `NEXT_PUBLIC_` 접두사 금지 |
| `APP_ORIGIN` | 개발 `http://localhost:3000`, 운영 실제 HTTPS origin. 경로 없이 설정 |
| `PIN_PEPPER` | 32자 이상, setup:env 자동 생성. 로그인 해시용 |
| `DATA_ENCRYPTION_KEY` | 64자리 hex, setup:env 자동 생성. 수령번호 암호화용 |
| `CRON_SECRET` | 32자 이상, setup:env 자동 생성. 정리/알림 작업 호출용 |

새 설치에서는 `SUPABASE_SECRET_KEY`만 설정합니다. 이전 `SUPABASE_SERVICE_ROLE_KEY`는 새 변수가 없을 때만 호환용으로 읽습니다. 둘 다 있고 값이 다르면 연결을 거부하므로 이전 변수는 제거하세요. 공개 변수에 Secret Key 또는 service_role JWT를 넣어도 거부합니다. 키 문자열 형식 검사는 실제 키 유효성 검증을 대신하지 않으며 최종 확인은 `db:check`에서 합니다.

새 코드에서는 `NEXT_PUBLIC_SUPABASE_URL`을 우선 사용합니다. 이전 `SUPABASE_URL`은 이전 설치 호환용으로만 남겼고 두 값이 서로 다르면 설정을 거부합니다. 키는 서버 호스트의 비밀 환경변수에도 동일하게 설정해야 합니다. PIN_PEPPER나 암호화 키를 배포할 때마다 새로 만들면 기존 계정/수령번호가 깨집니다.

### C. 최초 학년도와 관리자 준비

아직 학년도가 없을 때만 `npm run bootstrap`에 다음 JSON을 입력합니다.

```json
{"mode":"initialize-year","year":2026}
```

이는 테스트 계정 생성이 아니라 실제 운영 학년도 설정입니다. 이후:

```bash
npm run db:check
npm run dev
```

`db:check`는 **읽기 전용**입니다. 서비스 키 연결, migration 008, RLS, Private Storage 설정, 현재 학년도, Publishable Key의 직접 조회 차단을 검사합니다. 성공해도 실제 학생 흐름·객체 삭제·동시 예약 테스트를 대신하지 않습니다.

첫 최고관리자도 같은 가입 화면에서 학생증을 제출합니다. 학교 운영 담당자가 대면 신원 확인 후 해당 UUID를 `first-super`로 활성화합니다. 이어 실제 부장/회장단 후보를 사전 등록하고 해당 학생이 가입하면 `first-verifier` 절차로 최초 인증 담당자를 설정합니다. 이후에는 부장/회장단이 웹에서 승인합니다. **구체적인 입력 형식과 안전 조건은 README의 ‘최초 관리자 설정’에 있습니다.** 별도 관리자 계정이나 관리자 로그인 화면은 만들지 않습니다.

### D. 운영 서버와 주기 작업

1. 현재 Next.js 프로젝트를 Node.js 지원 서버에 배포합니다. 일반 `npm run build`/`npm start`를 사용합니다. 정적 `dist` 폴더만 배포하면 API가 작동하지 않습니다.
2. 모든 서버 환경변수와 실제 `APP_ORIGIN`을 맞춥니다. 배포 후 설정을 변경했다면 재시작/재배포합니다.
3. `GET /api/maintenance`를 5분 간격으로 호출하도록 스케줄러를 설정합니다. 인증 헤더는 `Authorization: Bearer <CRON_SECRET>`이며 URL query에 비밀값을 넣지 않습니다. 코드만 작성되어 있으며 실제 스케줄은 아직 등록하지 않았습니다.
4. `docs/ACCEPTANCE_TEST.md`를 실제 프로젝트에서 완료한 뒤 학생들에게 운영 주소를 안내합니다.

## 4. RLS와 서버 권한의 역할

- 25개 앱 테이블에 RLS와 FORCE RLS를 적용합니다.
- `yg_server_only`는 `anon`, `authenticated`의 모든 직접 조회/추가/수정/삭제를 막는 **restrictive policy**입니다. 테이블 GRANT도 회수했습니다. 나중에 넓은 허용 정책을 실수로 추가해도 이 제한이 유지됩니다.
- custom 세션이 Supabase Auth JWT가 아니므로 `auth.uid() = user_id` 같은 잘못된 정책을 붙이지 않습니다.
- 서버 전용 키는 RLS를 우회합니다. 따라서 서버 세션 검사와 각 SQL 함수의 role·현재 학년도·소유권 검사가 **별도로 필수**입니다. RLS만으로 service_role을 제한한다고 주장하지 않습니다.
- 일반 학생의 state에는 자신의 비공개 요청만 들어갑니다. 관리자 후보·다른 학생 요청·학생증·내부 보관번호는 반환하지 않습니다. 담당 임원도 자신의 배정만 받습니다.
- `/admin`, `/staff`는 서버에서 역할을 확인합니다. 클라이언트 메뉴 숨김만으로 보호하지 않습니다.
- 업무 함수, bootstrap, health RPC의 공개 실행 권한은 없습니다. 클라이언트가 actor나 role을 임의로 바꿔도 서버 세션과 SQL 범위 검사를 통과해야 합니다.

## 5. 사진 저장·자동 삭제

두 bucket은 비공개, 파일당 5 MiB, 저장 형식은 WebP입니다. 업로드 API는 JPG/PNG/WebP를 디코딩·크기 조정·메타데이터 제거한 뒤 WebP로 저장합니다. 사용 호스트의 HTTP 요청 크기 제한도 실제 파일로 확인해야 합니다.

Storage의 `yg_private_server_only` restrictive policy는 두 bucket의 공개/로그인 사용자 직접 접근을 차단합니다. 다운로드 링크를 외부에 열어두지 않고 서버 이미지 API가 매번 권한을 검사합니다.

학생증 승인/거절 → 같은 DB 트랜잭션에서 삭제 대기 → 서버가 Storage API `remove()` → 성공하면 경로를 비우고 DELETED 기록. 실패하면 재시도 큐를 유지합니다. 처리된 학생증은 물리 삭제가 지연되어도 이미지 API에서 즉시 차단됩니다. 72시간 미처리 사진과 연결되지 않은 업로드도 maintenance에서 정리합니다. **DB 행 삭제만으로 실제 파일이 지워지는 것으로 취급하지 않습니다.**

## 6. 연결 상태 표시

- 환경변수 누락/형식 오류: 연결 준비 상태, 가입·등록·예약 비활성.
- 네트워크 오류·잘못된 키·migration 없음: 연결 실패 상태. 성공으로 표시하지 않음.
- RLS/버킷/학년도 미설정: 설정 확인 상태. 가입/변경 요청은 서버에서도 503으로 차단.
- 모든 구성 점검과 DB 조회 성공: 실제 데이터 표시. 빈 DB는 빈 목록이며 샘플 물품을 넣지 않음.
- 현재 공개 정적 화면: 계속 ‘운영 준비 중’. 연결된 것처럼 자동 전환하지 않음.

## 공식 근거

- 키 종류와 서버 전용 키: https://supabase.com/docs/guides/getting-started/api-keys
- RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- Storage 접근 정책: https://supabase.com/docs/guides/storage/security/access-control
- 실제 객체 삭제: https://supabase.com/docs/guides/storage/management/delete-objects

## 2026-09-26 Secret Key 전환 점검

- `lib/server/config.mjs`: 새 서버 변수 우선, 이전 변수 호환, 충돌 시 거부.
- `lib/server/db.ts`: `server-only` 모듈의 Supabase 클라이언트에 Secret Key 전달.
- `scripts/bootstrap.mjs`, `scripts/check-supabase.mjs`: 같은 설정 사용.
- `scripts/setup-env.mjs`: 수정된 `.env.example`으로 파일 생성, 기존 파일 보존.
- 설치된 `@supabase/supabase-js` 2.116.0은 새 키를 지원하지만 DB 요청에서 키를 Bearer에도 중복 전달합니다. `lib/server/supabase-client.mjs`의 공통 전송 설정이 새 API 키와 일치하는 Bearer만 제거하여 `apikey`로 전달합니다. 실제 사용자 JWT는 제거하지 않습니다. 격리된 SDK 요청 테스트로 확인합니다.
- `production-fresh.sql` 변경 불필요. Secret Key도 DB의 `service_role` 권한으로 동작하므로 SQL role 이름을 `secret`으로 바꾸지 않습니다.
- Secret Key는 RLS를 우회하므로 서버의 학생 세션/역할/소유권 검사와 SQL 함수 검사를 그대로 유지합니다. Publishable Key로는 학생 데이터 직접 조회를 허용하지 않습니다.
- 실제 키 입력, 실제 Supabase 연결, Storage API 삭제, 운영 서버 배포 후 전체 수령 흐름은 사용자가 설정한 후 별도 확인해야 합니다. 준비 완료를 연결 완료로 표시하지 않습니다.

공식 근거 (확인 2026-09-26):
- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys
