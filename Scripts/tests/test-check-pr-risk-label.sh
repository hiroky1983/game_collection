#!/bin/bash
# check-pr-risk-label.sh の検証（#823）。
#
# 見逃し（ラベル無しのアプリコードを通す）は #808 の再発、誤検知（docs PR や release の取り込みを
# 落とす）は無関係な PR の CI を赤くする。base・head・ラベル・変更パスの組み合わせを直接テストする。
#
# 使い方: bash Scripts/tests/test-check-pr-risk-label.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-pr-risk-label.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 引数: 説明 / 期待する終了コード / base / head / ラベル（カンマ区切り。無しは ""） / 変更ファイル（可変長）
check() {
  local desc="$1" want="$2" base="$3" head="$4" labels="$5"
  shift 5
  local got
  if [ -n "$labels" ]; then
    printf '%s\n' "$labels" | tr ',' '\n' > "$TMP/labels.txt"
  else
    : > "$TMP/labels.txt"
  fi
  printf '%s\n' "$@" | bash "$TARGET" "$base" "$head" "$TMP/labels.txt" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: 終了コード $want / 実際: $got)"; fi
}

PKG="Packages/GameKit/Sources/GameBlocks/BlocksView.swift"

echo "== 1. ラベル無しのアプリコードは落ちる（#808 の 6 本の形）=="
check "Packages/ の変更・ラベル無し"            1 "release/v1.1.5" "fix/blocks-paddle-relative-control" "" "$PKG"
check "App/ の変更・ラベル無し"                 1 "release/v1.1.5" "fix/716-hub" "" "App/HubView.swift"
check "project.yml の変更・ラベル無し"          1 "release/v1.1.6" "chore/bump" "" "project.yml"
check "docs に混ぜても落ちる"                   1 "release/v1.1.5" "feat/x" "" "docs/ui-review/a.png" "$PKG"
check "risk 以外のラベルだけでは落ちる"         1 "release/v1.1.5" "feat/x" "bug,ai:approved" "$PKG"

echo "== 2. 規程の 3 種のどれかがあれば通る =="
check "risk:logic"                               0 "release/v1.1.5" "fix/x" "risk:logic" "$PKG"
check "risk:ui"                                  0 "release/v1.1.5" "fix/x" "risk:ui" "App/HubView.swift"
check "risk:sensitive"                           0 "release/v1.1.6" "feat/ads" "risk:sensitive" "project.yml"
check "他のラベルと並んでいても通る"             0 "release/v1.1.5" "fix/x" "bug,risk:ui,ai:approved" "$PKG"

echo "== 3. 規程に無いラベル・似た名前は通さない =="
check "risk:low（存在しない分類）"               1 "release/v1.1.5" "fix/x" "risk:low" "$PKG"
check "risk: の接頭辞だけ"                       1 "release/v1.1.5" "fix/x" "risk:" "$PKG"
check "大文字違い（Risk:UI）"                    1 "release/v1.1.5" "fix/x" "Risk:UI" "$PKG"
check "後ろに続きがある（risk:ui-minor）"        1 "release/v1.1.5" "fix/x" "risk:ui-minor" "$PKG"

echo "== 4. アプリコードを含まない PR は見ない =="
check "docs のみ"                                0 "main" "docs/roadmap" "" "docs/ai-company.md"
check "Scripts と .github のみ"                  0 "main" "chore/823" "" "Scripts/check-pr-risk-label.sh" ".github/workflows/pr-risk-label.yml"
check "web/（LP）のみ"                           0 "main" "web/seo" "" "web/app/lib/games.ts"
check "変更ファイルが空"                         0 "release/v1.1.5" "duty/x" "" ""
check "App という名前で始まるだけの別ディレクトリ" 0 "main" "chore/x" "" "Apps-notes/readme.md"

echo "== 5. 分類済みの変更を束ねて運ぶ PR は見ない =="
check "取り込み: release/v1.1.4 → main"          0 "main" "release/v1.1.4" "" "App/HubView.swift" "$PKG"
check "同期: release/v1.1.5 → release/v1.1.6"    0 "release/v1.1.6" "release/v1.1.5" "" "$PKG"
check "凍結回避の中間ブランチ（#558）"           0 "main" "chore/merge-release-v113-to-main" "" "$PKG"
check "同期ブランチ（#903）"                     0 "release/v1.1.6" "chore/sync-v115-to-v116-0915" "" "$PKG"
check "同期ブランチ（#888）"                     0 "release/v1.1.6" "chore/sync-release-v1.1.5-to-v1.1.6-847" "" "$PKG"

