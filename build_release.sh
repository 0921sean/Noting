#!/bin/bash
# Noting 릴리즈 빌드 + Google Drive 업로드
# 사용법: ./build_release.sh

set -e
cd "$(dirname "$0")"

# 버전 읽기
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
# 배포 파일명 규칙: Noting-v{major.minor.patch}.apk
# pubspec의 version을 그대로 따르니, 릴리스마다 pubspec을 먼저 bump해야 한다.
APK_NAME="Noting-v${VERSION}.apk"
APK_BUILD="build/app/outputs/flutter-apk/app-release.apk"
APK_SRC="build/app/outputs/flutter-apk/${APK_NAME}"

echo "🔨 빌드 시작 — noting v${VERSION}"
# 머신마다 Flutter 버전이 달라서 fvm로 고정 — fvm 있으면 그걸 통해 빌드
FLUTTER=$(command -v fvm >/dev/null 2>&1 && echo "fvm flutter" || echo "flutter")
# arm64 전용으로 빌드 — 기본(3종 포함) 51MB → 19MB.
# x86_64는 에뮬레이터용이고 armeabi-v7a는 2015년 이전 구형폰용이라,
# 카톡/드라이브로 직접 건네는 APK엔 둘 다 필요 없다.
# ⚠️ Play Store용은 AAB로 올릴 것 — 구글이 기기별로 쪼개 보내므로
#    구형폰 지원을 유지하면서도 설치 용량이 작아진다.
$FLUTTER build apk --release --target-platform android-arm64

# 빌드된 파일 이름 변경
cp "${APK_BUILD}" "${APK_SRC}"
echo "✅ 빌드 완료: ${APK_NAME}"

# Google Drive 업로드 (rclone 설정 필요)
if command -v rclone &>/dev/null && rclone listremotes | grep -q "gdrive:"; then
    DRIVE_DIR="gdrive:Apps/Noting/releases"
    echo "☁️  Google Drive 업로드 중..."
    rclone copy "${APK_SRC}" "${DRIVE_DIR}/" --progress
    echo "✅ 업로드 완료: ${DRIVE_DIR}/${APK_NAME}"
else
    echo "⚠️  rclone 미설정 — Finder에서 파일 열기"
    open "$(dirname "${APK_SRC}")"
fi

echo "🎉 완료!"

# ⚠️ 자동 git commit/push는 일부러 넣지 않는다.
# 예전엔 여기서 `git add -A && git commit -m "v${VERSION} - 릴리즈 빌드" && git push origin main`을
# 돌렸는데, (1) CLAUDE.md 절대 규칙인 "main 직접 커밋·푸시 금지"를 위반하고
# (2) 커밋 메시지가 컨벤션(`[Type/#번호] 내용`) 밖이며
# (3) pubspec을 안 올린 채 돌려서 2026-05-21~09월 커밋이 전부 `v1.0.0 -`으로 찍히는
# 버전 혼선을 만들었다. 변경사항은 브랜치 → PR로 올린다.
if [ -n "$(git status --porcelain)" ]; then
  echo "ℹ️  커밋 안 된 변경이 있습니다 — 브랜치 → PR로 올리세요 (main 직접 푸시 금지)."
fi
