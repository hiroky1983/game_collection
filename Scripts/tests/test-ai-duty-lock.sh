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
#
# 2並列化（会長指示 2026-09-25）で、ロックは DUTY_MAX_SLOTS 個のスロットに分かれた。1〜7 は1スロットの
# 性質（取得・回収・所有権の確認）を見るため DUTY_MAX_SLOTS=1 で走らせ、9 以降で複数スロット・Issue の確保・
# 孤児回収の除外・シミュレータの持ち主の判定を見る。
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

LOCK="$TEST_HOME/asobiba-ai-duty.lock"   # ai-duty.sh のスロット1（LOCK_BASE="${TMPDIR:-/tmp}/asobiba-ai-duty.lock"）
LOCK2="$LOCK.2"                          # スロット2
CLAIMS="$LOCK.claims"                    # Issue の確保
LOG="$TEST_HOME/Library/Logs/asobiba-ai-duty.log"
# macOS の既定の PID 上限は 99998。存在しえない PID を使うことで「死んだプロセス」を決定論的に作る
DEAD_PID=999999

# ロックを取り終えた直後で終わる版（claude も gh も呼ばせない）
E2E="$TEST_HOME/ai-duty-lock-e2e.sh"
awk '{ print } /^trap .* EXIT$/ { print "exit 0" }' "$TARGET" >"$E2E"
# PID_FILE を書いた直後に他プロセスが奪った状況を再現する版（回収の競合・所有者以外は消さない）
E2E_STOLEN="$TEST_HOME/ai-duty-lock-stolen.sh"
awk -v dead="$DEAD_PID" '
  /^sleep 1$/      { print "echo " dead " >\"$PID_FILE\"" }   # 所有権の確認に入る直前に奪う
  { print }
  /^trap .* EXIT$/ { print "exit 0" }
' "$TARGET" >"$E2E_STOLEN"
# PID を書く直前にロックごと消された状況を再現する版（他プロセスの回収と衝突したケース）。
# リダイレクトが失敗するので、生の stderr を出さずログを残して降りることを見る
E2E_VANISHED="$TEST_HOME/ai-duty-lock-vanished.sh"
awk '
  /^if ! write_pid; then$/ { print "rmdir \"$LOCK_DIR\"" }
  { print }
  /^trap .* EXIT$/         { print "exit 0" }
' "$TARGET" >"$E2E_VANISHED"
# 所有権の確認を**通り抜けたあと**に奪われた状況を再現する版。EXIT トラップの release_lock が
# 他プロセスのロックを巻き添えにしないことだけを切り出して見るために使う
E2E_STOLEN_LATE="$TEST_HOME/ai-duty-lock-stolen-late.sh"
awk -v dead="$DEAD_PID" '
  { print }
  /^trap .* EXIT$/ { print "echo " dead " >\"$PID_FILE\""; print "exit 0" }
' "$TARGET" >"$E2E_STOLEN_LATE"
# ロックを取ったあと DUTY_TEST_HOLD 秒だけ持ち続ける版（複数スロットの同時保持・並行取得を見る）
E2E_HOLD="$TEST_HOME/ai-duty-lock-hold.sh"
awk '{ print } /^trap .* EXIT$/ { print "sleep \"${DUTY_TEST_HOLD:-3}\""; print "exit 0" }' "$TARGET" >"$E2E_HOLD"

run() {  # run [追加の環境変数...] — 生成済みスクリプトを走らせ、終了コードを返す（既定は1スロット）
  local script="$1"; shift
  env HOME="$TEST_HOME" TMPDIR="$TEST_HOME" DUTY_MAX_SLOTS=1 "$@" bash "$script"
}
reset() { rm -rf "$LOCK" "$LOCK2" "$CLAIMS"; : >"$LOG"; }
logged() { grep -c -- "$1" "$LOG" | tr -d ' '; }
lock_exists() { if [ -d "$LOCK" ]; then echo yes; else echo no; fi; }

