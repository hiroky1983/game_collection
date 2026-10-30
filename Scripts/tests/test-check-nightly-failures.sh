#!/bin/bash
# check-nightly-failures.sh（#3077）の検証: failure / success / 起票済み の 3 ケースを gh のスタブで確かめる。
# 使い方: bash Scripts/tests/test-check-nightly-failures.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-nightly-failures.sh"
PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/nightly-failures-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
CALLS="$TMP/calls"
# 環境変数: RUN_CONCLUSION（run list の conclusion）/ EXISTING（issue list の件数）
cat >"$TMP/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >>"$CALLS"
case "$1 $2" in
  "run list")  [ -n "$RUN_CONCLUSION" ] && echo "$RUN_CONCLUSION	777	https://example.test/runs/777" ;;
  "run view")  printf 'FAILED test A\nline2\n' ;;
  "issue list") echo "${EXISTING:-0}" ;;
  "issue create") echo "https://example.test/issues/1" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gh"
export CALLS PATH="$TMP/bin:$PATH" NIGHTLY_MILESTONE_CMD="echo v1.1.15"

run() { : >"$CALLS"; RUN_CONCLUSION="$1" EXISTING="${2:-0}" bash "$TARGET"; }
creates() { grep -c '^issue create' "$CALLS" || true; }

echo "== failure: 夜間 2 本ぶん起票する =="
run failure
check "終了コード" "0" "$?"
check "2 本起票" "2" "$(creates)"
grep -q 'nightly-run-id: 777' "$CALLS" && ok "本文に run ID" || ng "本文に run ID が無い"
grep -q 'FAILED test A' "$CALLS" && ok "本文に落ちたログ" || ng "本文に落ちたログが無い"
grep -q -- '--milestone v1.1.15' "$CALLS" && ok "マイルストーンを付ける" || ng "マイルストーンが無い"

echo "== success: 何もしない =="
run success
check "起票 0" "0" "$(creates)"
run ""
check "run が無くても起票 0" "0" "$(creates)"

echo "== 起票済み: 二重に起票しない =="
run failure 1
check "起票 0" "0" "$(creates)"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
