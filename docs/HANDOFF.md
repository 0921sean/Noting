# Noting — HANDOFF (장기 컨텍스트)

CLAUDE.md를 먼저 읽고 이 문서로 오세요. 여기는 *왜 이렇게 짰는지*, 빠진
선택지들, 그리고 함정들.

---

## 1. 아키텍처 결정과 이유

### BaaS 직접 호출 (Supabase 직통)
- **선택**: Flutter 클라이언트가 `supabase_flutter` SDK로 Postgres에 직접 접근.
  별도 Node/Python 백엔드 없음.
- **이유**: 1인 개발 + CRUD가 대부분. 백엔드를 끼면 *오히려 느려진다*
  (홉 2개 + 서버 유지보수). RLS로 권한 격리.
- **트레이드오프**: 복잡한 비즈니스 로직이 필요해지면 클라이언트로 들어가서
  지저분해짐. 그땐 Edge Function 추가로 풀어내면 됨.

### Anthropic 호출만 Edge Function 뒤로
- **선택**: `supabase/functions/classify` 함수가 Anthropic API 키를 들고
  프록시함. 앱은 자기 Supabase JWT로 함수를 부르고, 함수가 키 붙여 전달.
- **이유**: APK 안에 Anthropic 키가 박히면 누구나 추출해서 청구 폭주
  시킬 수 있음. 키를 서버 시크릿에만 두는 게 표준 보안 패턴.
- **과거 함정 (해결됨, 2026-06-15)**: 처음 만든 키가 옛 APK 여러 개에 박혀
  배포됐었음. 새 키 발급 → Edge Function 시크릿 교체 → 옛 키 revoke 완료.
  유출됐던 키는 이제 무력화됨.

### Anthropic 비용 보호 다층
- **Anthropic 콘솔**: 월 한도 $50 + $20 알림
- **Edge Function**: 사용자별 시간당 5회 / 일 20회 (RLS bypass 위해 service_role 클라이언트로 `noting_ai_calls` 테이블에 기록)
- **함수 자체**: `max_tokens` 4096 상한

### PostHog SDK 대신 HTTP 직접 호출
- **사실**: `posthog_flutter` 5.x는 AGP 8+ / Kotlin 1.9+ 요구.
  4.x는 minSdk 23 요구. 둘 다 시도했지만 빌드 깨졌음.
- **해결**: PostHog Capture API에 HTTP POST 직접. SDK 없이도 분석은 동일.
  코드는 [lib/services/analytics_service.dart](../lib/services/analytics_service.dart).
- **결과**: minSdk만 23으로 올리는 선에서 멈춤 (Android 6+ 99% 커버).

### 카테고리 클라우드화 (이전엔 SharedPreferences였음)
- **사실**: 초기엔 카테고리 목록을 폰 로컬(`SharedPreferences`)에 저장.
  사용자별이 아니라 **폰별**. 같은 폰 공유 시 카테고리 누수 사고가 났음.
- **해결**: `noting_categories` 테이블 + RLS로 이전. 폰당 1회 일회성
  마이그레이션 로직으로 옛 로컬 데이터를 클라우드로 옮김.
- **함정**: 옛 마이그레이션 코드가 사용자별이 아니어서 "이 폰에서 처음
  로그인한 사람"이 옛 카테고리를 가져갔음. 실제로 사고가 한 번 났고
  SQL로 복구함. 현재는 마이그레이션이 **폰당 1회만 영구 실행** + 옛
  로컬 키도 즉시 폐기.

### 세로 모드 고정
- **사실**: `SystemChrome.setPreferredOrientations([portraitUp])`.
- **이유**: 가로 모드 만들면 메모 그리드/투두 캘린더가 어색해짐.
  반응형 부담 제거. 노트 앱은 보통 세로.

### 알림 source 추적
- 모든 알림 payload에 식별자 들어감:
  - 메모 리마인드 → note_id (숫자)
  - 자정 플래너 → `"planner"`
  - 90분 nudge → `"nudge"`
- 콜드 스타트 시 `NotificationService.getLaunchSource()`로 source 판별.
- `app_open` 이벤트에 `source: organic | memo_reminder | todo_nudge | planner_alarm`
  속성 박힘. **Noting의 핵심 가설**("알림이 사용자를 돌려세우는가") 검증용.

---

## 2. 보안 / 운영 점검

### RLS 정책
모든 사용자 데이터 테이블에 동일 정책:
```sql
using  (auth.uid() = user_id)
with check (auth.uid() = user_id)
```
anon key가 APK에 박혀있어도 (BaaS 표준) RLS가 격리 보장.

### 본인 운영 계정 보호
`0921sean@gmail.com`은 **클라이언트 + Edge Function 양쪽**에서 삭제 차단.
실수 / 누군가의 악의 / 둘 다 막힘.