echo "== 0. 前提 =="
if bash -n "$TARGET"; then ok "bash -n が通る"; else ng "bash -n が失敗"; fi
if grep -q '^exit 0$' "$E2E"; then ok "テスト用スクリプトを生成できた（trap 行が見つかる）"; else ng "テスト用スクリプトの生成に失敗（trap 行が見つからない）"; fi
check "PID を奪う版を生成できた" "1" "$(grep -c "^echo $DEAD_PID >\"\$PID_FILE\"$" "$E2E_STOLEN")"
check "確認後に PID を奪う版を生成できた" "1" "$(grep -c "^echo $DEAD_PID >\"\$PID_FILE\"$" "$E2E_STOLEN_LATE")"
check "ロックを消しておく版を生成できた" "1" "$(grep -c '^rmdir "\$LOCK_DIR"$' "$E2E_VANISHED")"
check "release_lock が EXIT トラップから呼ばれる" "1" "$(grep -c '^trap .*release_lock.* EXIT$' "$TARGET")"
# 行の完全一致にすると後片付けを1つ足すたびに落ちる（#762: cleanup_worktree の追加で実際に落ちていた）。
# 見たいのは「後片付けと通知が release_lock より前に並び、所有権の確認を経ずに走る」ことだけ
check "cleanup_simulators / notify_pending は所有権と無関係に走る" "1" "$(grep -c '^trap .cleanup_simulators;.* notify_pending; release_claim; release_lock. EXIT$' "$TARGET")"
# 所有権の確認を回収経路だけに絞ると二重当選が実在する（新規取得したプロセスのロックが、
# 回収経路のプロセスの `rm -rf` で消される経路。テスト6-b で挙動として押さえる）
check "所有権の確認が経路で条件分岐していない" "0" "$(grep -c 'RECLAIMED' "$TARGET")"

echo "== 1. 通常取得と解放 =="
reset
run "$E2E"
check "終了コード 0" "0" "$?"
check "終了時にロックが解放される" "no" "$(lock_exists)"
check "スキップのログは出ない" "0" "$(logged 'のためスキップ')"

echo "== 1-a. launchd からの起動は本体を切り離してすぐ終わる（2並列化の不具合修正 2026-09-26）=="
# launchd は前回の起動が終わるまで次を起動しない。起動元がすぐ終わり、切り離した本体がロックを取ることを見る
reset
START=$(date +%s)
run "$E2E_HOLD" XPC_SERVICE_NAME=com.asobiba.ai-duty DUTY_DETACHED= DUTY_TEST_HOLD=3
check "起動元は終了コード 0" "0" "$?"
check "起動元は本体の終了を待たない（2秒未満で戻る）" "yes" "$([ $(( $(date +%s) - START )) -lt 2 ] && echo yes || echo no)"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(logged 'スロット1/1 を取得')" = 1 ] && break; sleep 1; done
check "切り離した本体がロックを取る" "1" "$(logged 'スロット1/1 を取得')"
check "本体は別のプロセスグループで動く" "yes" \
  "$(p=$(cat "$LOCK/pid" 2>/dev/null); [ -n "$p" ] && [ "$(ps -o pgid= -p "$p" | tr -d ' ')" = "$p" ] && echo yes || echo no)"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -d "$LOCK" ] || break; sleep 1; done
check "本体の終了後にロックが解放される" "no" "$(lock_exists)"
reset
run "$E2E" XPC_SERVICE_NAME=com.asobiba.ai-duty DUTY_DETACHED=1
check "切り離し済み（DUTY_DETACHED=1）なら同期で走る" "1" "$(logged 'スロット1/1 を取得')"

echo "== 1-b. 呼び出し元の DUTY_SCRATCH_DIR を後片付けで消さない（#762）=="
# 当番セッションの中でこのテストを回すと、環境変数が引き継がれ、実行中の当番の scratch が消えていた
reset
INHERITED_SCRATCH="$TEST_HOME/inherited-scratch"
mkdir -p "$INHERITED_SCRATCH"
run "$E2E" DUTY_SCRATCH_DIR="$INHERITED_SCRATCH"
check "引き継いだ scratch は残る" "yes" "$(if [ -d "$INHERITED_SCRATCH" ]; then echo yes; else echo no; fi)"

echo "== 2. 実行中はスキップ（生きた PID のロックは奪わない）=="
reset
mkdir "$LOCK"; echo $$ >"$LOCK/pid"   # テスト自身の PID = 確実に生きている
run "$E2E"
check "終了コード 0（launchd を騒がせない）" "0" "$?"
check "実行中のロックは残る" "yes" "$(lock_exists)"
check "「前回実行中」のログが出る" "1" "$(logged "前回実行中 (pid=$$)")"
check "「全スロットが使用中」のログが出る" "1" "$(logged '全スロット（1）が使用中のためスキップ')"
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

