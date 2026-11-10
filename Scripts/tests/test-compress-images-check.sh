#!/bin/bash
# compress-images.py の --check/--dry-run の検証（#2913）。通常実行の検証は test-compress-images.sh（#2838）。
#
# `--check` は未圧縮の画像を含む PR を CI で落とす側なので、見逃し（書き換えが要るのに 0 枚と
# 報告する）も誤検知（MIN_BYTES 未満まで数える）もそのまま事故になる。実際に PNG を生成して
# 通常実行・--dry-run・--check の3モードを直接確かめる。
#
# python は NODE_OPTIONS があると落ちるため env -u で外す（#2913 と同じ事情）。
#
# 使い方: bash Scripts/tests/test-compress-images.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../compress-images.py"
FIXTURES="$SCRIPT_DIR/fixtures/make-compress-images-fixtures.py"
PY() { env -u NODE_OPTIONS python3 "$@"; }

# Pillow が無い環境は skip する（test-compress-images.sh と同じ流儀。CI は scripts-tests.yml で入れる）
if ! PY -c "import PIL" 2>/dev/null; then
  echo "SKIP: Pillow が無いため compress-images.py の --check テストを飛ばします"
  exit 0
fi
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

reset_tree() {
  rm -rf "$TMP/root"
  PY "$FIXTURES" "$TMP/root" >/dev/null
}

echo "== --check: 未圧縮があれば落ちる =="
reset_tree
before_big="$(wc -c < "$TMP/root/big.png")"
before_tiny="$(wc -c < "$TMP/root/tiny.png")"
out="$(PY "$TARGET" --check "$TMP/root" 2>&1)"
got=$?
if [ "$got" = 1 ]; then ok "未圧縮が1枚あれば終了コード1"; else ng "未圧縮が1枚あれば終了コード1（実際: ${got}）"; fi
if printf '%s' "$out" | grep -q "big.png"; then ok "未圧縮のファイル名を一覧する"; else ng "未圧縮のファイル名を一覧する"; fi
if printf '%s' "$out" | grep -q "compress-images.py$"; then ok "直すコマンドを出す"; else ng "直すコマンドを出す"; fi
after_big="$(wc -c < "$TMP/root/big.png")"
if [ "$before_big" = "$after_big" ]; then ok "--check は書き換えない"; else ng "--check は書き換えない（${before_big} -> ${after_big}）"; fi

echo "== --check: MIN_BYTES 未満は対象外 =="
if printf '%s' "$out" | grep -q "tiny.png"; then ng "小さい画像まで数える"; else ok "小さい画像は数えない"; fi
after_tiny="$(wc -c < "$TMP/root/tiny.png")"
if [ "$before_tiny" = "$after_tiny" ]; then ok "小さい画像も書き換えない"; else ng "小さい画像も書き換えない"; fi

echo "== --dry-run: 書き換えないが報告はする =="
reset_tree
before="$(wc -c < "$TMP/root/big.png")"
out="$(PY "$TARGET" --dry-run "$TMP/root" 2>&1)"
got=$?
after="$(wc -c < "$TMP/root/big.png")"
if [ "$got" = 0 ]; then ok "--dry-run の終了コードは0"; else ng "--dry-run の終了コードは0（実際: ${got}）"; fi
if [ "$before" = "$after" ]; then ok "--dry-run は書き換えない"; else ng "--dry-run は書き換えない"; fi
if printf '%s' "$out" | grep -q "big.png"; then ok "--dry-run も対象を報告する"; else ng "--dry-run も対象を報告する"; fi

echo "== 通常実行: 書き換えて --check が通るようになる =="
reset_tree
before="$(wc -c < "$TMP/root/big.png")"
PY "$TARGET" "$TMP/root" >/dev/null
after="$(wc -c < "$TMP/root/big.png")"
msg="通常実行は書き換えて小さくする（${before} -> ${after}）"
if [ "$after" -lt "$before" ]; then ok "$msg"; else ng "$msg"; fi
out="$(PY "$TARGET" --check "$TMP/root" 2>&1)"
got=$?
if [ "$got" = 0 ] && printf '%s' "$out" | grep -q "未圧縮の画像はありません"; then
  ok "圧縮後は --check が通る"
else
  ng "圧縮後は --check が通る（終了コード ${got}）"
fi

echo "== CI の差分抽出: リネームだけの PNG も検査対象になる（#3072） =="
CI_YML="$SCRIPT_DIR/../../.github/workflows/ci.yml"
filters="$(grep -o -e '--diff-filter=[A-Z]*' "$CI_YML" | sort -u)"
if [ "$filters" = "--diff-filter=AMR" ]; then
  ok "ci.yml の画像検査は --diff-filter=AMR（全箇所）"
else
  ng "ci.yml の画像検査は --diff-filter=AMR（実際: ${filters}）"
fi
GIT_REPO="$TMP/gitrepo"
mkdir -p "$GIT_REPO/d"
PY "$FIXTURES" "$TMP/gitfix" >/dev/null
cp "$TMP/gitfix/big.png" "$GIT_REPO/a.png"
(
  cd "$GIT_REPO" && git init -q && git add -A &&
    git -c user.name=t -c user.email=t@t commit -q -m base &&
    git mv a.png d/a.png && git add -A &&
    git -c user.name=t -c user.email=t@t commit -q -m rename
)
renamed="$(git -C "$GIT_REPO" diff --name-only --diff-filter=AMR HEAD~1 HEAD -- '*.png')"
if [ "$renamed" = "d/a.png" ]; then ok "リネーム先の PNG が抽出される"; else ng "リネーム先の PNG が抽出される（実際: ${renamed}）"; fi

echo
echo "結果: ok $PASS / NG $FAIL"
[ "$FAIL" -eq 0 ]
