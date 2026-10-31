# PROGRESS — Noting (살아있는 진행상황)

> **매 세션 프로토콜:** 시작 시 이 파일을 먼저 읽고, 끝에 갱신한다.
> (CLAUDE.md = *고정 지침* / 이 파일 = *매 세션 바뀌는 진행상황·다음 할 일*)
> `claude -p` 는 스테이트리스라, 이 파일이 세션 간 기억이다.
> updated: 2026-11-01 (버전체계 복구 v5.2.0 + 릴리스 서명키 도입 + 비동기 경합 Epic #23 착수)

## 지금 방향 (2026-07-13 결정)
- 에러 다수 해결 중 → 해결 후 **메모 기능과 분리해 '플래너 전용 앱'으로 출시** 계획.
- 가능하면 **"개인별 개인비서가 붙은 느낌"** 지향 (단 MVP 뒤 레이어 — 출시 전제로 걸지 말 것).
- 상세 OKR·오케 코멘트: 워크스페이스 `okr/noting.md` 참조.

## 진행 중 / 다음 할 일 (우선순위)
- [ ] **비동기 경합 방지 — Epic #23 남은 Task** ← 지금 진행 중. todo_screen은 끝(PR #24·#25). 남은 건:
  - home_screen 카테고리 추가/재정렬/삭제 가드 + `_loadAll` stale-guard (재정렬은 전체 삭제→재삽입이라 2회 겹치면 **카테고리 소실 가능**)
  - note_detail 삭제 ↔ 자동저장 교차 (`onPopInvoked`가 방금 삭제한 노트에 update를 날림)
  - settings `_signOut` 연타 가드
  - 올바른 패턴 레퍼런스: `auth_screen.dart`(버튼 비활성+스피너) / `planner_screen.dart:38`(조기 반환) / `settings_screen.dart`(전체 오버레이)
- [ ] **밀린 할 일 '이동' 실기기 검증** — 코드·빌드·설치는 됐으나 버튼을 실제로 눌러본 적 없음(실데이터 날짜를 바꾸는 동작이라 보류). 전날에서 빠지는지 + 시간기록 있는 건 원본 유지되는지 확인.
- [ ] **출시를 막는(blocking) 에러들 해결** ← *구체 목록은 본인/#noting 채널이 채울 것* (지금 미기재)
- [ ] **Flutter 3.19.6 → 최신 업그레이드 (이슈 #10)** — Android 툴체인(AGP/Gradle/Kotlin/Java/compileSdk) 동반 상향 필요. 지금은 Apple Silicon에서 릴리스 빌드에 Rosetta 필요한 상태. 별건 브랜치로 진행.
- [ ] 메모 ↔ 플래너 분리 설계
- [ ] 개인정보처리방침 + 이용약관 (Play Store 필수)
- [ ] APK → AAB 전환
- [ ] (뒤 레이어) "개인비서 붙은 느낌" 기능

## 개발 환경 메모 (하마) — 2026-11-01 갱신
- ⚠️ **릴리스 서명 키 필수.** `android/app/upload-keystore.jks` + `android/key.properties`가 없으면 릴리스 빌드가 *실패*한다(의도된 동작 — 예전엔 조용히 디버그 키로 서명됐다). gitignore라 레포엔 없음. 백업: `~/Desktop/CSB/MyApps/Noting-password/`. **백업할 때 '이동'하지 말고 '복사'할 것** — 실제로 옮겨서 빌드가 깨진 적 있음. 백업이 원본과 같은 디스크라 다른 매체에도 하나 더 두는 게 좋다.
- **서명 지문**: `282d14b7c684f23deb8cfe025af4ad80ad1ac385e0c9e693b0a152e71a81de22`. 확인: `apksigner verify --print-certs <apk>` (`CN=Android Debug`가 나오면 잘못된 빌드).
- **apksigner/keytool엔 JAVA_HOME 필요** — `export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home` (시스템 PATH에 java 없음).
- 이 맥(hazelnut, Apple Silicon)에서 **릴리스 빌드에 Rosetta 필요** (Flutter 3.19.6의 gen_snapshot이 darwin-x64). 설치 완료됨. 근본 해결은 이슈 #10(Flutter 업그레이드).
- `adb`는 PATH에 없음 → `~/Library/Android/sdk/platform-tools/adb` 직접 사용.
- **6월 이전 APK를 쓰던 기기는 1회 제거 후 설치 필요** (디버그 키 → 릴리스 키 전환으로 서명 불일치). 그 이후로는 덮어쓰기 업데이트 정상 — S24에서 확인함.
- 실기기 설치 시 폰 Play Protect가 `INSTALL_FAILED_VERIFICATION_FAILURE`로 막음 → 폰에서 "무시하고 설치" 눌러 통과. (adb로 verifier 끄는 건 지양)
- 폰: Galaxy S24 Ultra(SM-S928N), 패키지 `com.csb.noting`.

## 안정 완료된 것 (요약 — 상세는 CLAUDE.md '현재 상태')
- 가입/로그인/인증/계정삭제, PostHog 6이벤트, AI 자동분류(Edge Function), 다기기 동기화, 사용법 가이드.

## 최근 세션 로그 (최신이 위)
- **2026-11-01** — 배포 정비 + 비동기 경합 Epic 착수 (PR #20/#22/#24/#25 머지, Closes #19/#21, Epic #23 진행중).
  - **버전 체계 복구 (#19)**: pubspec이 5/21부터 `1.0.0+1`에 멈춰 있었고, `build_release.sh`의 자동 push가 그 값을 읽어 커밋 메시지를 생성한 탓에 5~9월 커밋이 전부 `v1.0.0 -`으로 찍혀 있었다. 전체 이력을 semver로 재구성 — 대개편마다 MAJOR(v2 Supabase 전환 / v3 이메일인증·계정체계 / v4 카테고리 클라우드 마이그레이션 / v5 하단 네비 전환) → **`5.2.0+14`**. 배포 파일명 `Noting-v{버전}.apk`로 통일. 스크립트의 `git push origin main` 자동 실행 제거(절대 규칙 위반 + 이 혼선의 원인).
  - **릴리스 서명 키 (#21)**: 릴리스가 `signingConfigs.debug`로 서명되고 있었다 → Play Store 거부 사유이자, **머신마다 키가 달라져** 맥북→맥미니 이동 후 기존 사용자가 업데이트를 설치할 수 없었다(`INSTALL_FAILED_UPDATE_INCOMPATIBLE` 실제 발생). 전용 keystore + `key.properties`로 전환, 키 없으면 빌드가 실패하게 둠.
  - **비동기 경합 Epic #23 착수**: "가져오기 중 날짜 넘기면 엉뚱한 날짜로 간다" 제보에서 출발 → 조사해보니 복사의 날짜 지정은 이미 정확했고(제보는 6월 빌드 기준), **무방비 async 핸들러가 전 화면에 20개+** 있는 게 진짜 문제였다. todo_screen부터 수정(PR #24): 타이머 ▶ 연타로 생기던 **고아 TimeRecord**(가드가 await 뒤에 설정돼 무효였음), 체크박스↔텍스트 저장 **상호 덮어쓰기**(둘 다 pre-await 스냅샷으로 copyWith → 앱 재시작까지 UI≠DB), 복사 연타 중복, **화살표 280ms 창**(애니메이션 끝나야 `_selectedDate` 갱신 → 그 사이 작업이 이전 날짜로), 페이저 스와이프 시 시간기록 stale. 버튼 비활성화+스피너+실패 스낵바 도입.
  - **밀린 할 일 이동화 (PR #25)**: 복사 → **이동**(전날에서 빠짐). 단 시간 기록이 달린 건 복사(원본 유지) — 기록은 자체 날짜가 없고 `todo.date`를 따라가서, 옮기면 어제 플래너의 시간 블록이 사라지고 오늘 안 한 블록이 생긴다.
  - 친구(jordan62872@gmail.com)에게 `Noting-v5.2.0.apk` 전달(카톡). ⚠️ **#25 이전 빌드라 이동 기능은 미포함** — 다시 보내려면 재빌드 필요.
- **2026-09-06** — 투두 3건 + 문서 (PR #13/#15/#17 머지, Closes #12/#14/#16). (1) **fix #12**: 새 할일 추가·'가져오기'가 `await`(DB 생성) 뒤 `setState`에서 `_selKey`를 다시 읽어, 생성 중 페이지 넘기면 넘긴 날짜에 잘못 삽입되던 문제 → 시작 시점 날짜키를 `targetKey`로 고정. (2) **feat #14**: '어제 가져오기'를 **선택 날짜 이전의 모든 미완료 전체 가져오기**로 확장 — 텍스트 기준 중복 제거 + 이미 오늘 목록에 있는 건 제외. 문구 '밀린 할 일 가져오기'로 변경. (3) **docs #16**: CONVENTION.md에 자매 레포 InvestChatBots 정합 — '커밋 쪼개기 기준' + '이슈 남발 자제' 보강(Invest 전용은 제외). 원본(과거 미완료)은 그대로 두는 복사 방식 유지(이동 아님). ⚠️ 실기기 검증은 아직 — 다음 세션에 S24 릴리스 설치로 체감 확인 권장.
- **2026-08-06** — perf: 투두 체감 속도 개선 (PR #9 머지, Closes #8). (1) '어제 미완료 복사'가 루프에서 하나씩 await createTodo(왕복 2N회) → `createTodosBatch`(order 조회 1 + 다중행 insert 1 = 2회)로 축소, setState 1회. (2) 시간기록을 날짜별 캐시(`_recordsByDate`)로 — 방문한 날짜 재방문 시 대기 0, 네트워크는 백그라운드 갱신. DB 인덱스는 이미 적절, 병목은 왕복 횟수/캐싱이었음. 실기기(S24) 릴리스 설치로 체감 확인 완료. + Flutter 업그레이드는 이슈 #10으로 분리.
- **2026-07-17** — fix: 투두 스와이프 삭제 후 드래그 시 뜨던 'A dismissed Dismissible widget is still part of the tree' 에러 수정. 원인은 `_deleteTodo`가 Supabase 삭제(await)를 먼저 하고 로컬 리스트 제거를 나중에 해서, 네트워크 대기 중 리빌드가 나면 dismiss된 위젯이 트리에 남던 것. 로컬 제거+setState를 먼저(낙관적) → Supabase 삭제를 뒤로 재배치. (todo_screen.dart만 수정)
- 2026-07-17 — 오케스트레이션 파이프라인 검증(claude -p 루프 정상 동작 확인).
- **2026-07-17** — (Agent Orchestration 셋업) PROGRESS.md 도입 + CLAUDE.md에 세션 프로토콜 추가. 코드 변경 없음.
