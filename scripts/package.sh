#!/bin/bash
# 构建 MijiaBar.app 并打包 DMG。
#   有 Developer ID 证书时：hardened runtime 签名 → 公证 → staple
#   没有证书时：ad-hoc 签名，DMG 文件名带 -unsigned
# 环境变量：
#   VERSION         版本号（默认 0.1.1）
#   ARCHS           默认 "--arch arm64 --arch x86_64"
#   SIGN_IDENTITY   签名身份；默认自动找 "Developer ID Application"，设为 "-" 强制 ad-hoc
#   NOTARY_PROFILE  notarytool 钥匙串配置名（默认 MijiaBar-notary）；设为空跳过公证
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.6}"
ARCHS="${ARCHS:---arch arm64 --arch x86_64}"
NOTARY_PROFILE="${NOTARY_PROFILE-MijiaBar-notary}"
ENT=Resources/MijiaBar.entitlements
APP=dist/MijiaBar.app

if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)
  [ -z "$SIGN_IDENTITY" ] && SIGN_IDENTITY="-"
fi
if [ "$SIGN_IDENTITY" = "-" ]; then
  DMG="dist/MijiaBar-$VERSION-unsigned.dmg"; echo "⚠️  未找到 Developer ID，使用 ad-hoc 签名"
else
  DMG="dist/MijiaBar-$VERSION.dmg"; echo "🔏 签名身份: $SIGN_IDENTITY"
fi

swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN/MijiaBarApp" "$APP/Contents/MacOS/MijiaBar"
cp "$BIN/mijiabar" "$APP/Contents/Resources/bin/mijiabar"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

sign() {
  if [ "$SIGN_IDENTITY" = "-" ]; then codesign --force --sign - --timestamp=none "$@"
  else codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$@"; fi
}
# 由内向外签名：先 CLI，再 app
sign --identifier com.neardws.MijiaBar.cli --entitlements "$ENT" "$APP/Contents/Resources/bin/mijiabar"
sign --entitlements "$ENT" "$APP"
codesign --verify --strict --verbose=2 "$APP"

STAGE=dist/dmg && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MijiaBar" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  if [ -n "$NOTARY_PROFILE" ]; then
    echo "📮 提交公证…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait | tee dist/notary.log
    grep -q "status: Accepted" dist/notary.log || { echo "❌ 公证失败，用 xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE 查看"; exit 1; }
    xcrun stapler staple "$APP"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl -a -vv "$APP"
    spctl -a -vvv -t install "$DMG"
  fi
fi
echo "✅ $DMG"
