#!/bin/bash
# 网站用图：每种语言的界面截图（浅色 / 深色）、设备插画（WebP）和分享图，放进 docs/assets/
# 依赖：先 swift build；cwebp（brew install webp）
# 主列表截图的小屋按本机时间显示白天或夜晚；list-night-* 和小屋大图固定用 MIJIABAR_HOUSE_PHASE / 固定状态
# 只在界面外观或演示数据变了时重新生成；之后运行 python3 scripts/gen-site.py
set -euo pipefail
cd "$(dirname "$0")/.."
APP=.build/debug/MijiaBarApp
[ -x "$APP" ] || { echo "❌ 先运行 swift build"; exit 1; }
command -v cwebp >/dev/null || { echo "❌ 需要 cwebp：brew install webp"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
webp() { cwebp -quiet -q 82 -m 6 -metadata none "$@" 2>/dev/null; }

# 设备插画（与语言无关）
"$APP" --art "$TMP/art" >/dev/null
mkdir -p docs/assets/art
for f in "$TMP"/art/*.png; do webp "$f" -o "docs/assets/art/$(basename "${f%.png}").webp"; done
# 分享图（og:image）
swift scripts/site-og.swift "$TMP/art" "$TMP/og.png" >/dev/null
sips -s format jpeg -s formatOptions 88 "$TMP/og.png" --out docs/assets/og.jpg >/dev/null

# 界面截图：App 语言代码 → 网页代码
SCREENS="list ac-cool ac-heat light fan plug camera-live login"
# 和 scripts/gen-site.py 的 LANGS 保持一致（目前只发布英文和简体中文）
for pair in en:en zh-Hans:zh-CN; do
  app=${pair%%:*}; web=${pair##*:}
  MIJIABAR_LANG=$app "$APP" --snapshot "$TMP/$web" -AppleLanguages "($app)" >/dev/null
  mkdir -p "docs/assets/shots/$web"
  for s in $SCREENS; do for t in light dark; do
    # 摄像机页下方是空白，裁掉（720×860 → 网页上 360×430）
    crop=(); [ "$s" = camera-live ] && crop=(-crop 0 0 720 860)
    webp "${crop[@]+"${crop[@]}"}" "$TMP/$web/$s-$t.png" -o "docs/assets/shots/$web/$s-$t.webp"
  done; done
  # 小屋区块：夜晚的列表截图（小屋嵌在列表顶部，只亮开着的灯具）
  MIJIABAR_HOUSE_PHASE=night MIJIABAR_LANG=$app "$APP" --snapshot "$TMP/night-$web" -AppleLanguages "($app)" >/dev/null
  for t in light dark; do webp "$TMP/night-$web/list-$t.png" -o "docs/assets/shots/$web/list-night-$t.webp"; done
  echo "✅ $web"
done
# 小屋剖面大图（与语言无关，1920×1080 → 1440×810）
"$APP" --house-snapshot "$TMP/house" >/dev/null
mkdir -p docs/assets/shots/house
for n in house-night-partial house-day-partial house-night-onelamp house-night-twolamps; do
  sips -Z 1440 "$TMP/house/$n.png" --out "$TMP/house/$n-1440.png" >/dev/null
  webp "$TMP/house/$n-1440.png" -o "docs/assets/shots/house/$n.webp"
done
du -sh docs/assets/shots docs/assets/art docs/assets/og.jpg
