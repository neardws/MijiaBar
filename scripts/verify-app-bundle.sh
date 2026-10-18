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

for style in japanese modern light-wood walnut; do
  PACK="$RESOURCES/House/styles/$style"
  [ -d "$PACK/modules" ] || fail "missing $PACK/modules"
  [ -n "$(find "$PACK/modules" -type f -name '*.png' -print -quit)" ] \
    || fail "no style PNGs in $PACK/modules"
  if [[ "$style" == light-wood || "$style" == walnut ]]; then
    [ -d "$PACK/classic" ] || fail "missing $PACK/classic"
    [ -n "$(find "$PACK/classic" -type f -name '*.png' -print -quit)" ] \
      || fail "no style PNGs in $PACK/classic"
  fi
done
echo "✅ App resource bundles and House style PNGs verified"
