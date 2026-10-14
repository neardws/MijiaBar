#!/bin/bash
# 下载 Sparkle 2.10 SPM XCFramework 到 .build/sparkle/spm/（校验 SHA-256，不进仓库）
set -euo pipefail
cd "$(dirname "$0")/.."
SPARKLE_VER=2.10.0
SPARKLE_SPM_SHA=17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959
SPARKLE_TAR_SHA=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
DEST=.build/sparkle/spm
TOOLS=.build/sparkle/$SPARKLE_VER
mkdir -p "$DEST" "$TOOLS"

Z="$DEST/Sparkle-for-Swift-Package-Manager.zip"
if [ ! -d "$DEST/Sparkle.xcframework" ]; then
  [ -f "$Z" ] || curl -fsSL -o "$Z" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VER/Sparkle-for-Swift-Package-Manager.zip"
  got=$(shasum -a 256 "$Z" | cut -d' ' -f1)
  [ "$got" = "$SPARKLE_SPM_SHA" ] || { echo "❌ Sparkle SPM zip 校验失败: $got"; rm -f "$Z"; exit 1; }
  rm -rf "$DEST/_extract" && mkdir -p "$DEST/_extract"
  unzip -q -o "$Z" -d "$DEST/_extract"
  fw=$(find "$DEST/_extract" -type d -name 'Sparkle.xcframework' | head -1)
  [ -n "$fw" ] || { echo "❌ zip 内无 Sparkle.xcframework"; exit 1; }
  rm -rf "$DEST/Sparkle.xcframework"
  mv "$fw" "$DEST/Sparkle.xcframework"
  rm -rf "$DEST/_extract"
  echo "✅ Sparkle.xcframework → $DEST/Sparkle.xcframework"
else
  echo "✅ Sparkle.xcframework 已存在"
fi

# 发行包（generate_appcast / generate_keys）
SZ="$TOOLS/Sparkle-$SPARKLE_VER.tar.xz"
if [ ! -x "$TOOLS/bin/generate_appcast" ]; then
  [ -f "$SZ" ] || curl -fsSL -o "$SZ" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VER/Sparkle-$SPARKLE_VER.tar.xz"
  got=$(shasum -a 256 "$SZ" | cut -d' ' -f1)
  [ "$got" = "$SPARKLE_TAR_SHA" ] || { echo "❌ Sparkle tar 校验失败: $got"; rm -f "$SZ"; exit 1; }
  tar -xJf "$SZ" -C "$TOOLS"
  echo "✅ Sparkle tools → $TOOLS/bin"
fi
