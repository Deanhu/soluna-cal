#!/bin/sh
# 打包前全量前置检查。make_dmg.sh 会先跑它，任一步失败就不出包。
#
# 检查项：
#   1. 断言来源守卫（历法事实必须有来源声明）
#   2. 节气断言与独立历法库对账（需要 lunar-python；缺失即失败，不静默跳过）
#   3. 单元测试全绿
#
# 用法：tools/preflight.sh [--skip-tests]

set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

SKIP_TESTS=0
for a in "$@"; do
    [ "$a" = "--skip-tests" ] && SKIP_TESTS=1
done

PY=""
for cand in \
    "$HOME/.workbuddy-ai/binaries/python/envs/default/bin/python" \
    "$(command -v python3 || true)"; do
    [ -x "$cand" ] && PY="$cand" && break
done
[ -n "$PY" ] || { echo "preflight: 找不到 python3"; exit 1; }

echo "== 1/3 断言来源守卫 =="
"$PY" tools/check_assertion_provenance.py

echo "== 2/3 节气断言独立对账 =="
"$PY" tools/verify_solarterm_assertions.py

if [ "$SKIP_TESTS" -eq 0 ]; then
    echo "== 3/3 单元测试 =="
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
        xcodebuild test -project SolunaCal.xcodeproj -scheme SolunaCal -quiet
else
    echo "== 3/3 单元测试（已跳过）=="
fi

echo "preflight: 全部通过"
