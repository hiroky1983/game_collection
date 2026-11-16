#!/bin/bash
# ai-weekly-meeting.sh（週次経営会議の起動スクリプト）の回帰検査（Issue #3516）。
# 月曜以外は起動しない曜日ガード・多重起動ロック・同日レポートの重複防止が壊れても CI が緑のまま、
# という状態をなくす。test-ai-management-lock.sh と同じ方式で、HOME / TMPDIR を一時ディレクトリへ
# 差し替え、`date` `gh` `git` `claude` は PATH 先頭（スクリプトが $HOME/.local/bin を先頭に足す）の
# スタブで置き換える。ロックのコードはトップレベルにあり source できないため、
# 「ロックを取り終えた直後で exit 0 する版」を awk で生成して本物のロジックを通す。
#
# 使い方: bash Scripts/tests/test-ai-weekly-meeting.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ai-weekly-meeting.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/ai-weekly-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/Library/Logs" "$TEST_HOME/.local/bin"

LOCK="$TEST_HOME/asobiba-ai-weekly.lock"   # LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-weekly.lock"
LOG="$TEST_HOME/Library/Logs/asobiba-ai-weekly.log"
CLAUDE_MARK="$TEST_HOME/claude-called"
DEAD_PID=999999
while kill -0 "$DEAD_PID" 2>/dev/null; do DEAD_PID=$((DEAD_PID + 1)); done

# --- スタブ ---
# date: 曜日（+%u / +%A）だけ FAKE_DOW に固定し、ほかは本物へ流す
cat >"$TEST_HOME/.local/bin/date" <<'STUB'
#!/bin/bash
case "$*" in
  "+%u") echo "${FAKE_DOW:-1}" ;;
  "+%A") echo "FakeDay${FAKE_DOW:-1}" ;;
  *) exec /bin/date "$@" ;;
esac
STUB
# gh: auth は成功、issue list は FAKE_EXISTING 件を返す
cat >"$TEST_HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "issue list") echo "${FAKE_EXISTING:-0}" ;;
esac
exit 0
STUB
# git: worktree add だけ作業ディレクトリを実際に作る（ほかは何もしない）
cat >"$TEST_HOME/.local/bin/git" <<'STUB'
#!/bin/bash
case "$*" in
  *"worktree add"*) mkdir -p "${@: -2:1}" ;;
esac
exit 0
STUB
# claude: 呼ばれた事実だけ残す
cat >"$TEST_HOME/.local/bin/claude" <<STUB
#!/bin/bash
echo called >>"$CLAUDE_MARK"
exit 0
STUB
chmod +x "$TEST_HOME/.local/bin/"*

# ロックを取り終えた直後で終わる版（claude も gh も呼ばせない）
E2E="$TEST_HOME/ai-weekly-lock-e2e.sh"
awk '{ print } /^trap .* EXIT$/ { print "exit 0" }' "$TARGET" >"$E2E"

run() {  # run <script> [追加の環境変数...]
  local script="$1"; shift
  env HOME="$TEST_HOME" TMPDIR="$TEST_HOME" WEEKLY_SELF_UPDATED=1 "$@" bash "$script"
}
reset() { rm -rf "$LOCK" "$CLAUDE_MARK" "$TEST_HOME/.asobiba-weekly"; : >"$LOG"; }
logged() { grep -c -- "$1" "$LOG" | tr -d ' '; }
lock_exists() { if [ -d "$LOCK" ]; then echo yes; else echo no; fi; }
claude_called() { if [ -f "$CLAUDE_MARK" ]; then echo yes; else echo no; fi; }

echo "== 0. 前提 =="
if bash -n "$TARGET"; then ok "bash -n が通る"; else ng "bash -n が失敗"; fi
if grep -q '^exit 0$' "$E2E"; then ok "テスト用スクリプトを生成できた（trap 行が見つかる）"; else ng "テスト用スクリプトの生成に失敗（trap 行が見つからない）"; fi

echo "== 1. 曜日ガード =="
reset
run "$TARGET" FAKE_DOW=3
check "月曜以外は終了コード 0" "0" "$?"
check "「月曜以外のため起動しない」のログが出る" "1" "$(logged '月曜以外のため起動しない')"
check "ロックまで進まない" "no" "$(lock_exists)"
check "claude を呼ばない" "no" "$(claude_called)"

