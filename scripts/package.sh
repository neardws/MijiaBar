#!/bin/bash
# 构建 MijiaBar.app（ad-hoc 签名）并打包 DMG
# 用法: scripts/package.sh            （默认 universal: arm64 + x86_64）
#       ARCHS="--arch arm64" scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
ARCHS="${ARCHS:---arch arm64 --arch x86_64}"
APP=dist/MijiaBar.app

swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN/MijiaBarApp" "$APP/Contents/MacOS/MijiaBar"
cp "$BIN/mijiabar" "$APP/Contents/Resources/bin/mijiabar"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

codesign --force --sign - --timestamp=none "$APP/Contents/Resources/bin/mijiabar"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

STAGE=dist/dmg && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MijiaBar" -srcfolder "$STAGE" -ov -format UDZO "dist/MijiaBar-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
echo "✅ dist/MijiaBar-$VERSION.dmg"
