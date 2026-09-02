#!/bin/bash
# ai-duty.sh の「会長の書き込み」検知（仕事5: 決裁着信 / 仕事8: 企画議論着信 / 仕事11: blocked 解除確認 /
# 仕事12: ハンコによる決裁）の検証。
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
# CodeRabbit指摘: 当番自身が着手見送り時に投稿する「着手見送り:」コメント（1-d-2記載の定型文）を
# 会長の新規コメントと誤認すると、blockedを付けた直後に仕事11が不要に発火する
check "最後が当番自身の「着手見送り」コメントなら発火しない（誤検知防止）" "false" \
  "$(blocked "$(node "blocked" "hiroky1983=着手見送り: 着手条件 xxx が未達（根拠）。解除条件: yyy")")"
# #386: ai:proposed + blocked の Issue では規程 1-e（企画議論）と 2-b（解除確認）が競合し、
# どちらの接頭辞を選んでも別の検知が鳴っていた。#184 が実際にこれで毎時空振りしていた。
check "最後が当番の「企画議論」応答なら発火しない（#386・#184）" "false" \
  "$(blocked "$(node "ai:proposed,blocked" "hiroky1983=1.1.3のUI改修を終えてからやりましょう" "hiroky1983=企画議論（経営企画室）: 承知しました。blocked を付けました")")"
check "最後が当番の決裁スレッドなら発火しない（#386）" "false" \
  "$(blocked "$(node "blocked" "hiroky1983=$RINGI_THREAD")")"

# #386: 当番マーカーの集合を is_duty_reply に集約したため、3つの判定がすべて同じ集合を見る。
# どれか1つが取りこぼすと、その接頭辞で応答した Issue が恒久的に空振りし続ける。
echo "== 7-b. 当番マーカーの集合が仕事5・8・11 で揃っている（#386）=="
# "表示名=本文" の形で持つ（cut -c はバイト単位で、日本語を途中で割ると表示が壊れる）
for entry in "企画議論=企画議論（経営企画室）: 回答します" \
             "解除確認=解除確認: まだ条件未達" \
             "着手見送り=着手見送り: 着手条件 xxx が未達" \
             "決裁スレッド=$RINGI_THREAD" \
             "決裁反映=決裁反映: 承認のため着手します"; do
  label="${entry%%=*}"
  prefix="${entry#*=}"
  check "仕事5 が「${label}…」で発火しない" "false" \
    "$(ringi "$(node "ringi:pending" "hiroky1983=会長の指示" "hiroky1983=$prefix")")"
  check "仕事8 が「${label}…」で発火しない" "false" \
    "$(proposed "$(node "ai:proposed" "hiroky1983=会長の指示" "hiroky1983=$prefix")")"
  check "仕事11 が「${label}…」で発火しない" "false" \
    "$(blocked "$(node "blocked" "hiroky1983=会長の指示" "hiroky1983=$prefix")")"
done
# PR #387 の CodeRabbit 指摘: マーカーは記録形式（先頭一致）で判定する。contains だと会長が
# 語を引用しただけのコメントを当番の応答と誤認し、決裁着信・解除確認をまるごと取りこぼす。
echo "== 7-c. 会長が決裁マーカーの語を引用しただけなら発火する（PR #387）=="
for qentry in "決裁反映の引用=前回の決裁反映を確認しました。続けてください" \
              "【要決裁】の引用=【要決裁】の件だけど、Bで進めてほしい"; do
  qlabel="${qentry%%=*}"
  quoted="${qentry#*=}"
  check "仕事5 は引用「${qlabel}…」で発火する" "true" \
    "$(ringi "$(node "ringi:pending" "hiroky1983=$RINGI_THREAD" "hiroky1983=$quoted")")"
  check "仕事8 は引用「${qlabel}…」で発火する" "true" \
    "$(proposed "$(node "ai:proposed" "hiroky1983=$quoted")")"
  check "仕事11 は引用「${qlabel}…」で発火する" "true" \
    "$(blocked "$(node "blocked" "hiroky1983=解除確認: 未達" "hiroky1983=$quoted")")"
done
check "正規の決裁反映（先頭一致）は当番の記録として除外される" "false" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=$CHAIRMAN" "hiroky1983=決裁反映: 承認のため着手します")")"

