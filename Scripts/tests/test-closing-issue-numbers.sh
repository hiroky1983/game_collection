#!/bin/bash
# closing-issue-numbers.js の検証（#3063）。
#
# close-issues.yml の判定を誤ると無関係な Issue を completed で閉じる（語尾の誤爆）ため、
# 拾うもの・拾わないものを直接テストする。
#
# 使い方: bash Scripts/tests/test-closing-issue-numbers.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../closing-issue-numbers.js"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

# 引数: 説明 / 期待する出力（スペース区切り・空なら何も拾わない） / PR 本文
check() {
  local desc="$1" want="$2" body="$3" got
  got="$(printf '%s' "$body" | node "$TARGET" | tr '\n' ' ' | sed 's/ $//')"
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: '$want' / 実際: '$got')"; fi
}

check "Closes #1 を拾う" "1" "Closes #1"
check "小文字・fixes・resolves を拾う" "2 3" $'fixes #2\nresolves #3'
check "過去形 closed / fixed / resolved を拾う" "4 5 6" $'closed #4\nFixed #5\nresolved #6'
check "文中の Closes を拾う" "7" "この PR は Closes #7 です"
check "prefixes #5 の語尾は拾わない" "" "This prefixes #5 ..."
check "encloses #7 の語尾は拾わない" "" "encloses #7"
check "unresolved #8 の語尾は拾わない" "" "unresolved #8"
check "語尾の誤爆と正規の Closes が混在しても正規だけ拾う" "9" $'prefixes #5\nCloses #9'
check "同じ番号は1回だけ" "10" $'Closes #10\nFixes #10'
check "カンマ区切りは先頭だけ（仕様追加はしない）" "1" "Closes #1, #2"
check "インラインコード内は拾わない" "" 'see `Closes #11`'
check "引用内は拾わない" "" "> Closes #12"
check "HTML コメント内は拾わない" "" "<!-- Closes #13 -->"
check "フェンス内は拾わない" "" $'```\nCloses #14\n```'
check "コードで分断された Closes と番号を連結しない" "" 'Closes `foo` #15'

echo "結果: $PASS 件成功 / $FAIL 件失敗"
[ "$FAIL" -eq 0 ]
