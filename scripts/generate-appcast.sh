#!/bin/bash
# 用 Sparkle 私钥给公证后的 DMG 签名，并写出 docs/appcast.xml（给 GitHub Pages）。
# 环境变量：
#   VERSION       版本号（必填或从 DMG 名推断）
#   DMG_PATH      公证后的 DMG；默认 dist/MijiaBar-$VERSION.dmg
#   SPARKLE_KEY   私钥路径，默认 ~/mijiabar-private/sparkle/eddsa_priv.key
#   DOWNLOAD_URL  enclosure URL，默认 GitHub Releases 资产地址
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/fetch-sparkle.sh
SP=.build/sparkle/2.10.0

KEY="${SPARKLE_KEY:-$HOME/mijiabar-private/sparkle/eddsa_priv.key}"
[ -f "$KEY" ] || { echo "❌ 找不到 Sparkle 私钥: $KEY"; echo "   应在 ~/mijiabar-private/sparkle/eddsa_priv.key（切勿提交到仓库）"; exit 1; }

VERSION="${VERSION:-}"
DMG_PATH="${DMG_PATH:-}"
if [ -z "$DMG_PATH" ] && [ -n "$VERSION" ]; then DMG_PATH="dist/MijiaBar-$VERSION.dmg"; fi
if [ -z "$DMG_PATH" ]; then
  DMG_PATH=$(ls -t dist/MijiaBar-*.dmg 2>/dev/null | grep -v unsigned | head -1 || true)
fi
[ -n "${DMG_PATH:-}" ] && [ -f "$DMG_PATH" ] || { echo "❌ 找不到 DMG（设 DMG_PATH 或 VERSION）"; exit 1; }
VERSION="${VERSION:-$(basename "$DMG_PATH" | sed -E 's/^MijiaBar-//; s/\.dmg$//; s/-unsigned$//')}"

DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/neardws/MijiaBar/releases/download/v${VERSION}/MijiaBar-${VERSION}.dmg}"

STAGE=$(mktemp -d /tmp/mijiabar-appcast.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
cp "$DMG_PATH" "$STAGE/MijiaBar-$VERSION.dmg"
NOTES="docs/release-notes/v$VERSION.md"
if [ -f "$NOTES" ]; then cp "$NOTES" "$STAGE/MijiaBar-$VERSION.md"; fi

"$SP/bin/generate_appcast" \
  --ed-key-file "$KEY" \
  --download-url-prefix "https://github.com/neardws/MijiaBar/releases/download/v${VERSION}/" \
  --link "https://www.neardws.com/MijiaBar/" \
  --embed-release-notes \
  -o "$STAGE/appcast.xml" \
  "$STAGE"

mkdir -p docs
cp "$STAGE/appcast.xml" docs/appcast.xml

python3 - "$DOWNLOAD_URL" <<'PY'
import sys, re
from pathlib import Path
url = sys.argv[1]
p = Path("docs/appcast.xml")
t = p.read_text()
t2, n = re.subn(r'(<enclosure[^>]*\surl=")[^"]+(")', rf"\1{url}\2", t, count=1)
p.write_text(t2 if n else t)
print(f"✅ docs/appcast.xml  (enclosure → {url})" if n else "⚠️  未找到 enclosure，原样保留")
PY
head -35 docs/appcast.xml
