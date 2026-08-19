#!/bin/bash
# ai-duty.sh の多重起動防止ロック（Issue #165）の検証。
# ロック取得のコードは DUTY_LIB_ONLY の入口より後ろにあり source では届かないため、
# 「ロックを取り終えた直後で exit 0 する版」を awk で生成して本物のロジックを通す
# （test-ai-duty-notify.sh のテスト10と同じ方式）。
#
# 使い方: bash Scripts/tests/test-ai-duty-lock.sh
#
# HOME をテスト用の一時ディレクトリへ差し替えるので、
#   - 自己更新（self_update）は $HOME/.asobiba-duty/game_collection/.git が無いため即 return する
#   - ログ・通知の状態ファイルもテスト側に閉じる
# TMPDIR も差し替えるため LOCK_DIR は会長の実ロックと衝突しない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ai-duty.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/ai-duty-lock-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/Library/Logs"

LOCK="$TEST_HOME/asobiba-ai-duty.lock"   # ai-duty.sh の LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-duty.lock"
LOG="$TEST_HOME/Library/Logs/asobiba-ai-duty.log"
# macOS の既定の PID 上限は 99998。存在しえない PID を使うことで「死んだプロセス」を決定論的に作る
DEAD_PID=999999

# ロックを取り終えた直後で終わる版（claude も gh も呼ばせない）
E2E="$TEST_HOME/ai-duty-lock-e2e.sh"
awk '{ print } /^trap .* EXIT$/ { print "exit 0" }' "$TARGET" >"$E2E"
# PID_FILE を書いた直後に他プロセスが奪った状況を再現する版（回収の競合・所有者以外は消さない）
E2E_STOLEN="$TEST_HOME/ai-duty-lock-stolen.sh"
awk -v dead="$DEAD_PID" '
  { print }
  /^echo \$\$ >"\$PID_FILE"$/ { print "echo " dead " >\"$PID_FILE\"" }
  /^trap .* EXIT$/            { print "exit 0" }
' "$TARGET" >"$E2E_STOLEN"

run() {  # run [追加の環境変数...] — 生成済みスクリプトを走らせ、終了コードを返す
  local script="$1"; shift
  env HOME="$TEST_HOME" TMPDIR="$TEST_HOME" "$@" bash "$script"
}
reset() { rm -rf "$LOCK"; : >"$LOG"; }
logged() { grep -c -- "$1" "$LOG" | tr -d ' '; }
lock_exists() { if [ -d "$LOCK" ]; then echo yes; else echo no; fi; }

echo "== 0. 前提 =="
if bash -n "$TARGET"; then ok "bash -n が通る"; else ng "bash -n が失敗"; fi
if grep -q '^exit 0$' "$E2E"; then ok "テスト用スクリプトを生成できた（trap 行が見つかる）"; else ng "テスト用スクリプトの生成に失敗（trap 行が見つからない）"; fi
check "PID を奪う版を生成できた" "1" "$(grep -c "^echo $DEAD_PID >\"\$PID_FILE\"$" "$E2E_STOLEN")"
check "release_lock が EXIT トラップから呼ばれる" "1" "$(grep -c '^trap .*release_lock.* EXIT$' "$TARGET")"
check "cleanup_simulators / notify_pending は所有権と無関係に走る" "1" "$(grep -c '^trap .cleanup_simulators; notify_pending; release_lock. EXIT$' "$TARGET")"

echo "== 1. 通常取得と解放 =="
reset
run "$E2E"
check "終了コード 0" "0" "$?"
check "終了時にロックが解放される" "no" "$(lock_exists)"
check "スキップのログは出ない" "0" "$(logged 'のためスキップ')"

echo "== 2. 実行中はスキップ（生きた PID のロックは奪わない）=="
reset
mkdir "$LOCK"; echo $$ >"$LOCK/pid"   # テスト自身の PID = 確実に生きている
run "$E2E"
check "終了コード 0（launchd を騒がせない）" "0" "$?"
check "実行中のロックは残る" "yes" "$(lock_exists)"
check "「前回実行中」のログが出る" "1" "$(logged "前回実行中 (pid=$$)")"
check "PID ファイルは書き換わらない" "$$" "$(cat "$LOCK/pid")"

