#!/bin/bash
# 用 app 自带的渲染器重新生成 Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
T=$(mktemp -d); .build/debug/MijiaBarApp --icon "$T/icon.png"
I="$T/AppIcon.iconset"; mkdir -p "$I"
for s in 16 32 128 256 512; do
  sips -z $s $s "$T/icon.png" --out "$I/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$T/icon.png" --out "$I/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$I" -o Resources/AppIcon.icns && echo "✅ Resources/AppIcon.icns"