reset
run "$E2E" FAKE_DOW=7
check "日曜でも起動しない" "1" "$(logged '月曜以外のため起動しない')"

reset
run "$E2E" FAKE_DOW=1
check "月曜は先へ進む（ガードのログなし）" "0" "$(logged '月曜以外のため起動しない')"
check "月曜はロックを取って解放する" "no" "$(lock_exists)"

reset
run "$E2E" FAKE_DOW=3 WEEKLY_FORCE=1
check "WEEKLY_FORCE=1 なら月曜以外でも先へ進む" "0" "$(logged '月曜以外のため起動しない')"

echo "== 2. 実行中はスキップ（生きた PID のロックは奪わない）=="
reset
mkdir "$LOCK"; echo $$ >"$LOCK/pid"
run "$E2E" WEEKLY_FORCE=1
check "終了コード 0" "0" "$?"
check "実行中のロックは残る" "yes" "$(lock_exists)"
check "「前回実行中」のログが出る" "1" "$(logged "前回実行中 (pid=$$)")"
check "PID ファイルは書き換わらない" "$$" "$(cat "$LOCK/pid")"

echo "== 3. PID 未書き込みで取得直後（WEEKLY_LOCK_GRACE 内）はスキップ =="
reset
mkdir "$LOCK"
run "$E2E" WEEKLY_FORCE=1
check "終了コード 0" "0" "$?"
check "ロックは残る" "yes" "$(lock_exists)"
check "「ロック取得直後」のログが出る" "1" "$(logged 'ロック取得直後')"
if [ -f "$LOCK/pid" ]; then ng "他プロセスの取得中ロックに PID を書き込んだ"; else ok "他プロセスの取得中ロックには触れない"; fi

echo "== 4. 猶予を超えた PID 未書き込みロックは回収する =="
reset
mkdir "$LOCK"; touch -t 202001010000 "$LOCK"
run "$E2E" WEEKLY_FORCE=1
check "終了コード 0" "0" "$?"
check "「ロックを回収」のログが出る" "1" "$(logged '停止済みプロセスのロックを回収 (pid=不明)')"
check "回収後は解放される" "no" "$(lock_exists)"

echo "== 4-b. 猶予は WEEKLY_LOCK_GRACE で調整できる =="
reset
mkdir "$LOCK"
run "$E2E" WEEKLY_FORCE=1 WEEKLY_LOCK_GRACE=0
check "猶予 0 なら PID 未書き込みでも回収する" "1" "$(logged '停止済みプロセスのロックを回収')"

echo "== 5. 死んだ PID のロックは回収する =="
reset
mkdir "$LOCK"; echo "$DEAD_PID" >"$LOCK/pid"
run "$E2E" WEEKLY_FORCE=1
check "終了コード 0" "0" "$?"
check "死んだ PID が出る回収ログ" "1" "$(logged "停止済みプロセスのロックを回収 (pid=$DEAD_PID)")"
check "回収後は解放される" "no" "$(lock_exists)"

echo "== 6. 同日レポートが既にあれば claude を呼ばずに見送る =="
reset
mkdir -p "$TEST_HOME/.asobiba-weekly/game_collection/.git"   # clone 経路を通さない
run "$TARGET" FAKE_DOW=1 FAKE_EXISTING=1
check "終了コード 0" "0" "$?"
check "「既に存在するため見送り」のログが出る" "1" "$(logged '既に存在するため見送り')"
check "claude を呼ばない" "no" "$(claude_called)"
check "起動ログは出ない" "0" "$(logged '週次経営会議起動')"
check "見送り時もロックは解放される" "no" "$(lock_exists)"

echo "== 6-b. 同日レポートが無ければ claude を呼ぶ（対照）=="
reset
mkdir -p "$TEST_HOME/.asobiba-weekly/game_collection/.git"
run "$TARGET" FAKE_DOW=1 FAKE_EXISTING=0 2>/dev/null
check "終了コード 0" "0" "$?"
check "見送りのログは出ない" "0" "$(logged '既に存在するため見送り')"
check "claude を呼ぶ" "yes" "$(claude_called)"
check "「週次経営会議終了」のログが出る" "1" "$(logged '週次経営会議終了 (exit=0)')"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