### 이메일 인증 강제
Supabase Auth → Confirm email ON. 미인증 계정은 로그인 자체가 안 됨.
봇 1차 방어. CAPTCHA는 보류 (Flutter 측 위젯 통합 30분 작업).

### Anthropic 키
- **현재 상태 (2026-06-15)**: 회전 완료. 옛 노출 키(옛 APK에 박혀있던 것)는
  revoke 했고, Edge Function 시크릿은 새 키로 교체됨. 유출 위험 해소.
- **회전 절차 (참고용 기록)**: Anthropic 콘솔 → 새 키 → Supabase Edge Functions →
  Secrets → `ANTHROPIC_API_KEY` 새 값으로 교체 → Anthropic 콘솔 옛 키 revoke.

---

## 3. 알림 시스템 상세

`flutter_local_notifications` 사용. 알림 ID 충돌 방지를 위해 분리:

| ID | 종류 | 트리거 | payload |
|---|---|---|---|
| 0~59 | 메모 리마인드 | 하루 3회(9시/15시/20시) × 20일 = 60슬롯 | note_id (숫자) |
| 996 | 자정 플래너 | 매일 00:00 (`matchDateTimeComponents.time`) | `"planner"` |
| 997 | 90분 nudge | 완료 후 90분 (활성 시간대만) | `"nudge"` |
| 998 | 타이머 진행 배너 | 타이머 켜져있는 동안 ongoing | (없음) |

**타이머 배너**: low importance · silent · ongoing · 30초마다 재게시
(스와이프로 지워도 자동 복귀). 진행 중일 땐 nudge 스킵 (지금 일하는 중).

**리마인드 풀**: 7일 이상 된 노트 (`SupabaseService.readRemindPool`).
한 번의 cancelAll + 재예약은 비용 큼 — 앱이 열릴 때만 갱신 (`_scheduleIfNeeded`).

---

## 4. 사용법 코치마크 시스템 (showcaseview)

복잡해서 별도 섹션.

### 두 가지 트리거 경로
1. **첫 진입 1회** (자동): `HomeScreen._maybeStartCoach` / `TodoScreen._maybeStartCoach`.
   `*_coachmark_done` 플래그 prefs에 저장. 한 번 띄우면 끝.
2. **설정 → 도움말 → 사용법** (수동, 언제든): `TourTrigger.start(kind, fromSettings: true)`.

### 글로벌 트리거 (`lib/utils/tour.dart`)
- `TourTrigger.notifier`: `ValueNotifier<TourRequest?>`.
- HomeScreen/TodoScreen이 각각 listener 등록.
- 처리 직후 `notifier.value = null`로 리셋 — **이거 안 하면 모드 토글마다
  투어가 재발사됨** (TodoScreen이 다시 마운트되면서 postFrame 체크가 옛 값을 봄).

### onBarrierClick 함정
`buildCoachMark` 헬퍼는 **반드시 `Builder`로 감쌈**. 이유:
- `ShowCaseWidget.of(context)`는 ancestor lookup.
- HomeScreen State의 context는 ShowCaseWidget *위*에 있어서 lookup 실패.
- Builder를 끼우면 inner ctx가 ShowCaseWidget 아래에 위치 → lookup 성공.
- 이 함정 한 번 밟았었음. 이유 주석에 적어둠.

### 메모↔투두 전환 시 코치마크
설정에서 "투두 사용법" 누른 경우:
- `TourTrigger.start('todo', fromSettings: true)`
- HomeScreen 리스너: `setState(_mode = _AppMode.todos)`
- TodoScreen 새로 마운트, initState의 postFrame 체크 → 현재 트리거 발견 → 처리
- **단, `_load()`가 비동기라 처음엔 `_selTodos`가 비어있어 `_timerKey` 누락 가능**
- 보류 로직(`_pendingTour`)으로 `_load` 끝나면 재시도

### 뒤로가기 시 설정 복귀
- HomeScreen이 `PopScope(canPop: !_tourActive)`로 가로채기
- `_tourFromSettings`면 설정 화면 다시 push
- `ShowCaseWidget.onFinish` + `onDismiss`에 `_tourActive = false`

---

## 5. 분석 (PostHog)

`lib/services/analytics_service.dart` — HTTP 직접.

### 식별 흐름
- 미로그인: 익명 ID (32자 hex) — SharedPreferences에 저장
- 로그인 직후: `identify(user.id)` 호출 → distinct_id를 Supabase auth UUID로 교체 + `$identify` 이벤트에 `$anon_distinct_id` 함께 전송 (PostHog가 두 ID 코호트 병합)
- 로그아웃: 새 익명 ID 발급 (`reset()`)

