#!/bin/bash
# ci.yml の「アプリに関係する変更か」の判定の検証（#1719）。
#
# 判定は ci.yml の run ブロックに埋まっているため、classify:begin〜end の範囲を取り出して
# 変更ファイル一覧ごとに実行する。誤ってアプリ変更をスキップすると test/build が走らず
# 壊れた変更がマージされるので、スキップしてよいもの・いけないものの両方を固定する。
#
# 使い方: bash Scripts/tests/test-ci-detect-app-changes.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_YML="$SCRIPT_DIR/../../.github/workflows/ci.yml"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

SNIPPET="$(sed -n '/# classify:begin/,/# classify:end/p' "$CI_YML")"
if [ -z "$SNIPPET" ] || ! grep -q 'others=' <<<"$SNIPPET"; then
  echo "NG: ci.yml から判定ブロックを取り出せない"; exit 1
fi

# 引数: 説明 / 期待（app=アプリ関係あり, skip=スキップ） / 変更ファイル（可変長）
check() {
  local desc="$1" want="$2" files got
  shift 2
  files="$(printf '%s\n' "$@")"
  got="$(files="$files" bash -c "$SNIPPET"$'\n''[ -n "$others" ] && echo app || echo skip')"
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: $want / 実際: $got)"; fi
}

echo "== 1. 運用系だけならスキップ =="
check "docs のみ"                 skip "docs/ai-devops.md"
check "Scripts のみ"              skip "Scripts/ai-duty.sh"
check "web のみ"                  skip "web/app/page.tsx"
check ".md のみ"                  skip "README.md"
check ".github の別ワークフロー"   skip ".github/workflows/pr-base-guard.yml"
check ".github の ISSUE_TEMPLATE" skip ".github/ISSUE_TEMPLATE/bug.yml"
check "運用系の混在"              skip "docs/a.md" ".github/workflows/x.yml" "Scripts/y.sh"

echo "== 2. ci.yml 自身とアプリ変更は回す =="
check "ci.yml のみ"               app ".github/workflows/ci.yml"
check "ci.yml と docs"            app "docs/a.md" ".github/workflows/ci.yml"
check "ci.yml と別ワークフロー"   app ".github/workflows/x.yml" ".github/workflows/ci.yml"
check "Swift の変更"              app "Packages/GameKit/Sources/Core/Theme.swift"
check "project.yml"               app "project.yml"
check ".github と Swift の混在"   app ".github/workflows/x.yml" "App/HubView.swift"
check "名前が似たファイル"        app ".github/workflows/ci.yml.bak" "project.yml"

echo
echo "結果: $PASS 件成功 / $FAIL 件失敗"
[ "$FAIL" = 0 ]
