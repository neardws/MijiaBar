#!/bin/bash
# 推送前检查：仓库里不能出现真实设备 token / 局域网 IP
# 可以用环境变量 EXTRA_PATTERNS 追加自己的 token 前缀（用 | 分隔）
set -uo pipefail
cd "$(dirname "$0")/.."
PATTERN='192\.168\.[0-9]+\.[0-9]+|"token"[[:space:]]*:[[:space:]]*"[0-9a-f]{32}"'
[ -n "${EXTRA_PATTERNS:-}" ] && PATTERN="$PATTERN|$EXTRA_PATTERNS"
if git grep -nE "$PATTERN" -- . ':!scripts/scan-secrets.sh'; then echo "❌ 发现疑似敏感信息"; exit 1; fi
echo "✅ 未发现 token / 局域网 IP"