# 集約が「常に false を返す」実装になっていないことの対照（会長の生コメントは3つとも発火する）
check "仕事5 は会長の素のコメントでは発火する（集約が潰していない）" "true" \
  "$(ringi "$(node "ringi:pending" "hiroky1983=解除しました" "hiroky1983=$CHAIRMAN")")"
check "仕事8 は会長の素のコメントでは発火する（集約が潰していない）" "true" \
  "$(proposed "$(node "ai:proposed" "hiroky1983=$CHAIRMAN")")"
check "仕事11 は会長の素のコメントでは発火する（集約が潰していない）" "true" \
  "$(blocked "$(node "blocked" "hiroky1983=解除確認: 未達" "hiroky1983=$CHAIRMAN")")"

# 仕事12（ハンコによる決裁・#436）。会長は ringi:pending を外さないため、「決裁スレッドのあとに
# ai:approved が付いた」= 推奨案での決裁成立として当番を起こす。#164 はこの経路が無かったせいで
# ハンコが押されたまま2週間滞留した。
# タイムライン付きのノードを組み立てる。
# 引数:
#   $1 ラベル（カンマ区切り）
#   $2 `ai:approved` のラベル操作履歴。"時刻,actor,L|U" を `;` で連結（L=付与 / U=剥がし）。
#      actor を省くと hiroky1983、種別を省くと L。空文字なら履歴そのものが無い（順序不明）
#   $3.. コメント "時刻=本文"（古い順）。時刻に `,author` を付けると投稿者を指定できる
stamp_node() {
  local labels="$1" stamps="$2"; shift 2
  local jq_labels jq_comments jq_timeline c key author ev t a kind
  jq_labels=$(printf '%s' "$labels" | tr ',' '\n' | jq -R '{name: .}' | jq -sc .)
  jq_comments='[]'
  for c in "$@"; do
    key="${c%%=*}"
    author="hiroky1983"
    case "$key" in *,*) author="${key#*,}"; key="${key%%,*}" ;; esac
    jq_comments=$(printf '%s' "$jq_comments" \
      | jq -c --arg t "$key" --arg a "$author" --arg b "${c#*=}" \
          '. + [{author: {login: $a}, createdAt: $t, body: $b}]')
  done
  jq_timeline='[]'
  if [ -n "$stamps" ]; then
    local IFS=';'
    for ev in $stamps; do
      t="${ev%%,*}"; a="hiroky1983"; kind="L"
      case "$ev" in *,*) a="${ev#*,}"; a="${a%%,*}" ;; esac
      case "$ev" in *,*,*) kind="${ev##*,}" ;; esac
      jq_timeline=$(printf '%s' "$jq_timeline" | jq -c \
        --arg t "$t" --arg a "$a" \
        --arg ty "$([ "$kind" = "U" ] && echo UnlabeledEvent || echo LabeledEvent)" \
        '. + [{__typename: $ty, createdAt: $t, label: {name: "ai:approved"}, actor: {login: $a}}]')
    done
  fi
  jq -nc --argjson l "$jq_labels" --argjson c "$jq_comments" --argjson tl "$jq_timeline" \
    '{number: 1, labels: {nodes: $l}, comments: {nodes: $c}, timelineItems: {nodes: $tl}}'
}
ringi_stamp() { printf '%s' "$1" | jq --arg trusted "$ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $a | is_ringi_stamp($a)'; }

T1="2026-09-01T00:00:00Z"   # 決裁スレッドの投稿
T2="2026-09-02T00:00:00Z"   # ハンコ
T3="2026-09-03T00:00:00Z"   # 当番の応答

echo "== 9. 仕事12（ハンコ着信）: 発火すべきケース =="
check "ハンコが決裁スレッドより後なら発火する（#436）" "true" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2,hiroky1983" "$T1=$RINGI_THREAD")")"
check "決裁スレッドが無くてもハンコが押されていれば発火する" "true" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2,hiroky1983")")"
check "ハンコの付与イベントが取れず当番の応答も無ければ発火する（順序不明・当番が再掲する）" "true" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "")")"

