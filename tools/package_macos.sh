#!/bin/bash
# ASC Toolkit (Flutter macOS)을 배포용 서명 .dmg로 패키징.
# 사용: ./tools/package_macos.sh
# 결과물: ./ASC-Toolkit-<version>-macos.dmg
#
# 흐름: flutter build macos --release
#       → inside-out 코드 서명(내포 프레임워크 먼저 → 호스트 앱)
#       → 서명 dmg 생성
#
# 서명 우선순위:
#   1) Developer ID Application — 배포용. 다운로드 dmg의 Gatekeeper "손상됨/미확인 개발자"
#      하드블록 제거(공증 전이라 최초 1회 우클릭→열기만). hardened runtime + secure timestamp.
#      모든 내포 코드를 같은 팀 ID로 서명 → 라이브러리 검증(hardened runtime) 충족.
#   2) ad-hoc — cert 없을 때. hardened runtime 생략(ad-hoc+runtime은 실행 문제 소지).
# 식별자는 repo에 하드코딩하지 않고 로컬 키체인에서 자동 탐지만 한다.
# (이 앱은 Sandbox OFF + 파일 기반 저장이라 서명은 배포·무결성용.)

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ASC Toolkit"
ENTITLEMENTS="macos/Runner/Release.entitlements"

echo "▶ flutter build macos --release"
flutter build macos --release

APP="build/macos/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP" ]; then
    echo "✗ 빌드 실패: $APP 없음" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application:" \
    | head -1 \
    | awk -F'"' '{print $2}' || true)

if [ -n "$IDENTITY" ]; then
    echo "▶ Signing (Developer ID): $IDENTITY"
    # 1) 내포 dylib (있으면) 먼저
    while IFS= read -r dylib; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$dylib"
    done < <(find "$APP/Contents" -name "*.dylib" 2>/dev/null)
    # 2) 프레임워크 (entitlements 없음)
    for fw in "$APP"/Contents/Frameworks/*.framework; do
        [ -e "$fw" ] || continue
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$fw"
    done
    # 3) 호스트 앱 마지막 (entitlements 포함)
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
    echo "▶ Verifying…"
    codesign --verify --strict --deep --verbose=2 "$APP"
else
    echo "▶ Developer ID 인증서 없음 → ad-hoc 서명 (hardened runtime 생략)"
    codesign --force --deep --sign - "$APP"
fi

# ---- dmg 패키징 ----
DMG="ASC-Toolkit-${VERSION}-macos.dmg"
echo "▶ Packaging → $DMG"
rm -f "$DMG"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
# ditto로 복사해 내포 코드 서명 메타데이터 보존.
ditto "$APP" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"

if [ -n "$IDENTITY" ]; then
    echo "▶ Signing dmg with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    codesign --verify --verbose=2 "$DMG"
fi

echo "✅ Built: $(pwd)/$DMG"
echo ""
echo "배포: gh release upload v${VERSION} \"$DMG\""
