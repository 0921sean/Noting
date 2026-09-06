# PROGRESS — Noting (살아있는 진행상황)

> **매 세션 프로토콜:** 시작 시 이 파일을 먼저 읽고, 끝에 갱신한다.
> (CLAUDE.md = *고정 지침* / 이 파일 = *매 세션 바뀌는 진행상황·다음 할 일*)
> `claude -p` 는 스테이트리스라, 이 파일이 세션 간 기억이다.
> updated: 2026-09-06 (투두 날짜전환 버그 fix + 밀린 할일 전체 가져오기 feat + CONVENTION 보강)

## 지금 방향 (2026-07-13 결정)
- 에러 다수 해결 중 → 해결 후 **메모 기능과 분리해 '플래너 전용 앱'으로 출시** 계획.
- 가능하면 **"개인별 개인비서가 붙은 느낌"** 지향 (단 MVP 뒤 레이어 — 출시 전제로 걸지 말 것).
- 상세 OKR·오케 코멘트: 워크스페이스 `okr/noting.md` 참조.

## 진행 중 / 다음 할 일 (우선순위)
- [ ] **출시를 막는(blocking) 에러들 해결** ← *구체 목록은 본인/#noting 채널이 채울 것* (지금 미기재)
- [ ] **Flutter 3.19.6 → 최신 업그레이드 (이슈 #10)** — Android 툴체인(AGP/Gradle/Kotlin/Java/compileSdk) 동반 상향 필요. 지금은 Apple Silicon에서 릴리스 빌드에 Rosetta 필요한 상태. 별건 브랜치로 진행.
- [ ] 메모 ↔ 플래너 분리 설계
- [ ] 개인정보처리방침 + 이용약관 (Play Store 필수)
- [ ] APK → AAB 전환
- [ ] (뒤 레이어) "개인비서 붙은 느낌" 기능

## 개발 환경 메모 (하마) — 2026-08-06
- 이 맥(hazelnut, Apple Silicon)에서 **릴리스 빌드에 Rosetta 필요** (Flutter 3.19.6의 gen_snapshot이 darwin-x64). 설치 완료됨. 근본 해결은 이슈 #10(Flutter 업그레이드).
- `adb`는 PATH에 없음 → `~/Library/Android/sdk/platform-tools/adb` 직접 사용.
- 실기기 설치 시 폰 Play Protect가 `INSTALL_FAILED_VERIFICATION_FAILURE`로 막음 → 폰에서 "무시하고 설치" 눌러 통과. (adb로 verifier 끄는 건 지양)
- 폰: Galaxy S24 Ultra(SM-S928N), 패키지 `com.csb.noting`.

## 안정 완료된 것 (요약 — 상세는 CLAUDE.md '현재 상태')
- 가입/로그인/인증/계정삭제, PostHog 6이벤트, AI 자동분류(Edge Function), 다기기 동기화, 사용법 가이드.

## 최근 세션 로그 (최신이 위)
- **2026-09-06** — 투두 3건 + 문서 (PR #13/#15/#17 머지, Closes #12/#14/#16). (1) **fix #12**: 새 할일 추가·'가져오기'가 `await`(DB 생성) 뒤 `setState`에서 `_selKey`를 다시 읽어, 생성 중 페이지 넘기면 넘긴 날짜에 잘못 삽입되던 문제 → 시작 시점 날짜키를 `targetKey`로 고정. (2) **feat #14**: '어제 가져오기'를 **선택 날짜 이전의 모든 미완료 전체 가져오기**로 확장 — 텍스트 기준 중복 제거 + 이미 오늘 목록에 있는 건 제외. 문구 '밀린 할 일 가져오기'로 변경. (3) **docs #16**: CONVENTION.md에 자매 레포 InvestChatBots 정합 — '커밋 쪼개기 기준' + '이슈 남발 자제' 보강(Invest 전용은 제외). 원본(과거 미완료)은 그대로 두는 복사 방식 유지(이동 아님). ⚠️ 실기기 검증은 아직 — 다음 세션에 S24 릴리스 설치로 체감 확인 권장.
- **2026-08-06** — perf: 투두 체감 속도 개선 (PR #9 머지, Closes #8). (1) '어제 미완료 복사'가 루프에서 하나씩 await createTodo(왕복 2N회) → `createTodosBatch`(order 조회 1 + 다중행 insert 1 = 2회)로 축소, setState 1회. (2) 시간기록을 날짜별 캐시(`_recordsByDate`)로 — 방문한 날짜 재방문 시 대기 0, 네트워크는 백그라운드 갱신. DB 인덱스는 이미 적절, 병목은 왕복 횟수/캐싱이었음. 실기기(S24) 릴리스 설치로 체감 확인 완료. + Flutter 업그레이드는 이슈 #10으로 분리.
- **2026-07-17** — fix: 투두 스와이프 삭제 후 드래그 시 뜨던 'A dismissed Dismissible widget is still part of the tree' 에러 수정. 원인은 `_deleteTodo`가 Supabase 삭제(await)를 먼저 하고 로컬 리스트 제거를 나중에 해서, 네트워크 대기 중 리빌드가 나면 dismiss된 위젯이 트리에 남던 것. 로컬 제거+setState를 먼저(낙관적) → Supabase 삭제를 뒤로 재배치. (todo_screen.dart만 수정)
- 2026-07-17 — 오케스트레이션 파이프라인 검증(claude -p 루프 정상 동작 확인).
- **2026-07-17** — (Agent Orchestration 셋업) PROGRESS.md 도입 + CLAUDE.md에 세션 프로토콜 추가. 코드 변경 없음.