echo "== 10. 仕事12: 発火してはいけないケース =="
check "ハンコが決裁スレッドより前なら発火しない（起票時からの承認）" "false" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T1,hiroky1983" "$T2=$RINGI_THREAD")")"
check "ringi:pending 単独（ハンコ無し）なら発火しない" "false" \
  "$(ringi_stamp "$(stamp_node "ringi:pending" "" "$T1=$RINGI_THREAD")")"
check "ai:approved 単独（決裁待ちでない）なら発火しない" "false" \
  "$(ringi_stamp "$(stamp_node "ai:approved" "$T2,hiroky1983")")"
# 停止条件の本体。当番の処理は「反映記録」か「決裁スレッドの再掲」で必ず終わるので、
# 応答した瞬間に鳴り止む（#120・#168・#386 と同型の空振り恒久化の再発防止）
for entry in "決裁反映（正典の形）=決裁反映: ハンコを推奨案の承認として反映しました" \
             "決裁反映（見出しの形・#164 の実データ）=## 決裁反映（2026-09-02）" \
             "決裁スレッドの再掲=$RINGI_THREAD"; do
  check "ハンコの後に当番が「${entry%%=*}」を書いたら発火しない" "false" \
    "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2,hiroky1983" "$T1=$RINGI_THREAD" "$T3=${entry#*=}")")"
done
check "順序不明でも稟議の記録が既にあれば発火しない（無限空振りの防止）" "false" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "" "$T1=$RINGI_THREAD")")"
check "ハンコの後の会長の素のコメントでは発火する（仕事5 と二重に拾って構わない）" "true" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2,hiroky1983" "$T1=$RINGI_THREAD" "$T3=$CHAIRMAN")")"
check "許可リスト外のアカウントによるハンコは無視する" "false" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2,someone-else" "$T1=$RINGI_THREAD")")"

# 基準を is_duty_reply の集合全部にすると、稟議と無関係な当番の記録が1本入っただけで
# 未処理のハンコを取りこぼす。基準は稟議の記録2種に限る
echo "== 10-b. 仕事12: 稟議と無関係な当番マーカーではハンコを取りこぼさない =="
for entry in "企画議論=企画議論（経営企画室）: 補足します" \
             "解除確認=解除確認: 条件は未達です" \
             "着手見送り=着手見送り: 着手条件が未達"; do
  check "ハンコの後に当番が「${entry%%=*}」を書いても発火する（取りこぼさない）" "true" \
    "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2,hiroky1983" "$T1=$RINGI_THREAD" "$T3=${entry#*=}")")"
done

# PR #446 の CodeRabbit 指摘（Security & Privacy・Major）。このリポジトリは PUBLIC で誰でも
# Issue にコメントでき、共同作業者ならラベルも操作できる。検知を第三者に握り潰されない・
# 第三者のラベル操作を会長のハンコと誤読しないことを確かめる。
echo "== 10-c. 仕事12: 承認の出所が信頼アカウントであることを要求する（PR #446 指摘）=="
check "第三者の「決裁反映」コメントでは検知を握り潰せない" "true" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2" "$T1=$RINGI_THREAD" "$T3,attacker=決裁反映: 対応済みです")")"
check "第三者の決裁スレッド風コメントでも検知を握り潰せない" "true" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2" "$T1=$RINGI_THREAD" "$T3,attacker=## 【要決裁】偽の再掲")")"
check "会長のハンコの後に第三者が剥がして付け直した場合は発火しない" "false" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2;$T3,attacker,U;$T3,attacker,L" "$T1=$RINGI_THREAD")")"
check "最新のラベル操作が「剥がし」なら発火しない（会長が承認を取り消した）" "false" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T2;$T3,hiroky1983,U" "$T1=$RINGI_THREAD")")"
check "会長が付け直した（第三者の剥がしの後）なら発火する" "true" \
  "$(ringi_stamp "$(stamp_node "ringi:pending,ai:approved" "$T1,attacker,U;$T2,hiroky1983,L" "$T1=$RINGI_THREAD")")"

echo "== 11. 呼び出し側が共通定義を使っている（判定の写しを作っていない）=="
USES=$(grep -c 'DUTY_JQ_COMMENT_LIB"' "$TARGET")
check "仕事5・仕事8・仕事11・仕事12 の4箇所が DUTY_JQ_COMMENT_LIB を渡している" "4" "$USES"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
