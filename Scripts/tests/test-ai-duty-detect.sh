#!/bin/bash
# ai-duty.sh の「会長の書き込み」検知（仕事5: 決裁着信 / 仕事8: 企画議論着信）の検証。
#
# 当番(AI)・経営企画室・会長はすべて同じ hiroky1983 トークンで投稿するため、この3者を分けるのは
# 本文のマーカーだけである。マーカーの取りこぼしはそのまま毎時の空振り起動になる（#120・#168）ので、
# 判定そのものをテストする。
#
# 使い方: bash Scripts/tests/test-ai-duty-detect.sh
# 仕込み方: ai-duty.sh の判定は DUTY_JQ_COMMENT_LIB（jq の関数定義）に切り出してあり、
# DUTY_LIB_ONLY=1 で source すると本物の定義をそのまま評価できる（テスト用の写しを持たない）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ai-duty.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

export DUTY_LIB_ONLY=1
# shellcheck source=/dev/null
. "$TARGET" || { echo "source に失敗"; exit 1; }
[ -n "${DUTY_JQ_COMMENT_LIB:-}" ] || { echo "DUTY_JQ_COMMENT_LIB が未定義"; exit 1; }

ACTORS="${DUTY_TRUSTED_ACTORS:-hiroky1983}"

# GraphQL の応答と同じ形の Issue ノードを1件組み立てる。
# 引数: ラベル(カンマ区切り) と、"author=本文" の並び（古い順）
node() {
  local labels="$1"; shift
  local jq_labels jq_comments c
  jq_labels=$(printf '%s' "$labels" | tr ',' '\n' | jq -R '{name: .}' | jq -sc .)
  jq_comments='[]'
  for c in "$@"; do
    jq_comments=$(printf '%s' "$jq_comments" \
      | jq -c --arg a "${c%%=*}" --arg b "${c#*=}" '. + [{author: {login: $a}, body: $b}]')
  done
  jq -nc --argjson l "$jq_labels" --argjson c "$jq_comments" \
    '{number: 1, labels: {nodes: $l}, comments: {nodes: $c}}'
}

# 仕事5 / 仕事8 / 仕事11 の実際の判定（ai-duty.sh の呼び出し側と同じ式）を1ノードに適用する
ringi()    { printf '%s' "$1" | jq --arg trusted "$ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $a | is_ringi_reply($a)'; }
proposed() { printf '%s' "$1" | jq --arg trusted "$ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $a | is_proposed_reply($a)'; }
blocked()  { printf '%s' "$1" | jq --arg trusted "$ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $a | is_blocked_reply($a)'; }

RINGI_THREAD='## 【要決裁】当番の権限
**サマリ**: …'
MGMT_TRIAGE='<!-- ai-management-triage -->
## 経営企画室: 優先度分析（2026-08-19）'
MGMT_REMINDER='<!-- ai-management-reminder -->
## 経営企画室リマインド: 決裁が4日滞留しています'
MGMT_RESEARCH='<!-- ai-management-research -->
## 経営企画室: 競合調査'
CHAIRMAN='Aで'

echo "== 1. 構文チェック =="
if bash -n "$TARGET"; then ok "bash -n が通る"; else ng "bash -n が失敗"; fi

echo "== 2. 仕事5（決裁着信）: 発火すべきケース =="
check "会長の決裁コメントが最後なら発火する" "true" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=$CHAIRMAN")")"
check "経営企画室コメントの手前の会長の決裁は隠れない（除外が着信を潰さない）" "true" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=$CHAIRMAN" "hiroky1983=$MGMT_REMINDER")")"

echo "== 3. 仕事5: 発火してはいけないケース =="
check "最後が決裁スレッドなら発火しない" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD")")"
check "最後が決裁反映の記録なら発火しない" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=決裁反映: 承認のため着手します")")"
# #168: 本体の回帰。経営企画室（日次）が1本置くたびに毎時の空振り起動が発生していた
check "最後が経営企画室のトリアージなら発火しない（#168）" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=$MGMT_TRIAGE")")"
check "最後が経営企画室のリマインドなら発火しない（#168）" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=$MGMT_REMINDER")")"
check "最後が経営企画室の調査結果なら発火しない（#168）" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=$MGMT_RESEARCH")")"
check "経営企画室が2本続いても発火しない" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=$MGMT_TRIAGE" "hiroky1983=$MGMT_REMINDER")")"
check "許可リスト外(coderabbitai)の最終コメントは無視する（#68）" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "coderabbitai=自動プランを作成しました")")"
check "コメントが1件も無ければ発火しない" "false" \
  "$(ringi "$(node "ringi:pending")")"

