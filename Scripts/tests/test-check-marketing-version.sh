#!/bin/bash
# check-marketing-version.sh の検証（#161）。
#
# このチェックは配信を止める側なので、誤検知（正常なのに落ちる）も見逃し（不一致を通す）も
# そのまま事故になる。ブランチ名の形と project.yml の書かれ方の組み合わせを直接テストする。
#
# 使い方: bash Scripts/tests/test-check-marketing-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-marketing-version.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# MARKETING_VERSION を持つ project.yml を組み立てる（引数の各値を1行ずつ書く）
yml() {
  local path="$TMP/project.yml" v
  {
    echo "settings:"
    echo "  base:"
    echo '        CFBundleShortVersionString: "$(MARKETING_VERSION)"'
    for v in "$@"; do
      echo "        MARKETING_VERSION: \"$v\""
      echo '        CURRENT_PROJECT_VERSION: "5"'
    done
  } > "$path"
  printf '%s' "$path"
}

# 引数: 説明 / 期待する終了コード / ブランチ名 / project.yml のパス
check() {
  local desc="$1" want="$2" branch="$3" path="$4" got
  bash "$TARGET" "$branch" "$path" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: 終了コード $want / 実際: $got)"; fi
}

echo "== 1. release ブランチでの一致・不一致 =="
check "ブランチと一致していれば通る"           0 "release/v1.1.2" "$(yml 1.1.2)"
check "更新漏れ（前版のまま）は落ちる"          1 "release/v1.1.2" "$(yml 1.1.1)"
check "先走った更新も落ちる"                    1 "release/v1.1.2" "$(yml 1.1.3)"
check "前方一致で誤判定しない（1.1.2 と 1.1.21）" 1 "release/v1.1.2" "$(yml 1.1.21)"

echo "== 2. 検証対象外のブランチは通す（作業中に邪魔をしない）=="
check "main は対象外"                           0 "main"                        "$(yml 1.1.1)"
check "feature ブランチは対象外"                0 "duty/foo-161"                "$(yml 1.1.1)"
check "旧命名の release-1 は対象外"             0 "release-1"                   "$(yml 1.1.1)"
check "detached HEAD は対象外"                  0 "HEAD"                        "$(yml 1.1.1)"

echo "== 2-b. release/v なのに X.Y.Z でない名前は落とす（検証の迂回を許さない）=="
check "release/vnext は落ちる"                  1 "release/vnext"               "$(yml 1.1.1)"
check "release/v1.1.2-rc1 は落ちる"             1 "release/v1.1.2-rc1"          "$(yml 1.1.2)"
check "release/v（空）は落ちる"                 1 "release/v"                   "$(yml 1.1.2)"
check "release/v1..2 は落ちる"                  1 "release/v1..2"               "$(yml 1.1.2)"
check "release/v.1.2 は落ちる"                  1 "release/v.1.2"               "$(yml 1.1.2)"
check "release/v1.1.2/hotfix は落ちる"          1 "release/v1.1.2/hotfix"       "$(yml 1.1.2)"

echo "== 3. project.yml 側の異常は落ちる（黙って通さない）=="
check "MARKETING_VERSION が無い"                1 "release/v1.1.2" "$(yml)"
check "値が割れている"                          1 "release/v1.1.2" "$(yml 1.1.2 1.1.1)"
check "project.yml が無い"                      1 "release/v1.1.2" "$TMP/does-not-exist.yml"

echo "== 4. 同じ値が複数ターゲットにあるのは正常 =="
check "同値が2行あっても通る"                   0 "release/v1.1.2" "$(yml 1.1.2 1.1.2)"

echo "== 5. 引用符の有無で判定が変わらない =="
printf 'settings:\n        MARKETING_VERSION: 1.1.2\n' > "$TMP/bare.yml"
check "引用符なしでも一致とみなす"              0 "release/v1.1.2" "$TMP/bare.yml"
printf "settings:\n        MARKETING_VERSION: '1.1.2'\n" > "$TMP/single.yml"
check "シングルクォートでも一致とみなす"        0 "release/v1.1.2" "$TMP/single.yml"
# awk は空白区切りなので、CRLF 改行だと値の末尾に \r が残り一致しているのに落ちる
printf 'settings:\r\n        MARKETING_VERSION: "1.1.2"\r\n' > "$TMP/crlf.yml"
check "CRLF 改行でも一致とみなす"               0 "release/v1.1.2" "$TMP/crlf.yml"
printf 'settings:\r\n        MARKETING_VERSION: "1.1.1"\r\n' > "$TMP/crlf-ng.yml"
check "CRLF 改行でも不一致は落ちる"             1 "release/v1.1.2" "$TMP/crlf-ng.yml"

echo "== 6. 配信レーンから呼ばれている（仕込み忘れの検出）=="
FASTFILE="$SCRIPT_DIR/../../fastlane/Fastfile"
if grep -q "check-marketing-version.sh" "$FASTFILE"; then
  ok "fastlane の beta レーンが check-marketing-version.sh を呼んでいる"
else
  ng "fastlane の beta レーンが check-marketing-version.sh を呼んでいない"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
