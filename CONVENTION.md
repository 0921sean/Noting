# Git / 개발 컨벤션 (솔로·소규모)

> **본질 = 추적성.** 모든 코드 변경이 "어떤 목표에서 왔는지" 이슈로 이어지게 한다.
> 이 문서는 프로젝트 무관 **범용 버전** — 다른 레포에 그대로 붙여도 된다.
> 프로젝트별 안전장치/빌드 규칙은 각 레포의 `CLAUDE.md`가 우선한다.

## 1. 작업 단위 — Epic · Task · 단발 (하이브리드)

| | 언제 | 이슈 | PR |
| --- | --- | --- | --- |
| **Epic** | 함께 가는 몇 개 작업의 응집 묶음 | `[Epic] #N - 주제` + **투두 체크리스트** 본문 | 없음 (아래 Task들이 채움) |
| **Task** | Epic의 투두 하나 | ❌ **안 만듦** | `[Type] #N - 내용`(에픽번호) · 본문 `Part of #N` |
| **단발** | Epic 밖 독립 작업(버그 하나 등) | `[Type] #K` | `[Type] #K - 내용` · 본문 `Closes #K`(자동종료) |

**핵심 규칙**
- **Task는 이슈를 새로 안 만든다.** 이슈는 Epic 하나뿐. (안 그러면 이슈=PR 1:1 중복 폭발)
- **Epic = 하나의 응집 묶음.** 수십 개를 무한정 안고 가지 말 것. 테마가 바뀌면 옛 Epic에 얹지 말고 **새 Epic**을 판다(예: "빌드" Epic ≠ "UX 개편" Epic). 비대해지면 쪼갠다.
- **`Closes`는 단발 전용**(자기 이슈 자동종료). Task는 **`Part of #N`만** — Epic 체크리스트로 추적, Epic은 마지막에 **수동 종료**.

## 2. 번호·브랜치·커밋 규칙

| 위치 | Task (에픽 하위) | 단발 |
| --- | --- | --- |
| 브랜치 | `type/슬러그` (예: `feat/q-exec`) | `type/#K` |
| 커밋 | `[Type/#N] 내용` (에픽번호) | `[Type/#K] 내용` |
| PR 제목 | `[Type] #N - 내용` | `[Type] #K - 내용` |
| PR 본문 | `Part of #N` (Closes 안 씀) | `Closes #K` (자동종료) |

- **Type**: `Epic` / `Feat` / `Fix` / `Hotfix` / `Refactor` / `Design` / `Setting` / `Docs` / `Test` / `Chore`
- 이슈 제목은 생성 후 부여된 번호를 확인해 `#번호`를 끼워 넣는다.
- PR 자신의 번호는 GitHub이 이슈와 공유 카운터로 따로 매기므로 제목의 번호(이슈번호)와 **다른 게 정상**(예: 이슈 #7 → PR #8).
- 한 브랜치의 전 커밋은 **같은 `#번호`**, Type만 바뀔 수 있다.
- 한국어 설명 OK. ❌ `update`·`wip`·`작업함`·빈 커밋 금지.

## 3. 절대 규칙 (라이브 안전장치)

- **`main` 직접 커밋·푸시 금지.** 작업은 브랜치 → PR → diff 셀프리뷰 → CI 통과 → 머지.
- **머지는 항상 사람이 명시적 승인.** CI가 초록이어도 자동머지 금지. (승인은 **PR별** — 한 PR의 OK가 다음으로 안 이어짐)
- **의미 단위마다 커밋.** 기능1 / 버그1 / 리팩터1 = 커밋1. 세션 전체를 한 커밋으로 뭉치지 않기.
- **위험/라이브 변경은 기능 플래그 뒤에.** 기본 **off**로 머지 → 켜는 건 별도 승인(예: `FEATURE_X_ENABLED`). 하드코딩보다 되돌리기 쉽고 라이브에 안전.
- **커밋 금지 대상**: `.db`, `.session`, `.env` 등 시크릿 — 커밋 전 `.gitignore` 확인.
- **라이브 긴급 상황의 Hotfix만 `main` 예외** — 사후에 이슈로 기록.

## 4. 세션 리듬

- **시작**: `git fetch`로 origin 관계 먼저 확인 → **새 커밋 있을 때만** `pull`.
- **작업 중**: 검증(테스트 + 실행 확인/스크린샷) **후** 커밋. Epic 체크리스트·진행상황 문서 갱신.
- **끝**: 남은 변경 전부 커밋·`push`. 마지막에 "이번 세션에 한 일" 1~2줄 요약.

## 5. 실전 흐름

1. 큰 테마 시작 → **Epic 이슈**(`[Epic] #N` + 투두 체크리스트).
2. 투두 하나 = `type/슬러그` 브랜치.
3. 작게 커밋(`[Type/#N]`) → push (여러 커밋 OK).
4. **PR → `main`**, 본문 `Part of #N` + 셀프리뷰.
5. 검증(테스트·실행·스크린샷) → **사람이 머지**.
6. 머지 시 Epic 투두 `[x]` 체크 → 다 끝나면 **Epic 수동 종료**.

> 단발은 위에서 Epic 이슈 대신 `[Type] #K` 이슈 하나 + PR 본문 `Closes #K`로 자동종료.

## 6. 라벨 (repo 1회, `gh` 로그인 후 실행)

> 타입 라벨만 사용(솔로라 담당자 라벨 제외). 라벨명 = `이름 이모지`, 커밋 Type = `[이름]`.

```bash
gh label create "Epic 🗂️"    --color 0E4B99 --description "여러 Task를 묶는 상위 목표(체크리스트)" --force
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

## 7. CI · 자동화

`.github/workflows/`:
- **ci.yml** — PR·main push마다 lint + 오프라인 안전 테스트. (네트워크/시크릿 필요한 통합 테스트는 별도 워크플로우로 분리)
- **pr-label.yml** — PR 제목 `[Type]` → 타입 라벨 자동 부여.
- **issue-label.yml** — 이슈 제목 `[Type]`(Epic 포함) → 타입 라벨 자동 부여. ⚠️ `issues` 트리거는 default 브랜치 버전만 도므로 **main 머지 후 활성화**.
- **pr-title-lint.yml** — PR 제목이 `[Type] #번호 - 내용`이 아니면 실패(머지 게이트).

repo 설정:
- **머지 후 작업 브랜치 자동 삭제** ON (`delete_branch_on_merge`).
- 단발 PR 본문 `Closes #K` → 머지 시 이슈 자동 종료. (Task의 `Part of #N`은 자동종료 안 됨 — 의도된 동작)

## 한 줄 요약

> 큰 테마 하나 = **Epic 이슈 하나**(투두 체크리스트), 그 아래 각 작업 = **이슈 없는 PR**(`Part of #N`). 테마 바뀌면 **새 Epic**. 독립 작업은 **단발**(`Closes #K`). `main`은 항상 **브랜치 → PR → 사람 승인**.
