#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/Sources/MijiaBarApp/Resources/House/modules"
rsync -a --delete --include='catalog.json' --include='module-*.png' --include='module-*.json' --include='curtain-*.png' --exclude='*' \
  "$ROOT/assets/house/modules/" "$ROOT/Sources/MijiaBarApp/Resources/House/modules/"
echo "synced modules -> Resources/House/modules ($(ls "$ROOT/Sources/MijiaBarApp/Resources/House/modules" | wc -l | tr -d ' ') files)"