echo "== 4-c. DUTY_LOCK_GRACE が非数値・負値なら既定値へ戻す（猶予の判定を素通りさせない）=="
# `[ "$AGE" -lt "$DUTY_LOCK_GRACE" ]` は非数値だと失敗（= 偽）になるため、検証しないと
# 猶予の判定を素通りして取得直後のロックを回収してしまう（PR #173 の CodeRabbit 指摘）
for BAD in invalid -5 "30 "; do
  reset
  mkdir "$LOCK"   # 取得直後（PID 未書き込み・経過 0 秒）
  run "$E2E" DUTY_LOCK_GRACE="$BAD"
  check "DUTY_LOCK_GRACE=[$BAD] でも取得直後のロックは残る" "yes" "$(lock_exists)"
  check "DUTY_LOCK_GRACE=[$BAD] は既定値 30 に戻したとログに出る" "1" "$(logged '既定値 30 を使う')"
  check "DUTY_LOCK_GRACE=[$BAD] でロックを回収しない" "0" "$(logged '停止済みプロセスのロックを回収')"
done

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

echo "== 6-b. 新規取得の経路でも所有権を確認する（二重当選を防ぐ本体）=="
# 「mkdir で新規に取れたのだから競合していない」は成り立たない。回収経路に入ったプロセスは
# 猶予の判定を済ませており、その後の `rm -rf` は誰が今ロックを持っていようと消す。
# 新規取得側のロックがそれで消され、確認を省くと回収側と新規取得側の両方が走る
# （40 並行のストレステストで3〜5プロセスが同時に当選することを実測）
reset
run "$E2E_STOLEN"   # mkdir で新規に取れた経路（回収に入らない）
check "終了コード 0" "0" "$?"
check "新規取得でも所有権の喪失を検知して降りる" "1" "$(logged 'ロックの所有権が他プロセスに移ったためスキップ')"
check "勝者のロックを消さずに降りる" "yes" "$(lock_exists)"
check "勝者の PID がそのまま残る" "$DEAD_PID" "$(cat "$LOCK/pid")"

echo "== 6-c. PID を書く直前にロックが消えていたら、stderr を汚さずログを残して降りる =="
reset
STDERR="$TEST_HOME/vanished.stderr"
run "$E2E_VANISHED" 2>"$STDERR"
check "終了コード 0" "0" "$?"
check "「PID 記録に失敗」のログが出る" "1" "$(logged 'ロックへの PID 記録に失敗')"
check "launchd の stderr を汚さない" "" "$(cat "$STDERR")"
check "所有権の確認まで進まない" "0" "$(logged 'ロックの所有権が他プロセスに移った')"

echo "== 7. 確認を通り抜けたあとに奪われても EXIT トラップでロックを消さない =="
# 6 / 6-b は所有権の確認で降りるケース。ここは確認を通り抜けたあとに奪われた場合、
# EXIT トラップの release_lock が他プロセスのロックを巻き添えにしないことだけを見る
reset
run "$E2E_STOLEN_LATE"
check "終了コード 0" "0" "$?"
check "所有者でないのでロックを消さない" "yes" "$(lock_exists)"
check "確認は通り抜けている（喪失のログは出ない）" "0" "$(logged 'ロックの所有権が他プロセスに移った')"

echo "== 9. 複数スロット（2並列化 2026-09-25）=="
# 9-a: スロット1が実行中なら、次の起動はスロット2を取って走る（スロット1には触れない）
reset
mkdir "$LOCK"; echo $$ >"$LOCK/pid"
run "$E2E" DUTY_MAX_SLOTS=2
check "終了コード 0" "0" "$?"
check "スロット2を取得する" "1" "$(logged 'スロット2/2 を取得')"
check "スロット1のロックは残る" "yes" "$(lock_exists)"
check "スロット1の PID は書き換わらない" "$$" "$(cat "$LOCK/pid")"
check "スロット2は終了時に解放される" "no" "$(if [ -d "$LOCK2" ]; then echo yes; else echo no; fi)"
check "スキップのログは出ない" "0" "$(logged 'のためスキップ')"

