#!/bin/bash
# ai-audit-duty.sh の監査対象窓（#822 ①・受け入れ条件）の検証。
# `gh pr list` が失敗した回は `~/.asobiba-audit/last-run` を進めず、次回に同じ期間を
# もう一度対象にする。「本当に対象 0 件」の回だけ窓を進める。この2つを取り違えると、
# レート制限やオフラインで gh が失敗した回の PR が恒久的に監査から漏れる（#822 原文）。
#
# 使い方: bash Scripts/tests/test-ai-audit-window.sh
#
# 仕込み方: ai-audit-duty.sh は先頭で PATH を `$HOME/.local/bin:...` に固定するため、
# HOME をテスト用の一時ディレクトリに差し替え、そこへ偽の gh を置けば本物の実装コードを
# そのまま通せる（test-ai-duty-notify.sh と同じ方式）。ただしこのスクリプトは通知当番と違い
# 「gh pr list を呼ぶまで」に自己更新・ロック・クローン・fetch・使い捨て worktree・
# 入力フィルタの用意まで一直線に進む作りなので、それらを本物のまま通すために
#   - 自己更新は AUDIT_DIR の origin に Scripts/ai-audit-duty.sh を置かず no-op させる
#     （self_update は origin/main の当該パスが無ければ何もせず return する）
#   - AUDIT_DIR は「監査対象なし（0 件）」「gh 失敗」のどちらでも claude の起動前に
#     exit するため、AUDIT_DIR の origin には Scripts/duty-gh-shim/ だけ実体を置けば足りる
# という最小限のローカル git リポジトリを一度だけ用意し、ネットワークに出ない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ai-audit-duty.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/ai-audit-window-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/Library/Logs" "$TEST_HOME/.asobiba-audit"

# 偽 gh: `auth status` は常に成功、`pr list` だけモックで応答を切り替える。
# それ以外（呼ばれない想定）は素通しで成功させ、想定外の呼び出しにも当番を止めない。
cat >"$TEST_HOME/.local/bin/gh" <<'MOCK'
#!/bin/bash
if [ "${1:-}" = "auth" ]; then exit 0; fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  printf 'pr list\n' >>"${MOCK_GH_CALLS:-/dev/null}"
  if [ -n "${MOCK_GH_PR_LIST_FAIL:-}" ]; then
    echo "mock: gh pr list を失敗させる（レート制限・オフラインの再現）" >&2
    exit 1
  fi
  printf '%s' "${MOCK_GH_PR_LIST_OUT:-}"
  exit 0
fi
exit 0
MOCK
chmod +x "$TEST_HOME/.local/bin/gh"

# AUDIT_DIR のローカル origin を一度だけ用意する。Scripts/duty-gh-shim/ だけを含み、
# Scripts/ai-audit-duty.sh は含めない（self_update を no-op させ、実行中のスクリプトを
# 別バージョンへ差し替えさせないため）。
ORIGIN_SRC="$TEST_HOME/origin-src"
mkdir -p "$ORIGIN_SRC/Scripts/duty-gh-shim"
cp "$SCRIPT_DIR/../duty-gh-shim/gh" "$SCRIPT_DIR/../duty-gh-shim/filter.jq" "$ORIGIN_SRC/Scripts/duty-gh-shim/"
git -C "$ORIGIN_SRC" init -q -b main
git -C "$ORIGIN_SRC" -c user.email=test@example.com -c user.name=test add -A
git -C "$ORIGIN_SRC" -c user.email=test@example.com -c user.name=test commit -q -m init

ORIGIN_BARE="$TEST_HOME/origin.git"
git clone -q --bare "$ORIGIN_SRC" "$ORIGIN_BARE" || { echo "origin.git の用意に失敗"; exit 1; }

AUDIT_DIR="$TEST_HOME/.asobiba-audit/game_collection"
git clone -q "$ORIGIN_BARE" "$AUDIT_DIR" || { echo "AUDIT_DIR の用意に失敗"; exit 1; }

