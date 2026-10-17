#!/bin/bash
# ai-duty.sh の仕事14（自動ハンコ・会長決裁 2026-10-17）の検証。
#   - 判定（DUTY_JQ_AUTO_STAMP_LIB の auto_stamp_status）: 24 時間・NG ラベル・ai:hold・stamp:auto・出所・遡及なし・区分
#   - 付け替えの本体（run_auto_stamp）: gh をスタブにして、ラベル → コメントの順で呼ぶこと・付けない Issue に触れないこと
#   - 週次まとめ（auto_stamp_summary_body / is_auto_stamp_summary_due / run_auto_stamp_weekly_summary）
#   - 付け替えの記録コメントが当番マーカー（is_duty_reply）として扱われること、仕事1 の hold 除外
#
# 使い方: bash Scripts/tests/test-ai-duty-auto-stamp.sh
# 仕込み方: DUTY_LIB_ONLY=1 で source し、本物の定義をそのまま評価する（テスト用の写しを持たない）。
# HOME をテスト用の一時ディレクトリに差し替えてから source するので、ログ・記録ファイルはテスト側に閉じる。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ai-duty.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/ai-duty-auto-stamp-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/Library/Logs" "$TEST_HOME/.asobiba-duty"
export HOME="$TEST_HOME"
unset DUTY_AUTO_STAMP_LOG DUTY_AUTO_STAMP_SUMMARY_STATE DUTY_AUTO_STAMP_SINCE DUTY_AUTO_STAMP_WAIT

export DUTY_LIB_ONLY=1
# shellcheck source=/dev/null
. "$TARGET" || { echo "source に失敗"; exit 1; }
[ -n "${DUTY_JQ_AUTO_STAMP_LIB:-}" ] || { echo "DUTY_JQ_AUTO_STAMP_LIB が未定義"; exit 1; }

ACTORS="hiroky1983"
# 基準の時刻: 2026-10-20T00:00:00Z
NOW=$(jq -n '"2026-10-20T00:00:00Z" | fromdateiso8601')

# GraphQL の応答と同じ形の Issue ノードを1件組み立てる。
# 引数: 作成日時 / ラベル(カンマ区切り) / 本文 / 作成者 / タイムライン（"種類|ラベル|日時|操作者" をカンマ区切り）/ マイルストーン
issue_node() {
  local created="$1" labels="$2" body="$3" author="${4:-hiroky1983}" events="${5-}" milestone="${6:-v1.1.13}"
  local jl je e
  jl=$(printf '%s' "$labels" | tr ',' '\n' | jq -R 'select(. != "") | {name: .}' | jq -sc .)
  # 既定のタイムライン: 起票と同時に信頼アカウントが stamp:auto を付けた
  [ -n "${5+x}" ] || events="LabeledEvent|stamp:auto|$created|hiroky1983"
  je='[]'
  if [ -n "$events" ]; then
    je=$(printf '%s' "$events" | tr ',' '\n' | jq -R 'split("|") | {__typename: .[0], label: {name: .[1]}, createdAt: .[2], actor: {login: .[3]}}' | jq -sc .)
  fi
  jq -nc --arg c "$created" --argjson l "$jl" --arg b "$body" --arg a "$author" --argjson e "$je" --arg m "$milestone" \
    '{number: 42, createdAt: $c, author: {login: $a}, body: $b, milestone: {title: $m},
      labels: {nodes: $l}, timelineItems: {nodes: $e}}'
}
status() {
  printf '%s' "$1" | jq -r --arg trusted "$ACTORS" --argjson now "$NOW" --argjson wait "$DUTY_AUTO_STAMP_WAIT" \
    --arg since "$DUTY_AUTO_STAMP_SINCE" "$DUTY_JQ_AUTO_STAMP_LIB"'($trusted | split(",")) as $a | auto_stamp_status($a; $now; $wait; $since)'
}

BODY_BUG='## 現象
ボタンが押せない

自動ハンコの区分: 不具合'
OLD="2026-10-18T12:00:00Z"   # 36 時間前
NEW="2026-10-19T06:00:00Z"   # 18 時間前
BASE="ai:proposed,stamp:auto,bug"