# 9-b: 2つとも実行中なら3つ目は走らない
reset
mkdir "$LOCK" "$LOCK2"; echo $$ >"$LOCK/pid"; echo $$ >"$LOCK2/pid"
run "$E2E" DUTY_MAX_SLOTS=2
check "終了コード 0" "0" "$?"
check "「全スロット（2）が使用中」のログが出る" "1" "$(logged '全スロット（2）が使用中のためスキップ')"
check "どのスロットも取得しない" "0" "$(logged 'を取得')"
check "スロット1の PID は書き換わらない" "$$" "$(cat "$LOCK/pid")"
check "スロット2の PID は書き換わらない" "$$" "$(cat "$LOCK2/pid")"

# 9-c: スロット2だけが死んだ当番のロックなら回収して走る。スロット2が実行中でスロット1が空いていれば1を取る
reset
mkdir "$LOCK" "$LOCK2"; echo $$ >"$LOCK/pid"; echo "$DEAD_PID" >"$LOCK2/pid"
run "$E2E" DUTY_MAX_SLOTS=2
check "死んだスロット2を回収する" "1" "$(logged "スロット2: 停止済みプロセスのロックを回収 (pid=$DEAD_PID)")"
check "回収したスロット2で走る" "1" "$(logged 'スロット2/2 を取得')"
reset
mkdir "$LOCK2"; echo $$ >"$LOCK2/pid"
run "$E2E" DUTY_MAX_SLOTS=2
check "スロット2が実行中でも空いたスロット1を取る" "1" "$(logged 'スロット1/2 を取得')"
check "スロット2のロックは残る" "$$" "$(cat "$LOCK2/pid")"

# 9-d: スロット2の取得直後（PID 未書き込み）も1スロット時と同じく奪わない
reset
mkdir "$LOCK" "$LOCK2"; echo $$ >"$LOCK/pid"
run "$E2E" DUTY_MAX_SLOTS=2
check "取得直後のスロット2は奪わない" "1" "$(logged 'スロット2: ロック取得直後')"
check "スキップする" "1" "$(logged '全スロット（2）が使用中のためスキップ')"
if [ -f "$LOCK2/pid" ]; then ng "取得中のスロット2に PID を書き込んでしまった"; else ok "取得中のスロット2には触れない"; fi

# 9-e: 並行起動しても、同時に走るのはスロット数ちょうど（2）だけ。所有権の確認が各スロットで効くことを見る
reset
for i in 1 2 3 4 5 6 7 8 9 10; do
  env HOME="$TEST_HOME" TMPDIR="$TEST_HOME" DUTY_MAX_SLOTS=2 DUTY_TEST_HOLD=4 bash "$E2E_HOLD" &
done
wait
check "10 並行で取得できたのは2つだけ" "2" "$(logged 'を取得')"
check "スロット1の取得は1つだけ" "1" "$(logged 'スロット1/2 を取得')"
check "スロット2の取得は1つだけ" "1" "$(logged 'スロット2/2 を取得')"
check "残りの8つは降りる" "8" "$(grep -cE '全スロット（2）が使用中のためスキップ|ロックの所有権が他プロセスに移ったためスキップ|ロックへの PID 記録に失敗' "$LOG" | tr -d ' ')"
check "終了後はどちらのロックも残らない" "no no" "$(lock_exists) $(if [ -d "$LOCK2" ]; then echo yes; else echo no; fi)"

# 9-f: DUTY_MAX_SLOTS が不正なら既定値 2 に戻す（0 だと当番が永久に止まる）
for BAD in 0 abc "" -1; do
  reset
  mkdir "$LOCK"; echo $$ >"$LOCK/pid"
  run "$E2E" DUTY_MAX_SLOTS="$BAD"
  check "DUTY_MAX_SLOTS=[$BAD] は既定値 2 に戻る（スロット2を取る）" "1" "$(logged 'スロット2/2 を取得')"
done