LOG="$TEST_HOME/Library/Logs/asobiba-ai-audit.log"
LAST_RUN_FILE="$TEST_HOME/.asobiba-audit/last-run"

run() {  # run [追加の環境変数...] — TARGET を実行する。HOME/TMPDIR をテスト側に閉じる
  env HOME="$TEST_HOME" TMPDIR="$TEST_HOME" "$@" bash "$TARGET"
}
reset() {
  rm -rf "$TEST_HOME/asobiba-ai-audit.lock"
  : >"$LOG"
  export MOCK_GH_CALLS="$TEST_HOME/gh-calls.log"
  : >"$MOCK_GH_CALLS"
}
logged() { grep -c -- "$1" "$LOG" | tr -d ' '; }

echo "== 0. 前提 =="
if bash -n "$TARGET"; then ok "bash -n が通る"; else ng "bash -n が失敗"; fi
check "コピペ残りの ai-management- が Scripts/ai-audit-duty.sh に無い" "0" "$(grep -c ai-management- "$TARGET")"

echo "== 1. gh pr list が失敗したら last-run を進めない（#822 ①・本題）=="
reset
echo "2020-01-01T00:00:00Z" >"$LAST_RUN_FILE"
export MOCK_GH_PR_LIST_FAIL=1
unset MOCK_GH_PR_LIST_OUT
run
RC=$?
unset MOCK_GH_PR_LIST_FAIL
check "終了コード 0（launchd を騒がせない）" "0" "$RC"
check "last-run は書き換わらない（次回また同じ期間を対象にする）" "2020-01-01T00:00:00Z" "$(cat "$LAST_RUN_FILE")"
check "「gh pr list に失敗」のログが出る" "1" "$(logged 'gh pr list に失敗')"
check "「監査対象なし」とは区別してログに出す（失敗を空と誤認しない）" "0" "$(logged '監査対象なし')"
check "gh pr list は実際に1回呼ばれた（モックが素通りしていない）" "1" "$(wc -l <"$MOCK_GH_CALLS" | tr -d ' ')"

echo "== 2. gh pr list が 0 件で成功したら last-run を進める =="
reset
echo "2020-01-01T00:00:00Z" >"$LAST_RUN_FILE"
export MOCK_GH_PR_LIST_OUT=""
run
RC=$?
unset MOCK_GH_PR_LIST_OUT
check "終了コード 0" "0" "$RC"
if [ "$(cat "$LAST_RUN_FILE")" = "2020-01-01T00:00:00Z" ]; then
  ng "last-run が進んでいない（0 件成功なのに窓が動いていない）"
else
  ok "last-run が今回の実行時刻へ進む"
fi
case "$(cat "$LAST_RUN_FILE")" in
  20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ok "last-run が ISO 8601 (UTC) の形式" ;;
  *) ng "last-run の形式がおかしい ($(cat "$LAST_RUN_FILE"))" ;;
esac
check "「監査対象なし」のログが出る" "1" "$(logged '監査対象なし')"
check "「gh pr list に失敗」のログは出ない" "0" "$(logged 'gh pr list に失敗')"

echo "== 3. 初回失敗 → 次回 0 件成功、の2回続けても窓は最後だけ進む（回帰防止）=="
reset
echo "2020-01-01T00:00:00Z" >"$LAST_RUN_FILE"
export MOCK_GH_PR_LIST_FAIL=1
run >/dev/null
unset MOCK_GH_PR_LIST_FAIL
check "1回目（失敗）の後も last-run は変わらない" "2020-01-01T00:00:00Z" "$(cat "$LAST_RUN_FILE")"
export MOCK_GH_PR_LIST_OUT=""
run >/dev/null
unset MOCK_GH_PR_LIST_OUT
if [ "$(cat "$LAST_RUN_FILE")" = "2020-01-01T00:00:00Z" ]; then
  ng "2回目（0件成功）でも last-run が進んでいない"
else
  ok "2回目（0件成功）で last-run が進む（失敗した回の期間を含めて対象にできる）"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