echo "== 1. 構文チェックと既定値 =="
if bash -n "$TARGET"; then ok "bash -n が通る"; else ng "bash -n が失敗"; fi
check "待ち時間の既定は 24 時間" "86400" "$DUTY_AUTO_STAMP_WAIT"
check "遡及しない基準日の既定は 2026-10-17" "2026-10-17T00:00:00Z" "$DUTY_AUTO_STAMP_SINCE"

echo "== 2. 付けるケース =="
check "24 時間経過・stamp:auto・NG 無し・区分ありなら付ける" "ok:不具合の修正" "$(status "$(issue_node "$OLD" "$BASE" "$BODY_BUG")")"
check "ちょうど 24 時間なら付ける" "ok:不具合の修正" "$(status "$(issue_node "2026-10-19T00:00:00Z" "$BASE" "$BODY_BUG")")"
for kv in "使いやすさ=使いやすさ・アクセシビリティ" "英訳=英語の訳の漏れ・誤り" \
          "仕組み=テスト・CI・当番の仕組み・docs の追従" "動作改善=遊び方も見た目も変わらない動作の改善"; do
  check "区分「${kv%%=*}」は固定の表示名になる" "ok:${kv#*=}" \
    "$(status "$(issue_node "$OLD" "$BASE" "自動ハンコの区分: ${kv%%=*}")")"
done
check "全角コロン・箇条書きの区分行も読む" "ok:不具合の修正" "$(status "$(issue_node "$OLD" "$BASE" "- 自動ハンコの区分：不具合")")"

echo "== 3. 24 時間未満は付けない =="
check "18 時間しか経っていなければ付けない" "" "$(status "$(issue_node "$NEW" "$BASE" "$BODY_BUG")")"
check "stamp:auto を後から付けたら、その時刻から 24 時間を数える" "" \
  "$(status "$(issue_node "$OLD" "$BASE" "$BODY_BUG" hiroky1983 "LabeledEvent|stamp:auto|$NEW|hiroky1983")")"

echo "== 4. NG ラベルがあると付けない =="
for lbl in ai:approved ai:in-progress ai:hold blocked ringi:pending risk:sensitive 広告 新ゲーム ops:chairman; do
  check "$lbl があれば付けない" "" "$(status "$(issue_node "$OLD" "$BASE,$lbl" "$BODY_BUG")")"
done
check "企画倉庫のマイルストーンなら付けない" "" \
  "$(status "$(issue_node "$OLD" "$BASE" "$BODY_BUG" hiroky1983 "LabeledEvent|stamp:auto|$OLD|hiroky1983" "企画倉庫")")"

echo "== 5. hold・stamp:auto で止まる =="
check "会長が ai:hold を付けたら止まる" "" "$(status "$(issue_node "$OLD" "$BASE,ai:hold" "$BODY_BUG")")"
check "stamp:auto が無いと付けない" "" "$(status "$(issue_node "$OLD" "ai:proposed,bug" "$BODY_BUG")")"
check "ai:proposed が無いと付けない" "" "$(status "$(issue_node "$OLD" "stamp:auto,bug" "$BODY_BUG")")"
check "会長が stamp:auto を外した（最新が剥がし）なら、ラベルが残っていても付けない" "" \
  "$(status "$(issue_node "$OLD" "$BASE" "$BODY_BUG" hiroky1983 "LabeledEvent|stamp:auto|$OLD|hiroky1983,UnlabeledEvent|stamp:auto|2026-10-18T13:00:00Z|hiroky1983")")"

echo "== 6. 出所・遡及・区分 =="
check "第三者が起票した Issue には付けない" "" "$(status "$(issue_node "$OLD" "$BASE" "$BODY_BUG" someone)")"
check "stamp:auto を付けたのが信頼外なら付けない" "" \
  "$(status "$(issue_node "$OLD" "$BASE" "$BODY_BUG" hiroky1983 "LabeledEvent|stamp:auto|$OLD|someone")")"
check "stamp:auto の付与記録が取れなければ付けない" "" "$(status "$(issue_node "$OLD" "$BASE" "$BODY_BUG" hiroky1983 "")")"
check "基準日より前に起票された Issue には遡らない" "" \
  "$(status "$(issue_node "2026-10-16T12:00:00Z" "$BASE" "$BODY_BUG" hiroky1983 "LabeledEvent|stamp:auto|2026-10-17T12:00:00Z|hiroky1983")")"
