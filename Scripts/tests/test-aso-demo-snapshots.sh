#!/bin/bash
# aso-demo-snapshots.py の検証（#2326）。
#
# 呼び元 capture-aso-screenshots.sh は出力を /dev/null に捨てるため、スクリプトが黙って壊れても
# スクショを撮る日まで気づけない。ここでは「落ちない・全部 JSON として読める・
# snapshot_* 関数の数だけ出力される」だけを固定する（中身の意味＝ゲーム側の復元可否は対象外）。
#
# 使い方: bash Scripts/tests/test-aso-demo-snapshots.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../aso-demo-snapshots.py"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"

# (1) 終了コード 0
if python3 "$TARGET" "$OUT" >"$TMP/stdout" 2>"$TMP/stderr"; then
  ok "終了コード 0"
else
  ng "終了コード 0 ではない: $(cat "$TMP/stderr")"
fi

# (2) 出力ファイルが全て JSON として読める
files=("$OUT"/*.json)
if [ -e "${files[0]}" ]; then
  bad=""
  for f in "${files[@]}"; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" 2>/dev/null \
      || bad="$bad $(basename "$f")"
  done
  if [ -z "$bad" ]; then
    ok "出力 ${#files[@]} 件が全て JSON として読める"
  else
    ng "JSON として読めない:$bad"
  fi
else
  ng "出力ファイルが無い"
fi

# (3) ファイル数が snapshot_* 関数の数と一致（ゲームを足して SNAPSHOTS への登録を忘れると落ちる）
funcs=$(grep -c '^def snapshot_' "$TARGET")
actual=$(find "$OUT" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$funcs" -gt 0 ] && [ "$funcs" -eq "$actual" ]; then
  ok "ファイル数 $actual が snapshot_* 関数の数 $funcs と一致"
else
  ng "ファイル数 $actual が snapshot_* 関数の数 $funcs と一致しない"
fi

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
