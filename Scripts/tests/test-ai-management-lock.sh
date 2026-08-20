#!/bin/bash
# ai-management-duty.sh の多重起動防止ロック（Issue #180）の検証。
# ai-duty.sh 側の test-ai-duty-lock.sh（Issue #165）と同じ方式・同じ観点で、
# 経営当番へ横展開した堅牢化が実際に効いているかを見る。
# ロック取得のコードはトップレベルにあり source では取り込めないため、
# 「ロックを取り終えた直後で exit 0 する版」を awk で生成して本物のロジックを通す。
#
# 使い方: bash Scripts/tests/test-ai-management-lock.sh
#
# HOME をテスト用の一時ディレクトリへ差し替えるので、
#   - 自己更新（self_update）は $HOME/.asobiba-mgmt/game_collection/.git が無いため即 return する
#   - ログもテスト側に閉じる
# TMPDIR も差し替えるため LOCK_DIR は会長の実ロックと衝突しない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ai-management-duty.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/ai-mgmt-lock-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/Library/Logs"

LOCK="$TEST_HOME/asobiba-ai-management.lock"   # LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-management.lock"
LOG="$TEST_HOME/Library/Logs/asobiba-ai-management.log"
# macOS の既定の PID 上限は 99998。存在しえない PID を使うことで「死んだプロセス」を決定論的に作る
DEAD_PID=999999

# ロックを取り終えた直後で終わる版（claude も gh も呼ばせない）
E2E="$TEST_HOME/ai-mgmt-lock-e2e.sh"
awk '{ print } /^trap .* EXIT$/ { print "exit 0" }' "$TARGET" >"$E2E"
# PID_FILE を書いた直後に他プロセスが奪った状況を再現する版（回収の競合・所有者以外は消さない）
E2E_STOLEN="$TEST_HOME/ai-mgmt-lock-stolen.sh"
awk -v dead="$DEAD_PID" '
  /^sleep 1$/      { print "echo " dead " >\"$PID_FILE\"" }   # 所有権の確認に入る直前に奪う
  { print }
  /^trap .* EXIT$/ { print "exit 0" }
' "$TARGET" >"$E2E_STOLEN"
# PID を書く直前にロックごと消された状況を再現する版（他プロセスの回収と衝突したケース）。
# リダイレクトが失敗するので、生の stderr を出さずログを残して降りることを見る
E2E_VANISHED="$TEST_HOME/ai-mgmt-lock-vanished.sh"
awk '
  /^if ! write_pid; then$/ { print "rmdir \"$LOCK_DIR\"" }
  { print }
  /^trap .* EXIT$/         { print "exit 0" }
' "$TARGET" >"$E2E_VANISHED"
# 所有権の確認を**通り抜けたあと**に奪われた状況を再現する版。EXIT トラップの release_lock が
# 他プロセスのロックを巻き添えにしないことだけを切り出して見るために使う
E2E_STOLEN_LATE="$TEST_HOME/ai-mgmt-lock-stolen-late.sh"
awk -v dead="$DEAD_PID" '
  { print }
  /^trap .* EXIT$/ { print "echo " dead " >\"$PID_FILE\""; print "exit 0" }
' "$TARGET" >"$E2E_STOLEN_LATE"

run() {  # run <script> [追加の環境変数...] — 生成済みスクリプトを走らせ、終了コードを返す
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
check "確認後に PID を奪う版を生成できた" "1" "$(grep -c "^echo $DEAD_PID >\"\$PID_FILE\"$" "$E2E_STOLEN_LATE")"
check "ロックを消しておく版を生成できた" "1" "$(grep -c '^rmdir "\$LOCK_DIR"$' "$E2E_VANISHED")"
check "release_lock が EXIT トラップから呼ばれる" "1" "$(grep -c '^trap .release_lock. EXIT$' "$TARGET")"
check "ロックの再帰削除はすべて stderr を抑止している" "0" "$(grep -c '^ *rm -rf "\$LOCK_DIR"$' "$TARGET")"

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

echo "== 3. PID 未書き込みのロックを奪わない =="
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

echo "== 4-b. 猶予は MGMT_LOCK_GRACE で調整できる =="
reset
mkdir "$LOCK"   # mtime は現在時刻 = 経過 0 秒
run "$E2E" MGMT_LOCK_GRACE=0
check "猶予 0 なら PID 未書き込みでも回収する" "1" "$(logged '停止済みプロセスのロックを回収')"
check "回収後は解放される" "no" "$(lock_exists)"

echo "== 4-c. MGMT_LOCK_GRACE が非数値・負値なら既定値へ戻す（受け入れ条件1）=="
# `[ "$AGE" -lt "$MGMT_LOCK_GRACE" ]` は非数値だと失敗（= 偽）になるため、検証しないと
# 猶予の判定を素通りして取得直後のロックを回収してしまう（PR #173 の CodeRabbit 指摘の横展開）
for BAD in invalid -5 "30 "; do
  reset
  mkdir "$LOCK"   # 取得直後（PID 未書き込み・経過 0 秒）
  run "$E2E" MGMT_LOCK_GRACE="$BAD"
  check "MGMT_LOCK_GRACE=[$BAD] でも取得直後のロックは残る" "yes" "$(lock_exists)"
  check "MGMT_LOCK_GRACE=[$BAD] は既定値 30 に戻したとログに出る" "1" "$(logged '既定値 30 を使う')"
  check "MGMT_LOCK_GRACE=[$BAD] でロックを回収しない" "0" "$(logged '停止済みプロセスのロックを回収')"