check "区分の行が無ければ nokey（付けない）" "nokey" "$(status "$(issue_node "$OLD" "$BASE" "本文だけ")")"
check "区分が表に無い語なら nokey（付けない）" "nokey" "$(status "$(issue_node "$OLD" "$BASE" "自動ハンコの区分: 新機能")")"

echo "== 7. 付け替えの本体（run_auto_stamp）=="
GH_CALLS="$TEST_HOME/gh-calls"
export DUTY_NOW="$NOW"
run_stamp_with() {
  STUB_RESP="$1"; STUB_EDIT_RC="${2:-0}"
  : >"$GH_CALLS"
  (
    gh() {
      printf '%s\n' "$*" >>"$GH_CALLS"
      case "$1 $2" in
        "api graphql") printf '%s' "$STUB_RESP" ;;
        "issue edit") return "$STUB_EDIT_RC" ;;
        "issue comment") return 0 ;;
        *) return 1 ;;
      esac
    }
    run_auto_stamp
  )
}
wrap() { jq -nc --argjson n "[$(IFS=,; echo "$*")]" '{data: {repository: {issues: {nodes: $n}}}}'; }
N_OK=$(issue_node "$OLD" "$BASE" "$BODY_BUG" | jq -c '.number = 101')
N_NEW=$(issue_node "$NEW" "$BASE" "$BODY_BUG" | jq -c '.number = 102')
N_HOLD=$(issue_node "$OLD" "$BASE,ai:hold" "$BODY_BUG" | jq -c '.number = 103')
N_NOKEY=$(issue_node "$OLD" "$BASE" "本文だけ" | jq -c '.number = 104')
rm -f "$DUTY_AUTO_STAMP_LOG"
run_stamp_with "$(wrap "$N_OK" "$N_NEW" "$N_HOLD" "$N_NOKEY")"
check "付けるのは対象の1件だけ（ラベル操作）" "1" "$(grep -c '^issue edit' "$GH_CALLS")"
check "ai:approved を付けて ai:proposed を外す" "1" \
  "$(grep -c '^issue edit 101 -R hiroky1983/game_collection --add-label ai:approved --remove-label ai:proposed$' "$GH_CALLS")"
check "ラベル → コメントの順で呼ぶ" "issue edit 101|issue comment 101" \
  "$(grep -oE '^issue (edit|comment) [0-9]+' "$GH_CALLS" | paste -sd '|' -)"
check "コメントは当番マーカー「自動ハンコ:」で始まり、区分を載せる" "1" \
  "$(grep -c '^issue comment 101 .*--body 自動ハンコ: 起票から 24 時間経過・自動ハンコ（OK 範囲: 不具合の修正）' "$GH_CALLS")"
for n in 102 103 104; do
  check "#${n}（24 時間未満 / hold / 区分なし）には触れない" "0" "$(grep -cE "^issue (edit|comment) $n " "$GH_CALLS")"
done
check "週次まとめ用に記録する" "$NOW	101	不具合の修正" "$(cat "$DUTY_AUTO_STAMP_LOG")"
check "区分なしはログに理由を残す" "1" "$(grep -c '#104 は本文に「自動ハンコの区分' "$LOG")"

rm -f "$DUTY_AUTO_STAMP_LOG"
run_stamp_with "$(wrap "$N_OK")" 1
check "ラベル付け替えに失敗したらコメントしない" "0" "$(grep -c '^issue comment' "$GH_CALLS")"
check "ラベル付け替えに失敗したら記録しない" "0" "$( [ -f "$DUTY_AUTO_STAMP_LOG" ] && wc -l <"$DUTY_AUTO_STAMP_LOG" | tr -d ' ' || echo 0)"

run_stamp_with "not json"
check "応答を解釈できなければ何もしない" "0" "$(grep -c '^issue edit' "$GH_CALLS")"

