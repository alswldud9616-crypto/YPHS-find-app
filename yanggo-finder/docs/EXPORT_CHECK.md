# GitHub 업로드 사본 점검 — 2026-09-27

- 별도 빈 소스 폴더에서 package-lock.json 기반 npm ci 성공.
- Node.js 24.19.0에서 npm run build 성공. TypeScript 검사와 Next.js 페이지/API 빌드 통과.
- .env.example은 환경변수 이름과 =만 포함하며 값은 모두 비움.
- 실제 키 형식, JWT, 개인키 패턴 검색에서 일치 없음. 테스트용 명시적 가짜 문자열은 테스트 코드에만 존재.
- 원본 추적 소스 파일을 모두 포함. 기존 Sites 전용 .openai/hosting.json만 GitHub 이식 시 제외.
- 기본 build는 Next.js 서버 빌드, 기존 정적 안내 빌드는 build:public으로 분리.
- node_modules, .next, .git, .env.local 및 기타 환경변수 실파일, dist, 로그, 캐시 제외.
- 실제 Supabase 키를 사용한 연결 또는 Vercel 클라우드 빌드는 실행하지 않음.
