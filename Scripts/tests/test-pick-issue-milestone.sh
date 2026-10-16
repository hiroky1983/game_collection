#!/bin/bash
# pick-issue-milestone.sh の検証（会長決裁 2026-10-16: 着手できる Issue が 0 件なら自動起票は現行版へ）。
#
# gh は PATH の先頭に置いた偽物に差し替える。偽物は fixture ディレクトリの JSON を返し、
# 呼び出し側の --jq を本物の jq で当てる（実際の gh と同じく、--jq の式そのものも検証される）。
# fixture が無い呼び出しは失敗（終了コード 1）として返す = gh の取得失敗。
#
# 使い方: bash Scripts/tests/test-pick-issue-milestone.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../pick-issue-milestone.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/bin/bash
# 偽の gh。FIX（fixture ディレクトリ）から応答を選ぶ
jqexpr="."; ms=""; base=""; ep=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --jq) jqexpr="${args[$((i + 1))]}" ;;
    --milestone) ms="${args[$((i + 1))]}" ;;
    --base) base="${args[$((i + 1))]}" ;;
  esac
done
case "$1 $2" in
  "api "*)
    case "$2" in
      */milestones\?*) f="$FIX/milestones.json" ;;
      */git/matching-refs/tags/v) f="$FIX/tags.json" ;;
      */branches/*/protection) v="${2#*release%2Fv}"; v="${v%/protection}"; f="$FIX/protection-v$v.json" ;;
      *) exit 1 ;;
    esac ;;
  "pr list") f="$FIX/prs-${base//\//_}.json" ;;
  "issue list") f="$FIX/issues-$ms.json" ;;
  *) exit 1 ;;
esac
[ -f "$f" ] || { echo "gh: not found" >&2; exit 1; }
jq -r "$jqexpr" "$f"
EOF
chmod +x "$TMP/bin/gh"

# 既定の fixture: 現行版 v1.1.12（未凍結）・次版 v1.1.13・企画倉庫・提出済みで開いたままの v1.1.11
reset_fix() {
  FIX="$TMP/fix-$1"
  mkdir -p "$FIX"
  echo '[{"title":"企画倉庫"},{"title":"v1.1.13"},{"title":"v1.1.12"},{"title":"v1.1.11"}]' >"$FIX/milestones.json"
  echo '[{"ref":"refs/tags/v1.1.10"},{"ref":"refs/tags/v1.1.10-submitted"},{"ref":"refs/tags/v1.1.11-submitted"}]' >"$FIX/tags.json"
  echo '{"lock_branch":{"enabled":false}}' >"$FIX/protection-v1.1.12.json"
  echo '[]' >"$FIX/prs-release_v1.1.12.json"
  echo '[]' >"$FIX/issues-v1.1.12.json"
  export FIX
}

# 引数: 説明 / 期待する標準出力（空なら出力なし）/ 期待する終了コード
check() {
  local desc="$1" want_out="$2" want_rc="$3" out rc
  out=$(PATH="$TMP/bin:$PATH" bash "$TARGET" 2>"$TMP/err")
  rc=$?
  if [ "$out" = "$want_out" ] && [ "$rc" = "$want_rc" ]; then
    ok "$desc"
  else
    ng "$desc (期待: [$want_out] rc=$want_rc / 実際: [$out] rc=$rc / $(cat "$TMP/err"))"
  fi
}

issue() {  # issue <番号> <ラベル...> → gh issue list --json number,labels の 1 要素
  local n="$1"; shift
  jq -nc --argjson n "$n" '$ARGS.positional | {number: $n, labels: map({name: .})}' --args "$@"
}
issues() { printf '%s\n' "$@" | jq -s . >"$FIX/issues-v1.1.12.json"; }

echo "== 1. 着手できる Issue が 0 件なら現行版 =="
reset_fix a
check "現行版に Issue が 1 件も無い" "v1.1.12" 0
issues "$(issue 1 ai:approved ringi:pending)" "$(issue 2 ai:approved ringi:pending)"
check "承認済みだが決裁待ち（ringi:pending）だけ（2026-10-16 の実データの形）" "v1.1.12" 0
grep -q "現行版" "$TMP/err" && ok "理由が標準エラーに出る" || ng "理由が標準エラーに出る"

echo "== 2. 着手できない Issue は数えない =="
reset_fix b
issues "$(issue 1 ai:approved ai:in-progress)"
check "ai:in-progress は数えない" "v1.1.12" 0
issues "$(issue 1 ai:approved blocked)"
check "blocked は数えない" "v1.1.12" 0
issues "$(issue 1 ai:approved ai:hold)"
check "ai:hold は数えない" "v1.1.12" 0
issues "$(issue 1 ai:approved duty:heavy)"
check "duty:heavy は数えない" "v1.1.12" 0
issues "$(issue 1 ai:proposed)" "$(issue 2 enhancement)"
check "未承認（ai:approved が無い）は数えない" "v1.1.12" 0

echo "== 3. 着手できる Issue が 1 件以上なら次版 =="
reset_fix c
issues "$(issue 1 ai:approved)"
check "ai:approved だけの Issue が 1 件" "v1.1.13" 0
issues "$(issue 1 ai:approved ai:hold)" "$(issue 2 ai:approved risk:logic)"
check "除外対象に混じって着手できるものが 1 件" "v1.1.13" 0

echo "== 4. 現行版が凍結・出荷準備中なら次版 =="
reset_fix d
echo '[{"headRefName":"chore/release-version-v1.1.12-b28"}]' >"$FIX/prs-release_v1.1.12.json"
check "版数更新 PR が開いている（出荷準備中）" "v1.1.13" 0
echo '[{"headRefName":"duty/2300-fix"}]' >"$FIX/prs-release_v1.1.12.json"
check "開いているのが通常の開発 PR だけなら出荷準備中ではない" "v1.1.12" 0
reset_fix e
echo '{"lock_branch":{"enabled":true}}' >"$FIX/protection-v1.1.13.json"
echo '[]' >"$FIX/prs-release_v1.1.13.json"
echo '[]' >"$FIX/issues-v1.1.13.json"
echo '{"lock_branch":{"enabled":true}}' >"$FIX/protection-v1.1.12.json"
echo '[{"title":"v1.1.14"},{"title":"v1.1.13"},{"title":"v1.1.12"}]' >"$FIX/milestones.json"
echo '{"lock_branch":{"enabled":false}}' >"$FIX/protection-v1.1.14.json"
echo '[]' >"$FIX/prs-release_v1.1.14.json"
echo '[]' >"$FIX/issues-v1.1.14.json"
check "lock_branch 済みの版は飛ばし、凍結していない最小の版を現行版にする" "v1.1.14" 0
reset_fix f
echo '[{"ref":"refs/tags/v1.1.11-submitted"},{"ref":"refs/tags/v1.1.12-submitted"}]' >"$FIX/tags.json"
echo '[]' >"$FIX/prs-release_v1.1.13.json"
echo '[]' >"$FIX/issues-v1.1.13.json"
check "提出済みタグの版は飛ばす（次の版が現行版になる）" "v1.1.13" 0
reset_fix g
echo '[{"ref":"refs/tags/v1.1.11-submitted"},{"ref":"refs/tags/v1.1.1-submitted"},{"ref":"refs/tags/v1.1.1"}]' >"$FIX/tags.json"
check "v1.1.1 のタグで v1.1.12 を凍結扱いにしない（完全一致）" "v1.1.12" 0
reset_fix h
rm "$FIX/protection-v1.1.12.json"
check "保護設定が取れない（エラー）は未凍結とみなす（ai-duty.sh 仕事13 と同じ）" "v1.1.12" 0

echo "== 5. 取得に失敗したら安全側（次版）・出す版が無ければ 1 =="
reset_fix i
rm "$FIX/issues-v1.1.12.json"
check "Issue 一覧が取れない → 次版" "v1.1.13" 0
reset_fix j
rm "$FIX/prs-release_v1.1.12.json"
check "PR 一覧が取れない → 次版" "v1.1.13" 0
reset_fix k
rm "$FIX/milestones.json"
check "マイルストーンが取れない → 1" "" 1
reset_fix l
rm "$FIX/tags.json"
check "タグが取れない → 1（凍結を判定できない）" "" 1
reset_fix m
echo '[{"title":"企画倉庫"},{"title":"v1.1.12"}]' >"$FIX/milestones.json"
echo '[{"headRefName":"chore/release-version-v1.1.12-b28"}]' >"$FIX/prs-release_v1.1.12.json"
check "出荷準備中で次の版のマイルストーンが無い → 1（新設しない）" "" 1
echo '[]' >"$FIX/prs-release_v1.1.12.json"
issues "$(issue 1 ai:approved)"
check "着手できる Issue があり次の版が無い → 未凍結の現行版" "v1.1.12" 0
reset_fix n
echo '[{"title":"企画倉庫"}]' >"$FIX/milestones.json"
check "vX.Y.Z のマイルストーンが無い（企画倉庫だけ）→ 1" "" 1

echo "== 6. 版の並びは数値順 =="
reset_fix o
echo '[{"title":"v1.1.10"},{"title":"v1.1.9"}]' >"$FIX/milestones.json"
echo '[]' >"$FIX/tags.json"
echo '[]' >"$FIX/prs-release_v1.1.9.json"
echo '[{"number":1,"labels":[{"name":"ai:approved"}]}]' >"$FIX/issues-v1.1.9.json"
check "v1.1.9 の次は v1.1.10（文字列順で v1.1.10 を先にしない）" "v1.1.10" 0

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
