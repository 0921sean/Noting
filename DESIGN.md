# Noting — Design System

> 개인 메모 + 일일 플래너 앱. 두 가지 시각 언어를 의도적으로 분리해 사용.

---

## 두 시각 언어

### 1. App UI (메모, 투두 리스트)
따뜻하고 차분한 earth tone. 기록하고 쌓아가는 감각.

- **Surface**: `#FAF7F2` (warm cream)
- **Primary**: `#7C5C3E` (warm brown)
- **On Surface**: `#2C1F14`
- **Secondary**: `#B5896A`
- **Error**: `#B85C38`
- **Divider**: `#E8DDD0`
- **Dark mode Surface**: `#1C1712`
- **Dark mode Primary**: `#C8956C`

### 2. Planner Mode (플래너 카드, 시간 기록 뱃지)
원본 Python hazel_nut_story.py의 COLOR_12 파스텔 팔레트. 인스타 스토리 감성.

```dart
kPlannerColors = [
  #FA7D7C  // 1: 분홍 (first todo)
  #F9AE7D  // 2: 주황
  #F7FC7F  // 3: 노랑
  #7DF97E  // 4: 초록
  #80E0FA  // 5: 하늘
  #7D7DFA  // 6: 보라
  #CA7CFA  // 7: 연보라
  #CD7D7E  // 8: 마젠타
  #C5967B  // 9: 갈색
  #CDCD7D  // 10: 올리브
  #7FCD7F  // 11: 연두
  #80BDCD  // 12: 청록
]
```

색상은 투두 리스트 순서(orderIndex)에 따라 자동 배정. 플래너 카드와 투두 리스트 색상 점이 동일 인덱스 사용.

**왜 두 언어인가?**
앱 UI는 집중과 편안함 → earth tone. 플래너 카드는 공유 목적의 시각적 결과물 → bright pastel. 의도적 분리.

---

## 타이포그래피

- **Font**: 시스템 폰트 (iOS: SF Pro, Android: Roboto)
- **Title (앱 이름)**: 26px, w700, `#2C1F14`
- **Section header**: 14px, w600
- **Body**: 15px, h1.45
- **Todo text**: 15px, h1.45
- **Caption (시간, 날짜)**: 10-12px
- **Planner date header**: 22px, w800, `#1A1A2E`
- **Planner checklist**: 10px, w600

---

## 간격

| 맥락 | 값 |
|------|-----|
| 화면 수평 패딩 | 20-24px |
| 섹션 간격 | 14-20px |
| 카드 내부 패딩 | 10-16px |
| 투두 아이템 수직 간격 | 10px |

---

## Border Radius

| 요소 | radius |
|------|--------|
| 메모 카드 / 다이얼로그 | 16px |
| 플래너 메인 카드 | 28px |
| 플래너 내부 카드 | 8-12px |
| 태그 / 뱃지 | 8-10px |
| 버튼 (pill) | 20px |

---

## 컴포넌트 가이드

### 투두 아이템
```
[drag_handle] [check_circle_22px] [▶/⏹_18px] [time_badge?] [text] [color_dot_8px]
```
- Check circle: 22px, done=primary color, undone=outlined
- Color dot: 8px, `kPlannerColors[index % 12]`
- Time badge: plannerColor.15 opacity bg, plannerColor text, 10px w600

### 플래너 카드
- Background: `#F0EFF8` (lavender)
- Aspect ratio: 9:16 (Instagram Story)
- Checklist: 12 slots max, done items show strikethrough
- Grid: 10분 단위, 1시간 = 6칸
- 시간 분할: 새벽(0-5) 좌하단, 낮(6-17) 우상단, 저녁(18-23) 우하단

### 모드 토글 (메모/투두)
- Height: 36px, radius: 20px
- Background: onSurface.06 opacity
- Selected tab: white card with shadow, w600
- Unselected: transparent, w400, onSurface.45

---

## 인터랙션 원칙

1. **진입 마찰 최소화** — 텍스트 입력 즉시 저장, 확인 창 없이
2. **타이머 탭 2번** — 시작(▶)/종료(⏹), TimePicker는 수동 수정용으로만
3. **플래너 공유** — 시스템 share sheet 직접 호출
4. **어제 복사** — 미완료 항목만 오늘로

---

## 아이콘 세트

- `Icons.drag_indicator_outlined` — drag handle
- `Icons.play_circle_outline` — timer start
- `Icons.stop_circle_outlined` — timer stop (planner color when active)
- `Icons.grid_view_rounded` — planner access
- `Icons.copy_outlined` — yesterday copy
- `Icons.ios_share_rounded` — export/share
- `Icons.check_box` / `Icons.check_box_outline_blank` — planner checklist