echo "== 8. 週次まとめ =="
LOGF="$TEST_HOME/stamp.log"
printf '%s\t%s\t%s\n' 1000 7 "不具合の修正" 2000 8 "英語の訳の漏れ・誤り" 3000 'x;rm' "壊れた行" >"$LOGF"
BODY=$(auto_stamp_summary_body "$LOGF" 1500)
check "前回より後の記録だけを載せる" "1" "$(printf '%s\n' "$BODY" | grep -c '^- #')"
check "番号と区分を載せる" "1" "$(printf '%s\n' "$BODY" | grep -c '^- #8（OK 範囲: 英語の訳の漏れ・誤り・')"
check "本文は当番マーカー「自動ハンコ」で始まる" "1" "$(printf '%s\n' "$BODY" | head -1 | grep -c '^自動ハンコ（週次まとめ）: ')"
check "対象が無ければ何も出さない" "" "$(auto_stamp_summary_body "$LOGF" 5000)"
if is_auto_stamp_summary_due 1000 $((1000 + 604800)); then ok "7 日経てば出す"; else ng "7 日経てば出す"; fi
if is_auto_stamp_summary_due 1000 $((1000 + 604799)); then ng "7 日未満なら出さない"; else ok "7 日未満なら出さない"; fi
if is_auto_stamp_summary_due "" 9999999; then ng "前回の記録が無ければ出さない"; else ok "前回の記録が無ければ出さない"; fi

run_summary_with() {
  STUB_WEEKLY="$1"
  : >"$GH_CALLS"
  (
    gh() {
      printf '%s\n' "$*" >>"$GH_CALLS"
      case "$1 $2" in
        "issue list") printf '%s' "$STUB_WEEKLY" ;;
        "issue comment") return 0 ;;
        *) return 1 ;;
      esac
    }
    osascript() { printf 'osascript %s\n' "$*" >>"$GH_CALLS"; }
    run_auto_stamp_weekly_summary
  )
}
printf '%s\t%s\t%s\n' "$((NOW - 3600))" 101 "不具合の修正" >"$DUTY_AUTO_STAMP_LOG"
rm -f "$DUTY_AUTO_STAMP_SUMMARY_STATE"
run_summary_with "2316"
check "初回は基準の時刻を書くだけで出さない" "0" "$(grep -c 'issue comment' "$GH_CALLS")"
check "初回に基準の時刻を書く" "$NOW" "$(cat "$DUTY_AUTO_STAMP_SUMMARY_STATE")"
printf '%s\n' "$((NOW - 604800))" >"$DUTY_AUTO_STAMP_SUMMARY_STATE"
run_summary_with "2316"
check "1 週間経てば最新の週次レポートに1本コメントする" "1" "$(grep -c '^issue comment 2316 ' "$GH_CALLS")"
check "まとめたら時刻を進める" "$NOW" "$(cat "$DUTY_AUTO_STAMP_SUMMARY_STATE")"
run_summary_with "2316"
check "同じ週には2回出さない" "0" "$(grep -c 'issue comment' "$GH_CALLS")"
printf '%s\n' "$((NOW - 604800))" >"$DUTY_AUTO_STAMP_SUMMARY_STATE"
run_summary_with ""
check "週次レポートが無ければ当番の通知に出す" "1" "$(grep -c '^osascript .*#101' "$GH_CALLS")"
printf '%s\n' "$((NOW - 604800))" >"$DUTY_AUTO_STAMP_SUMMARY_STATE"
: >"$DUTY_AUTO_STAMP_LOG"
run_summary_with "2316"
check "自動ハンコが0件の週は何も出さない" "0" "$(grep -cE 'issue comment|osascript' "$GH_CALLS")"

echo "== 9. 当番マーカーと仕事1 の hold 除外 =="
proposed_node=$(jq -nc --arg b "自動ハンコ: 起票から 24 時間経過・自動ハンコ（OK 範囲: 不具合の修正）" \
  '{number: 1, labels: {nodes: [{name: "ai:proposed"}]}, comments: {nodes: [{author: {login: "hiroky1983"}, body: "会長の指示"}, {author: {login: "hiroky1983"}, body: $b}]}}')
check "自動ハンコの記録コメントで仕事8 が発火しない" "false" \
  "$(printf '%s' "$proposed_node" | jq --arg trusted "$ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $a | is_proposed_reply($a)')"
check "仕事1 の集計・候補の2か所が stamp:auto + ai:hold を除外している" "2" \
  "$(grep -c 'and ((\$l | index("stamp:auto")) == null or (\$l | index("ai:hold")) == null)' "$TARGET")"
check "スロット1が通知の収集より前に自動ハンコを呼ぶ" "1" \
  "$(awk '/^  run_auto_stamp$/ { s = NR } /^  collect_notify_targets$/ { if (s && s < NR) print 1 }' "$TARGET")"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
