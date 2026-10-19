#!/bin/bash
# Scripts/{chess,go,gomoku,othello,shogi}-cpu-bench/build.sh が全部ビルドできることの検証（#2509）。
#
# bench は GameKit のエンジンのソースをコピーして単体バイナリにするため、GameKit 側のシグネチャや
# 依存（CPUStrength が引く tr、BoardHintBudget など）が変わるとコンパイルが壊れる。ところがテストも CI も
# 参照しておらず、次に計測する日まで誰も気づけなかった（このテストを足した時点で 5 本とも壊れていた）。
# ビルドが通ることだけを確かめる（実行はしない。計測内容・強さは対象外）。
#
# 使い方: bash Scripts/tests/test-cpu-bench-build.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d "${DUTY_SCRATCH_DIR:-${TMPDIR:-/tmp}}/cpu-bench-build-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

for game in chess go gomoku othello shogi; do
  build="$REPO/Scripts/$game-cpu-bench/build.sh"
  if [ ! -f "$build" ]; then
    ng "$game: build.sh が見つからない"
    continue
  fi
  if bash "$build" "$TMP/$game-bench" >"$TMP/$game.log" 2>&1 && [ -x "$TMP/$game-bench" ]; then
    ok "$game-cpu-bench がビルドできる"
  else
    ng "$game-cpu-bench のビルドに失敗"
    sed 's/^/        /' "$TMP/$game.log" | head -30
  fi
done

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
