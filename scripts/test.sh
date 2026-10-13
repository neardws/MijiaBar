#!/bin/bash
# 运行单元测试（Swift Testing）
# 用法: scripts/test.sh [swift test 的参数，例如 --filter LANHealth]
# 装了 Xcode 时直接 swift test；只有 Command Line Tools 时，需要手动指定 Testing.framework 的位置，
# 并改用 26.x SDK（27 SDK 缺少 SwiftUI 宏插件，App 目标编译不过）。
set -euo pipefail
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools
if [[ "$(xcode-select -p)" == "$CLT"* ]]; then
  F="$CLT/Library/Developer/Frameworks"
  [[ -d "$CLT/SDKs/MacOSX26.sdk" ]] && export SDKROOT="$CLT/SDKs/MacOSX26.sdk"
  exec swift test --build-system native -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" "$@"
fi
exec swift test "$@"