echo "== 10. Issue の確保（同じ Issue への二重着手を防ぐ）=="
# ロック取得より後ろのコードは E2E では届かないため、関数だけを読み込んで確かめる
sleep 60 &
LIVE_PID=$!
lib() {  # lib <シェルコード> — テスト用の TMPDIR で関数定義だけを読み込み、コードを評価する
  env HOME="$TEST_HOME" TMPDIR="$TEST_HOME" DUTY_LIB_ONLY=1 LIVE_PID="$LIVE_PID" DEAD_PID="$DEAD_PID" \
    bash -c '. "$1" || exit 99; eval "$2"' _ "$TARGET" "$1"
}
reset
check "空きの Issue は確保できる" "0" "$(lib 'claim_issue 10; echo $?')"
reset
mkdir -p "$CLAIMS/10"; echo "$LIVE_PID" >"$CLAIMS/10/pid"
check "生きた他の当番が確保中の Issue は取らない" "1" "$(lib 'claim_issue 10; echo $?')"
check "確保した当番の PID はそのまま" "$LIVE_PID" "$(cat "$CLAIMS/10/pid")"
reset
mkdir -p "$CLAIMS/10"; echo "$DEAD_PID" >"$CLAIMS/10/pid"
check "死んだ当番の確保は回収する" "0" "$(lib 'claim_issue 10; echo $?')"
reset
mkdir -p "$CLAIMS/10"
check "PID 未書き込みの確保（直後）は取らない" "1" "$(lib 'claim_issue 10; echo $?')"
reset
mkdir -p "$CLAIMS/10"; touch -t 202001010000 "$CLAIMS/10"
check "猶予を超えた PID 未書き込みの確保は回収する" "0" "$(lib 'claim_issue 10; echo $?')"

reset
mkdir -p "$CLAIMS/10"; echo "$LIVE_PID" >"$CLAIMS/10/pid"
check "先頭の候補が他スロットに確保されていれば次の候補を取る" "11 true" \
  "$(lib 'claim_next_issue "10 false
11 true
12 false" && echo "$DUTY_ISSUE $DUTY_ISSUE_FABLE"')"
reset
mkdir -p "$CLAIMS/10"; echo "$LIVE_PID" >"$CLAIMS/10/pid"
check "候補が全部確保済みなら取らない" "1 []" "$(lib 'claim_next_issue "10 false"; echo "$? [$DUTY_ISSUE]"')"
reset
check "候補が空なら取らない" "1" "$(lib 'claim_next_issue ""; echo $?')"

# 同じ候補一覧を2つの当番が同時に確保しても、同じ Issue は取らない（mkdir の原子性 + 所有権の確認）
reset
OUT1="$TEST_HOME/claim1.out"; OUT2="$TEST_HOME/claim2.out"
lib 'claim_next_issue "20 false
21 false" && echo "$DUTY_ISSUE"; sleep 2' >"$OUT1" &
C1=$!
lib 'claim_next_issue "20 false
21 false" && echo "$DUTY_ISSUE"; sleep 2' >"$OUT2" &
C2=$!
wait "$C1" "$C2"
check "同時に確保しても別々の Issue になる" "20 21" "$(cat "$OUT1" "$OUT2" | sort -n | tr '\n' ' ' | sed 's/ $//')"

# 同じ1件を2つの当番が同時に確保しようとしたら、勝つのはちょうど1つ（5回繰り返して偶然の通過を避ける）
WINS_ALL=""
for round in 1 2 3 4 5; do
  reset
  lib 'claim_issue 50 && echo win; sleep 2' >"$OUT1" &
  C1=$!
  lib 'claim_issue 50 && echo win; sleep 2' >"$OUT2" &
  C2=$!
  wait "$C1" "$C2"
  WINS_ALL="$WINS_ALL $(cat "$OUT1" "$OUT2" | grep -c win)"
done
check "同じ Issue の同時確保は毎回ちょうど1つだけが勝つ" " 1 1 1 1 1" "$WINS_ALL"
reset
check "確保にはスロット番号も残る" "2" "$(lib 'DUTY_SLOT=2; claim_issue 51 && cat "$CLAIMS_DIR/51/slot"')"

reset
mkdir -p "$CLAIMS/30" "$CLAIMS/31" "$CLAIMS/32"
echo "$LIVE_PID" >"$CLAIMS/30/pid"; echo "$DEAD_PID" >"$CLAIMS/31/pid"
check "他スロットの確保は生きている当番の分だけ数える" "30" "$(lib 'other_claimed_issues')"
check "自分の確保は他スロットの分に数えない" "" "$(lib 'mkdir -p "$CLAIMS_DIR/33"; echo $$ >"$CLAIMS_DIR/33/pid"; rm -rf "$CLAIMS_DIR/30"; other_claimed_issues')"

