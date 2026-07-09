# CLAUDE.md — Noting 인수인계 (다음 세션에서 먼저 읽어요)

> 이 문서는 *채팅 기억이 안 넘어가는* 다음 세션을 위한 핵심 컨텍스트.
> 자세한 건 [docs/HANDOFF.md](docs/HANDOFF.md) 참고.

## 한 줄 정체

"Remind-first" 개인 메모/투두/플래너 앱. 적어두면 잊을 때쯤 알림으로 다시
만나는 컨셉. **개발자: 0921sean@gmail.com** (Seungbeom). 친구 1명 사용 중,
Play Store 등록 준비 단계.

## 기술 스택 한눈에

```
Flutter (Android 메인)
  ├── Supabase (Auth/Postgres/RLS/Edge Functions) ─ 직접 호출
  │     ├── Functions/classify      (Anthropic 프록시 + rate limit)
  │     └── Functions/delete_account
  ├── PostHog (HTTP API 직접, SDK X) ─ 분석 6개 이벤트
  ├── flutter_local_notifications    ─ 리마인드/타이머 배너/자정 플래너
  ├── showcaseview                   ─ 코치마크 (사용법 가이드)
  └── google_fonts, share_plus, supabase_flutter
```

**별도 백엔드 서버 없음.** BaaS 직접 호출이 메인 패턴.
Anthropic 키 보호 목적으로만 Edge Function 거침.

## 코드 컨벤션

- **언어/주석**: 한국어, "왜" 중심 (코드만 봐도 알 수 있는 "어떻게"는 생략)
- **State**: setState 기반, state 관리 라이브러리 없음
- **Async**: fire-and-forget은 `unawaited()` 명시
- **테마 색**: `Theme.of(context).colorScheme` 통일 (primary/surface/onSurface/error)
- **폰트 크기**: 26 (제목) / 22 (큰 액션) / 18 / 16 / 15 (본문) / 14 / 13 / 12 (캡션)
- **Service 패턴**: `static` 메서드만 (CategoryService, SupabaseService 등)
- **Models**: 단순 데이터 클래스 + `fromMap`/`toMap`

## 커밋·배포 규칙 (중요)

- **커밋 메시지 형식**: `type: 무엇을 왜` (type = feat/fix/refactor/docs/test/chore, 설명은 한국어 OK)
  - 예) `feat: 랜덤 회상 알림 스케줄러 추가` / `fix: 자정 넘어갈 때 날짜 계산 오류 수정`
  - ❌ `update`·`wip`·`작업함` 같은 무의미 메시지 금지, ❌ 초록칸 채우기용 빈 커밋 금지 (히스토리는 채용 때 평가됨)
  - (2026-07-10 이전 커밋들은 옛 `v{VERSION} - 한글 설명` 형식 — 소급 변경 안 함)
- **Co-Authored-By 라인 없음** — 기존 리포 컨벤션
- **의미 단위 커밋**: 기능 1개 / 버그 1개 / 리팩터 1개 = 커밋 1개. 세션 전체를 한 커밋으로 뭉치지 않음.
- **세션 시작**: `git status` → origin 있으면 `git pull`(다른 기기 작업분 반영). origin 없으면 즉시 알림.
- **세션 끝**: 남은 변경 전부 커밋 → `git push`. 마지막 응답에 "이번 세션에 한 일" 1~2줄 요약.
- **main에 직접 푸시** (PR/브랜치 없이) — `git add -A && git commit && git push origin main`
- **릴리스 빌드**: `./build_release.sh` → APK 빌드 + Google Drive 자동 업로드 + GitHub push
  - rclone 설정 필요 (gdrive: 리모트), 없어도 빌드는 됨
  - APK 위치: `gdrive:Apps/Noting/releases/noting-v1.0.0.apk` + 로컬 `build/app/outputs/flutter-apk/`
- **VERSION**: `pubspec.yaml`의 `version: 1.0.0+1` (실제 릴리스는 신중히 bump)

## 환경 파일 (gitignore)

- `lib/config.dart` — Supabase URL/anon key + **PostHog API key** 들어있음.
  새 머신엔 USB/AirDrop 등으로 직접 옮겨야 함.
- `assets/fonts/` — Samanco 폰트 바이너리. gitignore.

## 데이터 모델 (Supabase, 모두 RLS `auth.uid() = user_id`)

| 테이블 | 핵심 컬럼 | 비고 |
|---|---|---|
| `noting_notes` | content, created_at(ms), category | category는 text(이름 매칭) |
| `noting_todos` | text, date(YYYY-MM-DD), done, order_index, start_time, end_time | start_time/end_time은 레거시 |
| `noting_time_records` | todo_id(CASCADE), start_time(HH:MM), end_time | 한 투두에 여러 세션 |
| `noting_categories` | name, position | 사용자별 카테고리 목록 + 순서 |
| `noting_ai_calls` | created_at(timestamptz) | rate limit 추적용 |

**모든 user_id FK에 `ON DELETE CASCADE`** — 계정 삭제 시 데이터 자동 정리.
스키마 정본: [`supabase_schema.sql`](supabase_schema.sql)

