#!/bin/bash
# tools/app_icon/source.svg 를 수정한 뒤 이 스크립트를 실행하면
# macOS AppIcon.appiconset 의 7장 PNG 가 일관된 비율로 재생성된다.
#
# 의존성: rsvg-convert (brew install librsvg)
set -euo pipefail

cd "$(dirname "$0")"
SVG="source.svg"
OUT="../../macos/Runner/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "ERROR: rsvg-convert 가 없음. 'brew install librsvg' 로 설치하세요." >&2
  exit 1
fi

if [ ! -f "$SVG" ]; then
  echo "ERROR: $SVG 가 없음." >&2
  exit 1
fi

for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" "$SVG" -o "$OUT/app_icon_${size}.png"
done

echo "✓ Regenerated 7 PNGs in $OUT"