reset
check "release_claim は自分の確保だけを放す" "no" \
  "$(lib 'claim_issue 40; DUTY_ISSUE=40; release_claim; [ -d "$CLAIMS_DIR/40" ] && echo yes || echo no')"
mkdir -p "$CLAIMS/41"; echo "$LIVE_PID" >"$CLAIMS/41/pid"
check "release_claim は奪われた確保（他の当番の PID）を消さない" "yes" \
  "$(lib 'DUTY_ISSUE=41; release_claim; [ -d "$CLAIMS_DIR/41" ] && echo yes || echo no')"

# 重い Issue（duty:heavy）は同時に1本まで（会長指示 2026-09-26）
reset
mkdir -p "$CLAIMS/60"; echo "$LIVE_PID" >"$CLAIMS/60/pid"
check "他の当番が重い Issue を作業中なら、重い候補を飛ばして軽い候補を取る" "62" \
  "$(lib 'DUTY_HEAVY_ISSUES="60 61"; claim_next_issue "61 false true
62 false false" && echo "$DUTY_ISSUE"')"
check "飛ばした重い候補は確保されずに残らない" "no" "$([ -d "$CLAIMS/61" ] && echo yes || echo no)"
reset
mkdir -p "$CLAIMS/60"; echo "$LIVE_PID" >"$CLAIMS/60/pid"
check "他の当番が軽い Issue なら重い候補も取れる" "61" \
  "$(lib 'DUTY_HEAVY_ISSUES="61"; claim_next_issue "61 false true
62 false false" && echo "$DUTY_ISSUE"')"
reset
mkdir -p "$CLAIMS/60"; echo "$DEAD_PID" >"$CLAIMS/60/pid"
check "重い Issue を抱えた当番が死んでいれば重い候補を取れる" "61" \
  "$(lib 'DUTY_HEAVY_ISSUES="60 61"; claim_next_issue "61 false true" && echo "$DUTY_ISSUE"')"
reset
mkdir -p "$CLAIMS/60"; echo "$LIVE_PID" >"$CLAIMS/60/pid"
check "重い候補しか無く他の当番が重い Issue を作業中なら何も取らない" "1 []" \
  "$(lib 'DUTY_HEAVY_ISSUES="60 61"; claim_next_issue "61 false true"; echo "$? [$DUTY_ISSUE]"')"
check "3列目の無い旧形式の候補は軽い Issue として扱う" "63 false" \
  "$(lib 'DUTY_HEAVY_ISSUES="60"; claim_next_issue "63 false" && echo "$DUTY_ISSUE $DUTY_ISSUE_FABLE"')"
reset
mkdir -p "$CLAIMS/60"; echo "$LIVE_PID" >"$CLAIMS/60/pid"
check "重い一覧を取れなかった回は、他の当番の作業中なら重い候補を取らない（安全側）" "62" \
  "$(lib 'DUTY_HEAVY_UNKNOWN=1; claim_next_issue "61 false true
62 false false" && echo "$DUTY_ISSUE"')"
reset
check "重い一覧を取れなくても、他の当番がいなければ重い候補を取る" "61" \
  "$(lib 'DUTY_HEAVY_UNKNOWN=1; claim_next_issue "61 false true" && echo "$DUTY_ISSUE"')"
# 確保の直後に他の当番の重い確保が現れた（同時確保の）場合は降りて確保を消す
reset
check "重い確保が同時に重なったら降りて確保を消す" "1 [] no" \
  "$(lib 'DUTY_HEAVY_ISSUES="60 61"
claim_issue() { mkdir -p "$CLAIMS_DIR/$1" "$CLAIMS_DIR/60"; echo $$ >"$CLAIMS_DIR/$1/pid"; echo "$LIVE_PID" >"$CLAIMS_DIR/60/pid"; return 0; }
claim_next_issue "61 false true"; echo "$? [$DUTY_ISSUE] $([ -d "$CLAIMS_DIR/61" ] && echo yes || echo no)"')"

