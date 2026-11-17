#!/bin/bash
# check-lp-min-ios.sh の検証（#3533）。
# 固定する落とし穴: 4箇所のどれか1つだけがずれているのを見逃す / 読み取れないのを黙って通す。
#
# 使い方: bash Scripts/tests/test-check-lp-min-ios.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-lp-min-ios.sh"
REAL_ROOT="$SCRIPT_DIR/../.."
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -r -f "$TMP"' EXIT

# 偽のツリーを作る。引数: project site ja en
make_tree() {
  local d="$TMP/t$RANDOM$RANDOM"
  mkdir -p "$d/web/app/lib" "$d/web/app/(ja)/terms" "$d/web/app/en/terms"
  printf 'options:\n  deploymentTarget:\n    iOS: "%s"\n' "$1" > "$d/project.yml"
  printf 'export const MIN_IOS_VERSION = "%s";\n' "$2" > "$d/web/app/lib/site.ts"
  printf '<p>iOS %s以上のデバイスでご利用いただけます。</p>\n' "$3" > "$d/web/app/(ja)/terms/page.tsx"
  printf '<p>devices running\n iOS %s or later.</p>\n' "$4" > "$d/web/app/en/terms/page.tsx"
  echo "$d"
}

expect() { # 名前 期待終了コード ツリー
  bash "$TARGET" "$3" >/dev/null 2>&1
  local rc=$?
  [ "$rc" -eq "$2" ] && ok "$1" || ng "${1}（終了コード ${rc}、期待 ${2}）"
}

expect "全部一致なら通る" 0 "$(make_tree 17.0 17.0 17.0 17.0)"
expect "site.ts だけずれたら落ちる" 1 "$(make_tree 18.0 17.0 18.0 18.0)"
expect "規約(ja)だけずれたら落ちる" 1 "$(make_tree 18.0 18.0 17.0 18.0)"
expect "規約(en)だけずれたら落ちる" 1 "$(make_tree 18.0 18.0 18.0 17.0)"
expect "project.yml だけ上がったら落ちる" 1 "$(make_tree 18.0 17.0 17.0 17.0)"

T="$(make_tree 17.0 17.0 17.0 17.0)"
echo 'nothing' > "$T/web/app/en/terms/page.tsx"
expect "規約から版が読めなければ落ちる" 1 "$T"

T="$(make_tree 17.0 17.0 17.0 17.0)"
rm "$T/web/app/lib/site.ts"
expect "ファイルが無ければ落ちる" 1 "$T"

# 同じ値を表す YAML 表記（単一引用符・引用符なし・行末コメント）も読めること
for line in "    iOS: '17.0'" "    iOS: 17.0" '    iOS: "17.0" # minimum OS'; do
  T="$(make_tree 17.0 17.0 17.0 17.0)"
  printf 'options:\n  deploymentTarget:\n%s\n' "$line" > "$T/project.yml"
  expect "project.yml の表記 [$line] を読める" 0 "$T"
done

# 実リポジトリは今一致している
expect "実リポジトリが一致している" 0 "$REAL_ROOT"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
