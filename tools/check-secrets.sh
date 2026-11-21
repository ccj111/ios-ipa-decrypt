#!/usr/bin/env bash
# check-secrets.sh — 发布前闸门（形状检查，不含任何真实值）
#
# 设计：这个脚本本身也要能公开，所以它不保存具体的 selector / udid / accountId。
# 它只检查这些值的**形状**；维护者另有 .secrets-local.txt（gitignored）做精确比对。
set -eu
cd "$(dirname "$0")/.."

fail=0
scan() {  # scan <描述> <正则> [白名单正则]
  local what="$1" pattern="$2" allow="${3:-}"
  local hits
  hits="$(grep -rnE "$pattern" --include='*.md' --include='*.sh' --include='*.py' \
            --include='*.sql' --include='*.svg' --include='*.yml' . 2>/dev/null \
          | grep -v '^./tools/check-secrets.sh:' || true)"
  if [ -n "$allow" ]; then hits="$(printf '%s\n' "$hits" | grep -vE "$allow" || true)"; fi
  if [ -n "$hits" ]; then printf '%s\n%s\n' "FAIL: $what" "$hits"; fail=1; fi
}

scan "疑似完整 selector（64 位十六进制）"    '[0-9a-f]{64}'      'sha256|SHA256|SHA-256|hash|digest|校验'
scan "疑似 udid（40 位十六进制）"            '[0-9a-f]{40}'      'sha256|SHA256|hash|digest'
scan "疑似 accountId（UUID）"                '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
scan "疑似真实 SINF 取值（user=N key=N）"    'user=[0-9]{2,}.{0,30}key=[0-9]+'
scan "绝对家目录路径"                        '/Users/[A-Za-z]'
scan "疑似真实邮箱"                          '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'  'example\.(com|invalid)|example|@example'
scan "疑似真实 bundle id"  'com\.[a-z0-9_]+\.[a-z0-9_]+'  'com\.example\.|com\.apple\.'

# 精确比对（仅在本地存在私有清单时执行；清单不入库）
if [ -f .secrets-local.txt ]; then
  while IFS= read -r needle; do
    [ -z "$needle" ] && continue
    case "$needle" in \#*) continue ;; esac
    if grep -rnF "$needle" --include='*.md' --include='*.sh' --include='*.py' \
         --include='*.sql' --include='*.svg' --include='*.yml' . >/dev/null 2>&1; then
      echo "FAIL: 命中本地私有清单中的条目（已隐藏）"
      fail=1
    fi
  done < .secrets-local.txt
fi

[ "$fail" = 0 ] && echo 'ok: 未发现真实标识形状'
exit "$fail"