reset
mkdir "$LOCK" "$LOCK2" "$LOCK.3"
echo "$LIVE_PID" >"$LOCK/pid"; echo "$DEAD_PID" >"$LOCK2/pid"; echo "$LIVE_PID" >"$LOCK.3/pid"
check "生きている他スロットだけを列挙する（上限を超えた番号も見る）" "$LOCK $LOCK.3" \
  "$(lib 'other_live_slot_dirs' | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$LOCK.3"

echo "== 11. 孤児回収は他スロットが確保中の Issue を除く =="
OLD="2026-01-01T00:00:00Z"
ORPHAN_JSON='[{"number":7,"updatedAt":"'"$OLD"'","labels":[{"name":"ai:approved"},{"name":"ai:in-progress"}]},{"number":8,"updatedAt":"'"$OLD"'","labels":[{"name":"ai:approved"},{"name":"ai:in-progress"}]}]'
check "確保中でなければ両方数える" "2" "$(lib "count_orphans '$ORPHAN_JSON' 1800 '[]' '[]'")"
check "他スロットが確保中の #8 は数えない" "1" "$(lib "count_orphans '$ORPHAN_JSON' 1800 '[]' '[8]'")"
check "4つ目の引数を省略すると従来どおり" "2" "$(lib "count_orphans '$ORPHAN_JSON' 1800 '[]'")"
check "番号の並びを JSON 配列にする" "[8,12]" "$(lib 'numbers_to_json "8 x 12"')"
check "空なら空の配列" "[]" "$(lib 'numbers_to_json ""')"
BUSY_LIB=$(lib 'printf "%s" "$DUTY_JQ_BUSY_LIB"')
busy_count() { printf '%s' "$1" | jq --argjson busy "$2" "$BUSY_LIB"'[.[] | select(linked_to_busy($busy) | not)] | length'; }
check "他スロットの Issue を Closes する PR は数えない（GraphQL の形）" "1" \
  "$(busy_count '[{"closingIssuesReferences":{"nodes":[{"number":8}]}},{"closingIssuesReferences":{"nodes":[]}}]' '[8]')"
check "他スロットの Issue を Closes する PR は数えない（gh pr list の形）" "1" \
  "$(busy_count '[{"closingIssuesReferences":[{"number":8}]},{"closingIssuesReferences":[{"number":9}]}]' '[8]')"
check "他スロットが無ければ全部数える" "2" \
  "$(busy_count '[{"closingIssuesReferences":[{"number":8}]},{"closingIssuesReferences":[]}]' '[]')"

echo "== 12. シミュレータの後片付けは他スロットの分を落とさない =="
# 引数: 起動中 / 自分の実行前 / 自分の記録 / 他スロットの記録 / 他スロットの実行前（1スロット1行・行頭 ":"）
sims() { lib "sims_to_shutdown '$1' '$2' '$3' '$4' '$5'" | tr '\n' ' ' | sed 's/ $//'; }
check "他スロットが無ければ従来どおり差分を落とす" "B" "$(sims "A B" "A" "" "" "")"
check "他スロットの実行前から起動していたものは落とす（他スロットのものではない）" "B" "$(sims "A B" "A" "" "" ":A B")"
check "他スロットの実行中に起動された記録なしのものは残す（そのスロットに委ねる）" "" "$(sims "A B" "A" "" "" ":A")"
check "他スロットの実行前一覧が空でも委ねる" "" "$(sims "B" "" "" "" ":")"
check "自分が記録したものは他スロットの実行中でも落とす" "B" "$(sims "A B" "A" "B" "" ":A")"
check "他スロットが記録したものは落とさない" "" "$(sims "A B" "A" "" "B" ":A B")"
check "自分の実行前から起動していたものは記録があっても落とさない" "" "$(sims "A" "A" "A" "" "")"
check "複数の他スロットのどれか1つでも実行前に無ければ委ねる" "" "$(sims "A B" "A" "" "" ":A B
:A")"
echo "== 13. 通し実行: スロット2は他スロットが確保中の Issue を飛ばし、Issue が無ければ何もしない =="
# 本物の本体を「起動モデルを決めた直後」まで走らせる。gh は偽物（ai:approved の一覧だけを返し、
# --jq は本物の jq で評価する）。ai-duty.sh は PATH の先頭を $HOME/.local/bin に固定するのでそこへ置く
mkdir -p "$TEST_HOME/.local/bin"
cat >"$TEST_HOME/.local/bin/gh" <<'MOCK'
#!/bin/bash
[ "${1:-}" = "auth" ] && exit 0
label=""; filter="."
while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="$2"; shift 2 ;;
    --jq) filter="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$label" in
  ai:approved) data="${MOCK_GH_APPROVED:-[]}" ;;
  *)           data="[]" ;;