### 추적 이벤트 6 + 1
| 이벤트 | 발화 지점 |
|---|---|
| `sign_up` | auth_screen 가입 성공 직후 (인증 메일 전이라도) |
| `onboarding_completed` | onboarding_screen 마지막 "시작하기" |
| `app_open` (+ `source`) | main.dart 콜드스타트 + HomeScreen `didChangeAppLifecycleState.resumed` |
| `note_created` | category_detail_screen `_submit` 성공 |
| `todo_created` | todo_screen `_addTodo` 성공 |
| `planner_shared` | planner_screen `_exportImage` Share 성공 |
| `ai_classify_used` (+ `success`/`notes_count`) | home_screen `_autoClassify` |

### PII 절대 보내지 말 것
- distinct_id는 **Supabase user UUID**만. 이메일 X.
- 노트/투두 내용 X.

---

## 6. 빌드 / 배포

### 디버그 빌드 (개발 중)
```
flutter run -d <device-id>
```
Hot reload (`r`) · Hot restart (`R`) · Quit (`q`).

### 릴리스 빌드 + 자동 푸시
```
./build_release.sh
```
1. `flutter build apk --release`
2. `noting-v{VERSION}.apk`로 rename
3. (rclone 있으면) Google Drive `gdrive:Apps/Noting/releases/`에 업로드
4. `git add -A && git commit -m "v{VERSION} - 릴리즈 빌드" && git push origin main`
   (변경 없으면 push 스킵)

### Play Store (예정, 아직 미진행)
- APK 50.7MB → **App Bundle (.aab)** 로 전환 권장:
  `flutter build appbundle --release`
- 사용자 폰 맞춰 분할 다운로드 → 실제 설치 크기 ~17MB.
- 서명 키스토어 필요 (`android/key.properties` + JKS 파일, gitignore 추가 필요).
- 현재는 디버그 서명 (`signingConfig signingConfigs.debug`).

---

## 7. 데이터베이스 운영

### 정본
`supabase_schema.sql`. 변경 시 이 파일을 먼저 수정하고 Supabase SQL Editor에서
실행 (`drop policy if exists` + `create policy` 패턴이라 멱등).

### 자주 쓰는 운영 쿼리

```sql
-- 사용자별 활동 요약
select u.email,
  (select count(*) from noting_notes where user_id=u.id) as notes,
  (select count(*) from noting_todos where user_id=u.id) as todos,
  (select count(*) from noting_time_records where user_id=u.id) as timers,
  (select count(*) from noting_categories where user_id=u.id) as cats
from auth.users u order by notes desc;

-- AI 호출 추세 (rate limit 체크)
select user_id, date_trunc('day', created_at) as day, count(*)
from noting_ai_calls
where created_at > now() - interval '7 days'
group by user_id, day
order by day desc;
```

### 마이그레이션 절차
1. `supabase_schema.sql`에 추가
2. Supabase SQL Editor → New Query → 붙여넣고 Run
3. RLS 정책 무경고 확인
4. 커밋

---

## 8. 친구·테스트 계정 메모

- **0921sean@gmail.com**: 본인 메인. 삭제 차단 (서버+클라이언트).
- **jordan62872@gmail.com**: 친구. 가끔 사용. 옛 APK 들고 있을 수 있음.
- **0921sean+test@gmail.com 등 alias**: Gmail+ alias로 테스트 가입 자주 함.
- **0921sean@yonsei.ac.kr**: 학교 메일. 카테고리 사고 때 테스트로 썼었음.

---

## 9. 자주 까먹는 디테일들

- **세로 고정**: `main.dart`에서 `SystemChrome.setPreferredOrientations([portraitUp])`.
- **카테고리 색**: 위치 인덱스 기반 8색 팔레트 (`CategoryService.palette`).
  순서 바꾸면 색도 따라 바뀜 — 의도된 동작.
- **플래너 색**: 별도 12색 파스텔 (`planner_colors.dart`).
- **플래너 시간표 알고리즘**: 10분 셀 해상도. 각 셀의 주인 = "그 셀을
  제일 오래 차지한 작업". 안 겹치면 다 채우고, 겹치면 한 색만 → 시각적
  겹침 없음. `planner_screen.dart`의 `cellOwner` 함수.
- **편집 자동 저장**: 투두 텍스트 인라인 편집 중 외부 탭하면 자동 저장
  (날아가지 않음). 명시 저장은 ✓ 버튼.
- **타이머 다중 세션**: 한 투두에 여러 TimeRecord 가능. 동시 진행도 가능.
- **회상 카드**: 매 진입마다 랜덤 셔플. 직전과 다른 메모 뽑으려고 4번
  시도.

---

## 10. 추가 자료

- `DESIGN.md`: 컬러/타이포 시스템
- `pubspec.yaml`: 의존성 목록 + 버전
- 기억 폴더 (다음 세션에서 자동 로드):
  `~/.claude/projects/-Users-hazelnut-Desktop-CSB-MyApps-Noting/memory/`
  - `commit-workflow.md`
  - `mac-mini-dev-env.md` ← fvm(3.19.6)/JDK17 빌드 환경
  - `build-uploads-to-drive.md` ← 빌드 시 Drive 업로드
