# iPad → GitHub → Vercel

## ZIP과 파일 구조

ZIP을 iPad 파일 앱에 저장한 뒤 눌러 압축을 풉니다. `yanggo-finder` 폴더 안의 파일과 하위 폴더를 GitHub 저장소에 올립니다. ZIP 파일 자체만 저장소에 올리면 Vercel이 코드를 빌드할 수 없습니다.

- 저장소 최상위에 package.json, package-lock.json, next.config.ts, tsconfig.json, postcss.config.mjs, vercel.json, .gitignore, .env.example, README.md를 둡니다.
- app/, components/, lib/, public/, scripts/, tests/, supabase/, docs/, public-view/, ops/의 구조를 유지합니다. 파일들을 한 폴더로 평탄화하지 마세요.
- .gitignore와 .env.example이 iPad 파일 선택기에 보이지 않으면 GitHub의 Add file → Create new file에서 같은 이름으로 생성합니다. .env.example 내용은 아래와 같습니다.

```dotenv
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
SUPABASE_SECRET_KEY=
APP_ORIGIN=
PIN_PEPPER=
DATA_ENCRYPTION_KEY=
CRON_SECRET=
```

## GitHub

1. Safari에서 GitHub에 로그인하고 새 저장소를 만듭니다. 비공개(Private) 저장소로 시작해도 Vercel에서 연결할 수 있습니다.
2. Add file → Upload files에서 압축을 푼 소스를 올리고 Commit changes를 누릅니다. 폴더 업로드가 가능한 환경에서는 구조를 그대로 유지합니다.
3. iPad 파일 선택기가 폴더 업로드를 지원하지 않으면 폴더별로 업로드합니다. GitHub에서 Add file → Create new file로 `app/.gitkeep` 같은 경로를 생성한 뒤 해당 폴더로 들어가 Upload files를 사용합니다. 중첩 폴더도 같은 방식으로 만들며 각 파일은 원래 위치에 둡니다. 업로드가 끝나면 임시 .gitkeep은 삭제해도 됩니다.
4. 최상위 package.json과 app/api/ 하위 코드, lib/server/, supabase/production-fresh.sql, docs/ 문서가 보이는지 확인합니다.
5. 폴더가 한 단계 더 감싸진 채 올라갔다면 Vercel Root Directory를 package.json이 있는 폴더로 선택합니다.

GitHub 브라우저 업로드는 한 번에 100개 파일, 파일당 25 MiB 제한이 있습니다. 이 패키지의 소스는 해당 범위 이내입니다. 실제 키는 GitHub에 입력하지 않습니다.

## Vercel

1. Add New → Project에서 GitHub 저장소를 Import합니다.
2. Framework Preset: Next.js, Root Directory: package.json이 있는 디렉터리, Node.js: 24.x.
3. Install Command: npm ci. Build Command: npm run build. Output Directory는 기본값을 유지합니다. dist나 out으로 지정하지 않습니다. 포함된 vercel.json이 Next.js 설정을 제공합니다.
4. Environment Variables에 .env.example의 7개 변수를 직접 등록합니다. Secret Key와 나머지 비밀값은 서버 전용입니다. APP_ORIGIN은 실제 서비스의 HTTPS origin이며 Supabase URL과 다릅니다. 배포 주소가 아직 없다면 최초 배포에서 연결 전 화면을 확인한 뒤 URL을 설정하고 재배포할 수 있습니다.
5. Supabase SQL 적용, 학년도 초기화와 최초 관리자 설정은 README.md와 SUPABASE_SETUP.md를 따릅니다. iPad 자체에서는 npm 명령을 실행하지 않습니다. 해당 명령은 신뢰할 수 있는 Node.js 터미널 환경에서 실행해야 합니다. 환경변수 입력만으로 학년도/최초 관리자가 만들어지지 않습니다.
6. 사진 정리와 예약 임박 알림용 5분 간격 스케줄러는 별도로 설정합니다. ops/vercel-cron.example.json은 참고용이며 자동 활성화하지 않았습니다. 사용하는 호스팅 요금제의 실행 주기 제한도 확인합니다.
7. ACCEPTANCE_TEST.md의 실제 Supabase 테스트를 마친 후 학생에게 링크를 배포합니다.

실제 Supabase 연결, Vercel 배포, 운영 테스트는 이 ZIP 제작 과정에서 수행하지 않았습니다.

## 구성 변경

기존 UI, API, SQL, 테스트, 정적 안내 화면 코드는 포함했습니다. .git 이력, 기존 Sites 전용 .openai 연결 설정, 설치 폴더, 빌드 산출물, 환경변수 실파일은 제외했습니다. GitHub/Vercel용 사본의 기본 build는 정적 안내 화면을 만드는 후속 명령을 분리했으며 dependencies와 고정 버전은 유지했습니다.

공식 안내 (확인 2026-09-27):
- https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository
- https://vercel.com/docs/builds/configure-a-build
- https://vercel.com/docs/functions/runtimes/node-js/node-js-versions