echo "== 4. 仕事8（企画議論着信）: 発火すべきケース =="
check "未承認 ai:proposed に会長コメントが付いたら発火する" "true" \
  "$(proposed "$(node "ai:proposed" "hiroky1983=この案はどう進める？")")"
check "経営企画室コメントの手前の会長コメントは隠れない" "true" \
  "$(proposed "$(node "ai:proposed" "hiroky1983=この案はどう進める？" "hiroky1983=$MGMT_TRIAGE")")"

echo "== 5. 仕事8: 発火してはいけないケース =="
check "最後が経営企画室のトリアージなら発火しない（#168）" "false" \
  "$(proposed "$(node "ai:proposed" "hiroky1983=$MGMT_TRIAGE")")"
check "当番の応答（企画議論 接頭辞）なら発火しない（#120）" "false" \
  "$(proposed "$(node "ai:proposed" "hiroky1983=質問です" "hiroky1983=企画議論（経営企画室）: 回答します")")"
check "最後が決裁スレッドなら発火しない" "false" \
  "$(proposed "$(node "ai:proposed" "hiroky1983=$RINGI_THREAD")")"
check "承認済み(ai:approved)は対象外" "false" \
  "$(proposed "$(node "ai:proposed,ai:approved" "hiroky1983=着手して")")"
check "着手中(ai:in-progress)は対象外" "false" \
  "$(proposed "$(node "ai:proposed,ai:in-progress" "hiroky1983=着手して")")"
check "blocked は対象外" "false" \
  "$(proposed "$(node "ai:proposed,blocked" "hiroky1983=待ち")")"
check "コメントが1件も無ければ発火しない" "false" \
  "$(proposed "$(node "ai:proposed")")"

echo "== 6. 仕事11（blocked 解除確認）: 発火すべきケース =="
check "会長の新規コメントが最後なら発火する" "true" \
  "$(blocked "$(node "blocked" "hiroky1983=着手見送り: 着手条件が未達" "hiroky1983=done")")"
check "経営企画室コメントの手前の会長コメントは隠れない（除外が着信を潰さない）" "true" \
  "$(blocked "$(node "blocked" "hiroky1983=done" "hiroky1983=$MGMT_TRIAGE")")"

echo "== 7. 仕事11: 発火してはいけないケース =="
check "最後が当番の解除確認応答なら発火しない" "false" \
  "$(blocked "$(node "blocked" "hiroky1983=done" "hiroky1983=解除確認: まだ条件未達")")"
check "解除確認応答の後に経営企画室のコメントが挟まっても発火しない（#168 と同じ除外）" "false" \
  "$(blocked "$(node "blocked" "hiroky1983=解除確認: まだ条件未達" "hiroky1983=$MGMT_TRIAGE")")"
check "許可リスト外(coderabbitai)の最終コメントは無視する" "false" \
  "$(blocked "$(node "blocked" "coderabbitai=何かのコメント")")"
check "コメントが1件も無ければ発火しない" "false" \
  "$(blocked "$(node "blocked")")"

echo "== 8. 呼び出し側が共通定義を使っている（判定の写しを作っていない）=="
USES=$(grep -c 'DUTY_JQ_COMMENT_LIB"' "$TARGET")
check "仕事5・仕事8・仕事11 の3箇所が DUTY_JQ_COMMENT_LIB を渡している" "3" "$USES"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