done

echo "== 4-d. mtime が未来（時刻の巻き戻り）でも回収しない（受け入れ条件2）=="
# AGE が負値になると比較が失敗し、正規化が無いと回収する側へ落ちる
reset
mkdir "$LOCK"; touch -t 209901010000 "$LOCK"   # mtime を未来に倒して AGE を負値にする
run "$E2E"
check "終了コード 0" "0" "$?"
check "未来 mtime のロックは残る" "yes" "$(lock_exists)"
check "「経過=不明」として取得直後に倒す" "1" "$(logged 'ロック取得直後（PID 未書き込み・経過=不明秒）')"
check "ロックを回収しない" "0" "$(logged '停止済みプロセスのロックを回収')"

echo "== 5. 死んだ PID のロックは回収する =="
reset
mkdir "$LOCK"; echo "$DEAD_PID" >"$LOCK/pid"
run "$E2E"
check "終了コード 0" "0" "$?"
check "「ロックを回収」のログに死んだ PID が出る" "1" "$(logged "停止済みプロセスのロックを回収 (pid=$DEAD_PID)")"
check "回収後は解放される" "no" "$(lock_exists)"
check "猶予の判定は PID があるときは働かない" "0" "$(logged 'ロック取得直後')"

echo "== 6. 回収経路で所有権を奪われたら降りる（後から書いた1プロセスだけが残る）=="
reset
mkdir "$LOCK"; echo "$DEAD_PID" >"$LOCK/pid"   # 回収経路に入れる
run "$E2E_STOLEN"
check "終了コード 0" "0" "$?"
check "「所有権が他プロセスに移った」のログが出る" "1" "$(logged 'ロックの所有権が他プロセスに移ったためスキップ')"
check "勝者のロックを消さずに降りる" "yes" "$(lock_exists)"
check "勝者の PID がそのまま残る" "$DEAD_PID" "$(cat "$LOCK/pid")"

echo "== 6-b. 新規取得の経路でも所有権を確認する =="
# 「mkdir で新規に取れたのだから競合していない」は成り立たない。回収経路に入ったプロセスの
# `rm -rf` は誰が今ロックを持っていようと消すため、新規取得側のロックもそれで消されうる
reset
run "$E2E_STOLEN"   # mkdir で新規に取れた経路（回収に入らない）
check "終了コード 0" "0" "$?"
check "新規取得でも所有権の喪失を検知して降りる" "1" "$(logged 'ロックの所有権が他プロセスに移ったためスキップ')"
check "勝者のロックを消さずに降りる" "yes" "$(lock_exists)"
check "勝者の PID がそのまま残る" "$DEAD_PID" "$(cat "$LOCK/pid")"

echo "== 6-c. PID を書く直前にロックが消えていたら、stderr を汚さずログを残して降りる（受け入れ条件3）=="
reset
STDERR="$TEST_HOME/vanished.stderr"
run "$E2E_VANISHED" 2>"$STDERR"
check "終了コード 0" "0" "$?"
check "「PID 記録に失敗」のログが出る" "1" "$(logged 'ロックへの PID 記録に失敗')"
check "launchd の stderr を汚さない" "" "$(cat "$STDERR")"
check "所有権の確認まで進まない" "0" "$(logged 'ロックの所有権が他プロセスに移った')"

echo "== 7. 確認を通り抜けたあとに奪われても EXIT トラップでロックを消さない =="
reset
run "$E2E_STOLEN_LATE"
check "終了コード 0" "0" "$?"
check "所有者でないのでロックを消さない" "yes" "$(lock_exists)"
check "確認は通り抜けている（喪失のログは出ない）" "0" "$(logged 'ロックの所有権が他プロセスに移った')"

echo "== 8. 並行起動しても当選は1プロセスだけ =="
# 実際に同時起動させ、ロックを取れた（= trap 行まで到達した）プロセス数を数える。
# 到達したことはログではなく標準出力で数えられるよう、E2E に印を打った版を使う
E2E_MARK="$TEST_HOME/ai-mgmt-lock-mark.sh"
awk '{ print } /^trap .* EXIT$/ { print "echo WON"; print "exit 0" }' "$TARGET" >"$E2E_MARK"
reset
WON_OUT="$TEST_HOME/won.out"
: >"$WON_OUT"
for _ in $(seq 1 20); do
  ( run "$E2E_MARK" >>"$WON_OUT" 2>/dev/null ) &
done
wait
check "同時 20 プロセスでも当選は1つ" "1" "$(grep -c '^WON$' "$WON_OUT" | tr -d ' ')"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