esac
printf '%s' "$data" | jq -r "$filter"
MOCK
printf '#!/bin/bash\nexit 0\n' >"$TEST_HOME/.local/bin/osascript"
chmod +x "$TEST_HOME/.local/bin/gh" "$TEST_HOME/.local/bin/osascript"
E2E_MAIN="$TEST_HOME/ai-duty-main.sh"
awk '{ print } /^export DUTY_MODEL$/ { print "exit 0" }' "$TARGET" >"$E2E_MAIN"
check "起動モデルを決めた直後で止める版を生成できた" "1" "$(grep -c '^exit 0$' "$E2E_MAIN")"
APPROVED_JSON='[{"number":11,"labels":[{"name":"ai:approved"},{"name":"model:fable"}],"milestone":{"title":"v1.1.7"}},
{"number":10,"labels":[{"name":"ai:approved"}],"milestone":{"title":"v1.1.7"}},
{"number":5,"labels":[{"name":"ai:approved"}],"milestone":{"title":"v1.1.8"}},
{"number":3,"labels":[{"name":"ai:approved"},{"name":"ai:in-progress"}],"milestone":{"title":"v1.1.7"}}]'

reset
mkdir "$LOCK"; echo "$LIVE_PID" >"$LOCK/pid"
mkdir -p "$CLAIMS/10"; echo "$LIVE_PID" >"$CLAIMS/10/pid"   # スロット1の当番が #10 を確保中
run "$E2E_MAIN" DUTY_MAX_SLOTS=2 MOCK_GH_APPROVED="$APPROVED_JSON"
check "スロット2で走る" "1" "$(logged 'スロット2/2 を取得')"
check "スロット1が確保中の #10 を飛ばし、版 → 番号の順で次の #11 を確保する" "1" "$(logged 'Issue #11 を確保')"
check "終了時に自分の確保（#11）を放す" "no" "$(if [ -d "$CLAIMS/11" ]; then echo yes; else echo no; fi)"
check "他スロットの確保（#10）は残す" "$LIVE_PID" "$(cat "$CLAIMS/10/pid")"

reset
mkdir "$LOCK"; echo "$LIVE_PID" >"$LOCK/pid"
mkdir -p "$CLAIMS/10" "$CLAIMS/11" "$CLAIMS/5"
echo "$LIVE_PID" >"$CLAIMS/10/pid"; echo "$LIVE_PID" >"$CLAIMS/11/pid"; echo "$LIVE_PID" >"$CLAIMS/5/pid"
run "$E2E_MAIN" DUTY_MAX_SLOTS=2 MOCK_GH_APPROVED="$APPROVED_JSON"
check "候補が全部確保済みならスロット2は何もせず終わる" "1" "$(logged 'スロット2: 着手できる Issue が無いため終了')"
check "起動モデルの決定まで進まない（claude を起動しない）" "0" "$(logged 'を確保')"

reset
run "$E2E_MAIN" DUTY_MAX_SLOTS=2 MOCK_GH_APPROVED="$APPROVED_JSON"
check "空いていればスロット1が先頭の #10 を確保する" "1" "$(logged 'Issue #10 を確保')"
check "スロット1は取得できた（スロット2は使わない）" "1" "$(logged 'スロット1/2 を取得')"

kill "$LIVE_PID" 2>/dev/null
wait "$LIVE_PID" 2>/dev/null

echo "== 8. 既存の通知テストが引き続き通る =="
if bash "$SCRIPT_DIR/test-ai-duty-notify.sh" >"$TEST_HOME/notify.out" 2>&1; then
  ok "test-ai-duty-notify.sh が通る"
else
  ng "test-ai-duty-notify.sh が失敗（$(tail -3 "$TEST_HOME/notify.out" | tr '\n' ' ')）"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
