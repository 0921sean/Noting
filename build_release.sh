#!/bin/bash
# Noting 릴리즈 빌드 + Google Drive 업로드
# 사용법: ./build_release.sh

set -e
cd "$(dirname "$0")"

# 버전 읽기
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
APK_NAME="noting-v${VERSION}.apk"
APK_BUILD="build/app/outputs/flutter-apk/app-release.apk"
APK_SRC="build/app/outputs/flutter-apk/${APK_NAME}"

echo "🔨 빌드 시작 — noting v${VERSION}"
flutter build apk --release

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