echo "== 6. 束ねる PR に見せかけた名前は通さない =="
check "release/ で始まるだけの作業ブランチ"      1 "release/v1.1.5" "release/whatever" "" "$PKG"
check "バージョンが2要素（release/v1.1）"        1 "release/v1.1.5" "release/v1.1" "" "$PKG"
check "release/vX.Y.Z の後ろに続きがある"        1 "release/v1.1.5" "release/v1.1.5-hotfix" "" "$PKG"
check "head 名に release を含むだけ"             1 "release/v1.1.5" "fix/release-note" "" "$PKG"
check "中間ブランチを release 向けに出す"        1 "release/v1.1.5" "chore/merge-release-v113-to-main" "" "$PKG"
check "中間ブランチに見せかけた名前"             1 "main" "chore/merge-release-vXYZ" "" "$PKG"
check "同期ブランチ名を main 向けに出す"         1 "main" "chore/sync-v115-to-v116" "" "$PKG"
check "同期ブランチ名だが base が release でない" 1 "feat/base" "chore/sync-x" "" "$PKG"
check "chore/sync- だけで続きが無い"             1 "release/v1.1.6" "chore/sync-" "" "$PKG"
check "chore/sync を接頭辞に含むだけ"            1 "release/v1.1.6" "chore/synchronize" "" "$PKG"

echo "== 7. 使い方の誤りは 2 で落ちる（黙って通さない）=="
: > "$TMP/empty-labels.txt"
printf '%s\n' "$PKG" | bash "$TARGET" "" "feat/x" "$TMP/empty-labels.txt" >/dev/null 2>&1
[ $? -eq 2 ] && ok "base が空" || ng "base が空"
printf '%s\n' "$PKG" | bash "$TARGET" "release/v1.1.5" "" "$TMP/empty-labels.txt" >/dev/null 2>&1
[ $? -eq 2 ] && ok "head が空" || ng "head が空"
printf '%s\n' "$PKG" | bash "$TARGET" "release/v1.1.5" "feat/x" >/dev/null 2>&1
[ $? -eq 2 ] && ok "ラベル一覧を渡さない" || ng "ラベル一覧を渡さない"
printf '%s\n' "$PKG" | bash "$TARGET" "release/v1.1.5" "feat/x" "$TMP/no-such-labels.txt" >/dev/null 2>&1
[ $? -eq 2 ] && ok "読めないラベル一覧" || ng "読めないラベル一覧"
printf '%s\n' "$PKG" > "$TMP/files.txt"
bash "$TARGET" "release/v1.1.5" "feat/x" "$TMP/empty-labels.txt" "$TMP/files.txt" >/dev/null 2>&1
[ $? -eq 1 ] && ok "ファイル渡しでも判定できる" || ng "ファイル渡しでも判定できる"
bash "$TARGET" "release/v1.1.5" "feat/x" "$TMP/empty-labels.txt" "$TMP/no-such-file.txt" >/dev/null 2>&1
[ $? -eq 2 ] && ok "読めない変更ファイル一覧" || ng "読めない変更ファイル一覧"

echo "== 8. CI から呼ばれている（仕込み忘れの検出）=="
WORKFLOW="$SCRIPT_DIR/../../.github/workflows/pr-risk-label.yml"
if [ -f "$WORKFLOW" ] && grep -q "check-pr-risk-label.sh" "$WORKFLOW"; then
  ok "pr-risk-label.yml が check-pr-risk-label.sh を呼んでいる"
else
  ng "pr-risk-label.yml が check-pr-risk-label.sh を呼んでいない"
fi
# ラベルを後から付けたときに再判定されないと、付け直しても赤のまま残る。
if [ -f "$WORKFLOW" ] && grep -q "labeled" "$WORKFLOW" && grep -q "unlabeled" "$WORKFLOW"; then
  ok "ラベルの付け外しで再実行される"
else
  ng "ラベルの付け外しで再実行されない（types に labeled / unlabeled が無い）"
fi
# アプリコードの PR は release ブランチ向けなので、main だけに絞ると肝心の PR で動かない。
if [ -f "$WORKFLOW" ] && grep -q "release/\*\*" "$WORKFLOW"; then
  ok "release ブランチ向けの PR でも動く"
else
  ng "release ブランチ向けの PR で動かない（branches に release/** が無い）"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