echo "== 3. PID 未書き込みのロックを奪わない（本 Issue の本題）=="
reset
mkdir "$LOCK"   # mkdir 直後 = PID を書く前の状態。mtime は現在時刻
run "$E2E"
check "終了コード 0" "0" "$?"
check "取得直後のロックは残る" "yes" "$(lock_exists)"
check "「ロック取得直後」のログが出る" "1" "$(logged 'ロック取得直後')"
if [ -f "$LOCK/pid" ]; then ng "他プロセスの取得中ロックに PID を書き込んでしまった"; else ok "他プロセスの取得中ロックには触れない"; fi

echo "== 4. 猶予を超えた PID 未書き込みロックは回収する（永久ロックを作らない）=="
reset
mkdir "$LOCK"; touch -t 202001010000 "$LOCK"   # mtime を過去に倒して猶予超過を作る
run "$E2E"
check "終了コード 0" "0" "$?"
check "回収したロックは終了時に解放される" "no" "$(lock_exists)"
check "「ロックを回収」のログが出る" "1" "$(logged '停止済みプロセスのロックを回収 (pid=不明)')"
check "取得直後の判定には落ちない" "0" "$(logged 'ロック取得直後')"

echo "== 4-b. 猶予は DUTY_LOCK_GRACE で調整できる =="
reset
mkdir "$LOCK"   # mtime は現在時刻 = 経過 0 秒
run "$E2E" DUTY_LOCK_GRACE=0
check "猶予 0 なら PID 未書き込みでも回収する" "1" "$(logged '停止済みプロセスのロックを回収')"
check "回収後は解放される" "no" "$(lock_exists)"

echo "== 5. 死んだ PID のロックは回収する =="
reset
mkdir "$LOCK"; echo "$DEAD_PID" >"$LOCK/pid"
run "$E2E"
check "終了コード 0" "0" "$?"
check "「ロックを回収」のログに死んだ PID が出る" "1" "$(logged "停止済みプロセスのロックを回収 (pid=$DEAD_PID)")"
check "回収後は解放される" "no" "$(lock_exists)"
check "猶予の判定は PID があるときは働かない" "0" "$(logged 'ロック取得直後')"

echo "== 6. 回収が競合したら降りる（後から書いた1プロセスだけが残る）=="
reset
mkdir "$LOCK"; echo "$DEAD_PID" >"$LOCK/pid"   # 回収経路に入れる（= 所有権の再確認が走る）
run "$E2E_STOLEN"
check "終了コード 0" "0" "$?"
check "「回収が競合」のログが出る" "1" "$(logged 'ロックの回収が競合したためスキップ')"
check "勝者のロックを消さずに降りる" "yes" "$(lock_exists)"
check "勝者の PID がそのまま残る" "$DEAD_PID" "$(cat "$LOCK/pid")"

echo "== 7. 所有者でなくなった場合は EXIT トラップでもロックを消さない =="
# 6 は所有権の再確認（回収経路）で降りるケース。ここは再確認を通り抜けたあとに奪われた場合、
# EXIT トラップの release_lock が他プロセスのロックを巻き添えにしないことを見る。
# 新規取得（回収なし = 再確認をしない経路）で PID を奪わせると、この経路だけを切り出せる
reset
run "$E2E_STOLEN"
check "終了コード 0" "0" "$?"
check "所有者でないのでロックを消さない" "yes" "$(lock_exists)"
check "回収の競合ログは出ない（新規取得の経路）" "0" "$(logged 'ロックの回収が競合')"

echo "== 8. 既存の通知テストが引き続き通る =="
if bash "$SCRIPT_DIR/test-ai-duty-notify.sh" >"$TEST_HOME/notify.out" 2>&1; then
  ok "test-ai-duty-notify.sh が通る"
else
  ng "test-ai-duty-notify.sh が失敗（$(tail -3 "$TEST_HOME/notify.out" | tr '\n' ' ')）"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
