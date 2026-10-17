#!/bin/bash
# check-issue-milestone-prefix.sh の検証（#619）。
#
# 2026-09-11 にオープン Issue 7 件でタイトルプレフィックスとマイルストーンがズレていたのに
# 気づく経路が無かった（規程はあったが検査が無かった）。検知漏れ（ズレを見逃す）も
# 誤検知（整合しているものを誤って報告する）もそのまま信頼を損なうので、組み合わせを
# 直接テストする。gh は一切呼ばず、gh issue list --json number,title,milestone と同じ形の
# JSON を直接渡す（このスクリプト自体が gh 抜きでテストできる設計になっている）。
#
# 使い方: bash Scripts/tests/test-check-issue-milestone-prefix.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-issue-milestone-prefix.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

# 引数: 説明 / 期待する終了コード / 渡す JSON
check() {
  local desc="$1" want="$2" json="$3" got
  printf '%s' "$json" | bash "$TARGET" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: 終了コード $want / 実際: $got)"; fi
}

# 引数: 説明 / 渡す JSON / 出力に含まれるべき文字列
contains_output() {
  local desc="$1" json="$2" needle="$3" out
  out="$(printf '%s' "$json" | bash "$TARGET" 2>&1)"
  case "$out" in
    *"$needle"*) ok "$desc" ;;
    *) ng "$desc (出力に [$needle] が含まれない: $out)" ;;
  esac
}

echo "== 1. 整合している Issue は通る =="
check "マイルストーンとプレフィックスが一致"       0 '[{"number":1,"title":"[v1.1.5] OK","milestone":{"title":"v1.1.5"}}]'
check "マイルストーン無し・プレフィックスも無し"   0 '[{"number":2,"title":"運用系のIssue","milestone":null}]'
check "milestone キー自体が無い（milestone 無しと同じ扱い）" 0 '[{"number":3,"title":"運用系のIssue"}]'
check "空配列"                                     0 '[]'
check "複数件すべて整合"                           0 '[{"number":1,"title":"[v1.1.5] a","milestone":{"title":"v1.1.5"}},{"number":2,"title":"運用系","milestone":null}]'

echo "== 2. 実際にズレていた形（#619 の実測）を検出する =="
check "マイルストーン変更にプレフィックスが追随していない（#54/#79 の形）" 1 \
  '[{"number":54,"title":"[v1.1.3] ASO 二巡目","milestone":{"title":"v1.1.4"}}]'
check "プレフィックス欠落（起票時の付け忘れ、#523 等の形）" 1 \
  '[{"number":523,"title":"プレフィックスが無い Issue","milestone":{"title":"v1.1.4"}}]'
contains_output "欠落の報告に Issue 番号が出る" \
  '[{"number":523,"title":"プレフィックスが無い Issue","milestone":{"title":"v1.1.4"}}]' "#523"
contains_output "欠落の報告に期待するプレフィックスが出る" \
  '[{"number":523,"title":"プレフィックスが無い Issue","milestone":{"title":"v1.1.4"}}]' "[v1.1.4]"

echo "== 3. 逆方向（マイルストーン無しにプレフィックスが付いている）も拾う =="
check "マイルストーンが無いのにプレフィックスが付いている" 1 \
  '[{"number":9,"title":"[v1.1.4] マイルストーン未設定","milestone":null}]'

echo "== 4. 際どい一致判定（部分一致で誤って通さない） =="
check "桁が異なるだけの誤一致（v1.1.5 に v1.1.50 の後ろが続く）" 1 \
  '[{"number":11,"title":"[v1.1.50] 桁違い","milestone":{"title":"v1.1.5"}}]'
check "プレフィックスの後ろに続きがあっても本文は許容（先頭一致でよい）" 0 \
  '[{"number":12,"title":"[v1.1.5] 本文が続く","milestone":{"title":"v1.1.5"}}]'
check "先頭に別の文字が混ざると不一致" 1 \
  '[{"number":13,"title":"接頭辞前に文字 [v1.1.5] タイトル","milestone":{"title":"v1.1.5"}}]'

echo "== 5. 複数件のうち一部だけがズレている場合も検出する =="
check "3件中1件だけズレ" 1 \
  '[{"number":1,"title":"[v1.1.5] a","milestone":{"title":"v1.1.5"}},
    {"number":2,"title":"ズレている","milestone":{"title":"v1.1.5"}},
    {"number":3,"title":"運用系","milestone":null}]'

echo "== 6. 使い方の誤り・不正な入力は 2 で落ちる（黙って通さない） =="
check "JSON 配列でない入力"  2 '{"not":"an array"}'
check "JSON として不正な入力" 2 'this is not json'
bash "$TARGET" /no/such/file.json >/dev/null 2>&1
[ $? -eq 2 ] && ok "読めないファイルを渡したら 2 で落ちる" || ng "読めないファイルを渡したら 2 で落ちる"

echo "== 7. ファイル引数でも判定できる =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '%s' '[{"number":523,"title":"プレフィックス欠落","milestone":{"title":"v1.1.4"}}]' > "$TMP/issues.json"
bash "$TARGET" "$TMP/issues.json" >/dev/null 2>&1
[ $? -eq 1 ] && ok "ファイル渡しでも判定できる" || ng "ファイル渡しでも判定できる"

echo "== 8. タイトルを書き換えない（出力・引数のどちらにも gh edit の呼び出しが無い） =="
if grep -qE 'gh (issue )?edit|title-body|gh issue create' "$TARGET"; then
  ng "スクリプトが gh でタイトルを書き換える経路を持っている"
else
  ok "スクリプトは gh を呼ばない（検知のみで、書き換えは行わない）"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