## 현재 상태 (2026-06-15 기준)

- ✅ 가입/로그인/이메일 인증/비번 재설정/계정 삭제 다 동작
- ✅ Gmail SMTP 연결 (발신: `0921sean@gmail.com`)
- ✅ PostHog 분석 6개 이벤트 박힘
- ✅ AI 자동분류 (Edge Function, rate limit 5/hr·20/day)
- ✅ 카테고리 클라우드 이전 + 다기기 동기화
- ✅ 사용법 가이드 (설정 → 도움말, 코치마크 재트리거)
- ✅ Anthropic 월 한도 $50 + $20 알림 설정됨
- ✅ Anthropic 키 회전 완료 (옛 유출 키 revoke, 2026-06-15)
- ⏳ Play Store 등록 진행 중 (정책/약관 작성 중)

## 출시 전 미완 작업 (우선순위 순)

1. **개인정보처리방침 + 이용약관** (Play Store 필수)
2. **APK → AAB 전환** (Play Store는 App Bundle 표준, 설치 크기 ~17MB로 줄어듦)
3. **커스텀 도메인 + 브랜드 발신자** (현재 `0921sean@gmail.com`에서 발송 — 100명 가까워지면 어색)
4. **Sentry 같은 크래시 리포트** (5K events/월 무료)
5. **메모 카테고리 수동 변경 UI 없음** — 현재는 카테고리 안에서 새로 적거나 AI 자동분류만 가능
6. **iOS 빌드** (signing 세팅 + TestFlight) — 아이콘 asset은 준비됨

## 다음 세션에서 자주 막히는 포인트

- **폰 dev 세션이 자주 끊김** (`Lost connection to device`): 폰 화면이 꺼지면 `flutter run`이 종료됨. 개발자옵션 "켜진 상태 유지" 켜는 게 정석.
- **adb USB 디버깅 인증 팝업**: 폰을 다른 노트북 처음 연결하거나 한참 만에 연결하면 폰에 "USB 디버깅 허용" 팝업 뜸. 승인해야 잡힘.
- **카테고리 마이그레이션은 폰당 1회만 영구 실행** — 이미 마이그레이션된 폰은 다시 안 함. 새 폰에선 빈 상태로 시작.

## 주요 파일 빠른 인덱스

```
lib/
├── main.dart                 # 앱 부트, PostHog/Supabase init, 라우팅
├── config.dart               # GITIGNORE. API 키들.
├── screens/
│   ├── auth_screen.dart      # 로그인/가입 (세그먼티드 탭 UI)
│   ├── home_screen.dart      # 메모 탭 + 모드 토글 + 회상 카드
│   ├── todo_screen.dart      # 투두 탭 + 주간 캘린더 + 타이머
│   ├── planner_screen.dart   # 9:16 색깔 시간표, share_plus 공유
│   ├── settings_screen.dart  # 알림 시간/계정 삭제/로그아웃/사용법
│   ├── onboarding_screen.dart # 2페이지 컨셉 소개
│   └── category_detail_screen.dart
├── services/
│   ├── supabase_service.dart # CRUD (notes/todos/time_records)
│   ├── category_service.dart # 카테고리 (클라우드, 마이그레이션 포함)
│   ├── classifier_service.dart # Anthropic 호출 (Edge Function 거침)
│   ├── notification_service.dart # 4종 알림 + payload→source 매핑
│   └── analytics_service.dart # PostHog HTTP 직접 호출
├── utils/
│   ├── coach_mark.dart       # showcaseview 헬퍼 (Builder 감싸기 주의)
│   ├── tour.dart             # 설정→사용법에서 코치마크 재트리거용 글로벌
│   └── planner_colors.dart
└── models/                   # Note/Todo/TimeRecord/NoteGroup

supabase/
├── functions/classify/index.ts        # Anthropic 프록시 + rate limit
└── functions/delete_account/index.ts  # auth.users 삭제
supabase_schema.sql           # 정본 스키마 (CREATE + RLS + INDEX)
```

## "지금 뭐부터 하지" 가이드

작업 시작 전에:
1. `git log --oneline | head -10` 으로 최근 커밋 보기 — 직전 세션 흐름 파악
2. `git status` — 작업 중이던 변경 있는지
3. `flutter analyze lib/` — 빨간 줄 있는지
4. 폰 띄울 거면 `flutter devices` 로 연결 확인

코드 수정 후:
- 가능하면 핫 리로드 (`r`) — 새 state 필드 추가했으면 핫 리스타트 (`R`)
- `flutter analyze` 한 번 돌리고 error 없으면 커밋
- 커밋 메시지는 위 형식 엄수, main에 push, Co-Authored-By 라인 절대 넣지 말 것

브라우저 작업 필요 시 (Supabase 콘솔, PostHog 등):
- `/Users/cheonseungbeom/.claude/skills/gstack/browse/dist/browse` 사용
- Supabase·PostHog는 이미 로그인 세션이 프로필에 살아있을 가능성 큼
