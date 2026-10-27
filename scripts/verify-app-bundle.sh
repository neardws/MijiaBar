#!/bin/bash
set -euo pipefail

APP="${1:-dist/MijiaBar.app}"
RESOURCES="$APP/Contents/Resources"
BUNDLE="$RESOURCES/MijiaBar_MijiaBarApp.bundle"

fail() { echo "❌ App resource verification failed: $*" >&2; exit 1; }

[ -d "$BUNDLE" ] || fail "missing $BUNDLE"
[ -n "$(find "$BUNDLE" -type f -name 'house-cutaway*.png' -print -quit)" ] \
  || fail "no House cutaway PNGs in $BUNDLE"
[ -n "$(find "$BUNDLE" -type f -name 'module-*.png' -print -quit)" ] \
  || fail "no House module PNGs in $BUNDLE"
for resource in catalog.json module-living-day-unlit.png module-living-day-lit.png module-living-night-unlit.png module-living-night-lit.png; do
  [ -n "$(find "$BUNDLE" -type f -name "$resource" -print -quit)" ] || fail "missing default style resource $resource"
done
[ -n "$(find "$BUNDLE" -type f -name 'decor-*.png' -print -quit)" ] \
  || fail "no decor PNGs in $BUNDLE"
[ -n "$(find "$BUNDLE" -type f -name 'decor-catalog.json' -print -quit)" ] \
  || fail "no decor catalog in $BUNDLE"
for pet in pet-spots.json {cat,dog}-short.json {cat,dog}-short-{solid,tabby,tabbyWhite,bicolor,calico,colorpoint}.png; do
  [ -n "$(find "$BUNDLE" -type f -name "$pet" -print -quit)" ] || fail "missing pet resource $pet in $BUNDLE"
done

MODE="${HOUSE_STYLE_BUNDLE:-detect}"
case "$MODE" in all|default|detect) ;; *) fail "invalid HOUSE_STYLE_BUNDLE: $MODE" ;; esac
[ -n "$(find "$BUNDLE" -type f -name 'style-packs.json' -print -quit)" ] || fail "missing baked style pack index"
PRESENT=0
for style in japanese modern light-wood walnut; do
  [ ! -e "$RESOURCES/House/styles/$style" ] || PRESENT=$((PRESENT + 1))
done
if [ "$MODE" = default ]; then
  [ "$PRESENT" = 0 ] || fail "default mode contains optional styles"
elif [ "$MODE" = all ]; then
  [ "$PRESENT" = 4 ] || fail "all mode requires four styles"
else
  [ "$PRESENT" = 0 ] || [ "$PRESENT" = 4 ] || fail "partially bundled styles"
fi
if [ "$PRESENT" = 4 ]; then
for style in japanese modern light-wood walnut; do
  PACK="$RESOURCES/House/styles/$style"
  [ -f "$PACK/manifest.json" ] || fail "missing $PACK/manifest.json"
  if [[ "$style" == japanese || "$style" == modern ]]; then
    [ -f "$PACK/modules/catalog.json" ] || fail "missing $PACK/modules/catalog.json"
  fi
  [ -d "$PACK/modules" ] || fail "missing $PACK/modules"
  [ -n "$(find "$PACK/modules" -type f -name '*.png' -print -quit)" ] \
    || fail "no style PNGs in $PACK/modules"
  if [[ "$style" == light-wood || "$style" == walnut ]]; then
    [ -d "$PACK/classic" ] || fail "missing $PACK/classic"
    [ -n "$(find "$PACK/classic" -type f -name '*.png' -print -quit)" ] \
      || fail "no style PNGs in $PACK/classic"
  fi
done
fi
echo "✅ App resource bundles and House style PNGs verified"
