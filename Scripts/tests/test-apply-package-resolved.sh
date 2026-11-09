#!/bin/bash
# apply-package-resolved.sh の検証（#3416）。
#
# 依存の版固定（#1579）を担い、ビルド・QA・ASO 撮影・CI の 4 経路から呼ばれる。
# コピー先のパスや失敗時の終了コードが黙って変わると版固定が外れるため、
# 一時ディレクトリにスクリプトを置いて（ROOT はスクリプトの親から決まる）直接確かめる。
#
# 使い方: bash Scripts/tests/test-apply-package-resolved.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../apply-package-resolved.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

# 偽のリポジトリ根を作る。引数: ディレクトリ名 / Package.resolved を置くか(1|0) / .xcodeproj を置くか(1|0)
make_root() {
  local root="$TMP/$1"
  mkdir -p "$root/Scripts"
  cp "$TARGET" "$root/Scripts/apply-package-resolved.sh"
  if [ "$2" = 1 ]; then
    mkdir -p "$root/Config"
    echo '{"pins":[],"version":3}' >"$root/Config/Package.resolved"
  fi
  if [ "$3" = 1 ]; then mkdir -p "$root/GameCollection.xcodeproj"; fi
  echo "$root"
}

DEST_REL="GameCollection.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

echo "== 1. 正常系: 固定版が Xcode の読む場所へ置かれる =="
R="$(make_root ok 1 1)"
bash "$R/Scripts/apply-package-resolved.sh" >/dev/null 2>&1
rc=$?
[ "$rc" = 0 ] && ok "終了コード 0" || ng "終了コード 0 のはず（実際: ${rc}）"
if [ -f "$R/$DEST_REL" ] && cmp -s "$R/Config/Package.resolved" "$R/$DEST_REL"; then
  ok "$DEST_REL に Config/Package.resolved と同じ内容が置かれる"
else
  ng "$DEST_REL に Config/Package.resolved が置かれていない"
fi

echo "== 2. 再実行: 古い内容を上書きする =="
echo 'stale' >"$R/$DEST_REL"
bash "$R/Scripts/apply-package-resolved.sh" >/dev/null 2>&1
cmp -s "$R/Config/Package.resolved" "$R/$DEST_REL" && ok "既存のファイルを固定版で上書き" || ng "古い内容が残っている"

echo "== 3. Config/Package.resolved が無いと exit 1 =="
R="$(make_root nosrc 0 1)"
bash "$R/Scripts/apply-package-resolved.sh" >/dev/null 2>&1
rc=$?
[ "$rc" = 1 ] && ok "終了コード 1" || ng "終了コード 1 のはず（実際: ${rc}）"
[ ! -e "$R/$DEST_REL" ] && ok "何も配置されない" || ng "失敗したのに配置された"

echo "== 4. .xcodeproj が無いと exit 1 =="
R="$(make_root noproj 1 0)"
bash "$R/Scripts/apply-package-resolved.sh" >/dev/null 2>&1
rc=$?
[ "$rc" = 1 ] && ok "終了コード 1" || ng "終了コード 1 のはず（実際: ${rc}）"
[ ! -e "$R/GameCollection.xcodeproj" ] && ok ".xcodeproj を勝手に作らない" || ng ".xcodeproj が作られた"

echo
echo "結果: ok=$PASS NG=$FAIL"
[ "$FAIL" = 0 ]
