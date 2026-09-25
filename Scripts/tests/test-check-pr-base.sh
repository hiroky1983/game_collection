#!/bin/bash
# check-pr-base.sh の検証（#606）。
#
# このチェックは PR を止める側なので、誤検知（正規の取り込みや docs PR を落とす）も
# 見逃し（main 直のアプリコードを通す）もそのまま事故になる。base・head・変更パスの
# 組み合わせを直接テストする。
#
# 使い方: bash Scripts/tests/test-check-pr-base.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-pr-base.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 引数: 説明 / 期待する終了コード / base / head / 変更ファイル（可変長）
check() {
  local desc="$1" want="$2" base="$3" head="$4"
  shift 4
  local got
  printf '%s\n' "$@" | bash "$TARGET" "$base" "$head" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: 終了コード $want / 実際: $got)"; fi
}

echo "== 1. main 直のアプリコードは落ちる =="
check "Packages/ の変更"        1 main "fix/runner-followup-qa" "Packages/GameKit/Sources/GameRunner/RunnerView.swift"
check "App/ の変更"             1 main "feat/hub" "App/HubView.swift"
check "project.yml の変更"      1 main "chore/bump" "project.yml"
check "docs に混ぜても落ちる"    1 main "duty/x" "docs/ai-devops.md" "Packages/GameKit/Sources/Core/Theme.swift"

echo "== 2. main 直でも運用系・LP は通る =="
check "docs のみ"               0 main "docs/roadmap" "docs/ai-company.md"
check "Scripts のみ"            0 main "duty/tooling" "Scripts/ai-duty.sh"
check ".github のみ"            0 main "ci/fix" ".github/workflows/ci.yml"
check "web/（LP）のみ"          0 main "web/seo" "web/app/lib/games.ts"
check "変更ファイルが空"        0 main "duty/x" ""

echo "== 3. release 向けの通常の開発 PR は見ない =="
check "base が release/v1.1.4"  0 "release/v1.1.4" "duty/606-x" "Packages/GameKit/Sources/GameRunner/RunnerView.swift"
check "base が release/v1.1.3"  0 "release/v1.1.3" "feat/x" "App/HubView.swift"

echo "== 4. 公開後の取り込み（release → main）は通す =="
check "head が release/v1.1.3"                  0 main "release/v1.1.3" "App/HubView.swift" "Packages/GameKit/Sources/Core/Theme.swift"
check "head が凍結回避の中間ブランチ（#558）"    0 main "chore/merge-release-v113-to-main" "Packages/GameKit/Sources/Core/Theme.swift"

echo "== 5. 取り込み経路に見せかけた迂回は通さない =="
# ブランチ名は PR を出す側が自由に決められるので、**バージョン番号の形まで**見て初めて
# 歯止めになる。`release/` の前方一致だけだと、その名前を付けるだけで素通しできてしまう
# （#607 の敵対的検証の指摘）。
check "head 名に release を含むだけ（fix/release-note）" 1 main "fix/release-note" "App/HubView.swift"
check "head 名が my-release/v1.1.4"                       1 main "my-release/v1.1.4" "App/HubView.swift"
check "release/ で始まるだけの作業ブランチ"               1 main "release/whatever" "App/HubView.swift"
check "release の後にスラッシュが無い（release-v1.1.4）"  1 main "release-v1.1.4" "App/HubView.swift"
check "release の後にスラッシュが無い（releasehotfix）"   1 main "releasehotfix" "App/HubView.swift"
check "v が無い（release/1.1.4）"                         1 main "release/1.1.4" "App/HubView.swift"
check "バージョンが2要素（release/v1.1）"                 1 main "release/v1.1" "App/HubView.swift"
check "バージョンが4要素（release/v1.1.4.1）"             1 main "release/v1.1.4.1" "App/HubView.swift"
check "release/vX.Y.Z の後ろに続きがある"                 1 main "release/v1.1.4-hotfix" "App/HubView.swift"
check "中間ブランチに見せかけた名前"                      1 main "chore/merge-release-vXYZ" "App/HubView.swift"
check "中間ブランチの語尾が違う"                          1 main "chore/merge-release-v113-to-release" "App/HubView.swift"

echo "== 6. 使い方の誤りは 2 で落ちる（黙って通さない）=="
check "base が空"  2 "" "feat/x" "App/HubView.swift"
check "head が空"  2 main ""      "App/HubView.swift"
printf 'App/HubView.swift\n' > "$TMP/files.txt"
bash "$TARGET" main "feat/x" "$TMP/files.txt" >/dev/null 2>&1
[ $? -eq 1 ] && ok "ファイル渡しでも判定できる" || ng "ファイル渡しでも判定できる"
bash "$TARGET" main "feat/x" "$TMP/no-such-file.txt" >/dev/null 2>&1
[ $? -eq 2 ] && ok "読めないファイルを渡したら落ちる" || ng "読めないファイルを渡したら落ちる"

echo "== 7. CI から呼ばれている（仕込み忘れの検出）=="
WORKFLOW="$SCRIPT_DIR/../../.github/workflows/pr-base-guard.yml"
if [ -f "$WORKFLOW" ] && grep -q "check-pr-base.sh" "$WORKFLOW"; then
  ok "pr-base-guard.yml が check-pr-base.sh を呼んでいる"
else
  ng "pr-base-guard.yml が check-pr-base.sh を呼んでいない"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
