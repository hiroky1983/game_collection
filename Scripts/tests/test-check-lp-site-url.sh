#!/bin/bash
# check-lp-site-url.sh の検証（#3547）。
# 固定する落とし穴: 片方だけずれたのを見逃す / 読み取れないのを黙って通す。
#
# 使い方: bash Scripts/tests/test-check-lp-site-url.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-lp-site-url.sh"
REAL_ROOT="$SCRIPT_DIR/../.."
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -r -f "$TMP"' EXIT

# 偽のツリーを作る。引数: SITE_URL APP_STORE_ID legalBaseURL アプリ側の id
make_tree() {
  local d="$TMP/t$RANDOM$RANDOM"
  mkdir -p "$d/web/app/lib" "$d/App"
  printf 'export const SITE_URL = "%s";\n\nexport const APP_STORE_ID = "%s";\n' "$1" "$2" > "$d/web/app/lib/site.ts"
  printf '    private static let legalBaseURL = "%s"\n' "$3" > "$d/App/SettingsView.swift"
  printf '    static let appStoreURL = URL(string: "https://apps.apple.com/jp/app/id%s")!\n' "$4" > "$d/App/AppGameServices.swift"
  echo "$d"
}

expect() { # 名前 期待終了コード ツリー
  bash "$TARGET" "$3" >/dev/null 2>&1
  local rc=$?
  [ "$rc" -eq "$2" ] && ok "$1" || ng "${1}（終了コード ${rc}、期待 ${2}）"
}

A="https://example.vercel.app"
B="https://example.com"

expect "全部一致なら通る" 0 "$(make_tree $A 111 $A 111)"
expect "末尾スラッシュ違いは通る" 0 "$(make_tree $A 111 $A/ 111)"
expect "SITE_URL だけ変わったら落ちる" 1 "$(make_tree $B 111 $A 111)"
expect "legalBaseURL だけ変わったら落ちる" 1 "$(make_tree $A 111 $B 111)"
expect "APP_STORE_ID だけ変わったら落ちる" 1 "$(make_tree $A 222 $A 111)"
expect "アプリ側の id だけ変わったら落ちる" 1 "$(make_tree $A 111 $A 222)"

T="$(make_tree $A 111 $A 111)"
echo 'nothing' > "$T/App/SettingsView.swift"
expect "legalBaseURL が読めなければ落ちる" 1 "$T"

T="$(make_tree $A 111 $A 111)"
echo 'nothing' > "$T/App/AppGameServices.swift"
expect "appStoreURL が読めなければ落ちる" 1 "$T"

T="$(make_tree $A 111 $A 111)"
rm "$T/web/app/lib/site.ts"
expect "ファイルが無ければ落ちる" 1 "$T"

# 実リポジトリは今一致している
expect "実リポジトリが一致している" 0 "$REAL_ROOT"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
