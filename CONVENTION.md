# Git / 개발 컨벤션 (솔로)

> 블록깨비 팀 컨벤션(Offroad 스타일)의 솔로 버전. **본질 = 모든 작업을 이슈에서 시작해 같은 `#번호`로 끝까지(브랜치·커밋·PR) 끌고 가는 추적성.**
> 절대 규칙(머지 셀프 게이트 등)은 [CLAUDE.md](CLAUDE.md) 참조 — 컨벤션보다 우선한다.

## 4곳 `#번호` 포맷

| 위치 | 포맷 | 예 |
| --- | --- | --- |
| 이슈 제목 | `[Type] #번호 - 내용` | `[Feat] #12 - 랜덤 회상 알림 스케줄러` |
| 브랜치 | `type/#번호` | `feat/#12` |
| 커밋 | `[Type/#번호] 내용` | `[Feat/#12] 회상 알림 자정 스케줄 등록` |
| PR 제목 | `[Type] #번호 - 내용` + 본문 `Resolved: #번호` | `[Feat] #12 - 랜덤 회상 알림 스케줄러` |

- **4곳의 `#번호`는 전부 "이슈 번호"다.** PR 자신의 번호는 GitHub이 이슈와 공유 카운터로 따로 매기므로 이슈 번호와 다른 게 정상이다(예: 이슈 `#7` → 그 PR은 `#8`). 제목·브랜치·커밋엔 언제나 **이슈** 번호를 쓴다.
- 이슈 제목은 생성 후 부여된 번호를 확인해 `#번호`를 끼워 넣는다.
- 한 브랜치의 전 커밋은 **같은 `#번호`**, Type만 바뀔 수 있다(예: 구현 `[Feat/#12]` → 리팩터 `[Refactor/#12]`).
- 한국어 설명 OK. ❌ `update`·`wip`·`작업함` 같은 무의미 메시지·빈 커밋 금지(히스토리는 채용 때 평가된다).

## Type

`Feat`(새 기능) / `Fix`(버그) / `Hotfix`(긴급 수정) / `Refactor` / `Design`(UI·스타일) / `Setting`(설정·빌드·CI) / `Docs` / `Test` / `Chore`(잡일)

## 브랜치 전략

- `main` = 안정 브랜치. **직접 커밋·푸시 금지.**
- 작업은 `type/#번호` 브랜치 → PR → diff 셀프 리뷰 → CI 통과 → main 머지.
- 긴급 상황의 **Hotfix만 예외**(사후에 이슈로 기록).
- 작업 단위 = **이슈1 → 브랜치1 → 커밋 여러 개 → PR1 → 머지 → 이슈 종료.**

## 개발 순서

1. 할 일을 **이슈**로 등록 → (생성 후) 제목에 `#번호` 끼워넣기. 타입 라벨은 제목 `[Type]`으로 자동 부여됨.
2. 이슈 → `type/#번호` 브랜치 생성.
3. 커밋 `[Type/#번호] 내용` → push.
4. PR: 작업 브랜치 → `main`. 템플릿 작성 + 본문에 `Resolved: #번호`.
5. **셀프 리뷰**(diff 훑기) + CI 통과 확인. 수정은 같은 브랜치에 커밋 추가.
6. 머지 → `Resolved: #번호`로 이슈 자동 종료.

## 라벨 (repo 1회, `gh` 로그인 후 실행)

> 타입 라벨만 사용(솔로라 담당자 라벨 제외). 라벨명은 `이름 이모지`, 커밋 Type은 `[이름]`.

```bash
gh label create "Feat 💻"     --color 0E8A16 --description "새 기능" --force
gh label create "Fix 🐛"      --color D93F0B --description "버그 수정" --force
gh label create "Hotfix 🚨"   --color B60205 --description "긴급 수정" --force
gh label create "Refactor ♻️" --color 5319E7 --description "리팩터링" --force
gh label create "Design 🎨"   --color D4C5F9 --description "UI·스타일" --force
gh label create "Setting ⚙️"  --color 555555 --description "설정·빌드" --force
gh label create "Docs 📝"     --color 0075CA --description "문서" --force
gh label create "Test 🧪"     --color C2E0C6 --description "테스트" --force
gh label create "Chore 🧹"    --color CFD3D7 --description "잡일" --force
```

- ⚠️ 솔로는 여기까지만. 라벨 체계 과하게 늘리지 말 것.

## CI · 자동화

`.github/workflows/`:
- **ci.yml** — PR·main push마다 `flutter analyze`(정적 분석) + 오프라인 안전 테스트(`test/regression_test.dart`, `test/widget_test.dart`). Flutter는 FVM과 동일한 **3.19.6** 핀. `lib/config.dart`(gitignore)는 CI에서 placeholder로 생성해 컴파일만 통과시킴 — 실제 시크릿 없음. Supabase/PostHog/Anthropic를 실제로 때리는 통합 테스트는 CI에서 제외(추후 secrets 붙인 별도 워크플로우로).
- **pr-label.yml** — PR 제목 `[Type]` → 타입 라벨 자동 부여.
- **issue-label.yml** — 이슈 제목 `[Type]` → 타입 라벨 자동 부여(템플릿 안 거친 CLI·빈 이슈까지). ⚠️ `issues` 트리거는 **default 브랜치(main)** 버전만 도므로, 이 워크플로우는 **main 머지 후에야** 활성화된다.
- **pr-title-lint.yml** — PR 제목이 `[Type] #번호 - 내용` 형식이 아니면 실패(머지 게이트).

repo 설정:
- **머지 후 작업 브랜치 자동 삭제** ON (`delete_branch_on_merge`). 브랜치 목록이 안 쌓인다.
- PR 본문 `Resolved: #번호` → 머지 시 이슈 자동 종료.
