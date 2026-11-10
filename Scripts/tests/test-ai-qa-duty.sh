#!/bin/bash
# 自動QA当番（#2314）の検証: ゲーム ID の列挙と、開発当番・シミュレータ上限との排他。
#
# 使い方: bash Scripts/tests/test-ai-qa-duty.sh
#
# ai-qa-duty.sh は HOME / TMPDIR をテスト用ディレクトリに差し替えて本物のまま通す
# （test-ai-audit-window.sh と同じ方式）。ビルド・撮影・claude の起動より前の「見送り」経路だけを見るので、
# 偽の xcrun / gh を PATH 先頭（$HOME/.local/bin）に置く。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="$ROOT/Scripts/ai-qa-duty.sh"
PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

echo "== 0. 構文 =="
for f in Scripts/ai-qa-duty.sh Scripts/list-game-ids.sh; do
  if bash -n "$ROOT/$f"; then ok "bash -n $f"; else ng "bash -n $f"; fi
done
if plutil -lint "$ROOT/Scripts/com.asobiba.ai-qa.plist" >/dev/null 2>&1 || ! command -v plutil >/dev/null; then
  ok "plist が正しい"
else
  ng "plist が不正"
fi

echo "== 1. list-game-ids.sh: registry のコメントアウトされていない Module だけを ID にする =="
IDS=$(bash "$ROOT/Scripts/list-game-ids.sh" "$ROOT")
check "終了コード 0" "0" "$?"
EXPECT=$(awk '/static let registry = GameRegistry\(\[/{on=1; next} on && /^[[:space:]]*\]\)/{exit} on' "$ROOT/App/AppGameServices.swift" \
  | grep -cE '^[[:space:]]*[A-Za-z0-9]+Module\(\),')
check "ID の数 = コメントアウトされていない Module の行数" "$EXPECT" "$(echo "$IDS" | grep -c .)"
check "ID が重複しない" "$(echo "$IDS" | sort -u | wc -l | tr -d ' ')" "$(echo "$IDS" | wc -l | tr -d ' ')"
case "$IDS" in *minesweeper*) ok "minesweeper を含む" ;; *) ng "minesweeper を含まない" ;; esac
check "企画倉庫（コメントアウト）の roulette は含まない" "0" "$(echo "$IDS" | grep -c '^roulette$')"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ai-qa-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/repo"
mkdir -p "$FAKE/App" "$FAKE/Packages/GameKit/Sources/GameA"
cat >"$FAKE/App/AppGameServices.swift" <<'SWIFT'
    static let registry = GameRegistry([
        AModule(),
        // BModule(),
        CModule(),
    ])
SWIFT
echo '    public let id = "alpha"' >"$FAKE/Packages/GameKit/Sources/GameA/AModule.swift"
bash "$ROOT/Scripts/list-game-ids.sh" "$FAKE" >/dev/null 2>&1
check "ID を引けないモジュール（C）があれば終了コード 1" "1" "$?"
rm -f "$FAKE/App/AppGameServices.swift"
bash "$ROOT/Scripts/list-game-ids.sh" "$FAKE" >/dev/null 2>&1
check "registry が無ければ終了コード 1" "1" "$?"

echo "== 2. ai-qa-duty.sh: 開発当番が動いていれば見送り、当番のロックは壊さない =="
HOME_T="$TMP/home"
mkdir -p "$HOME_T/.local/bin" "$HOME_T/Library/Logs"
LOG="$HOME_T/Library/Logs/asobiba-ai-qa.log"
sleep 300 & LIVE=$!
trap 'kill $LIVE 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/asobiba-ai-duty.lock"; echo "$LIVE" >"$TMP/asobiba-ai-duty.lock/pid"
env HOME="$HOME_T" TMPDIR="$TMP" bash "$TARGET"
check "終了コード 0" "0" "$?"
check "「スロット1 が使用中」で見送る" "1" "$(grep -c 'スロット1 が使用中のため見送り' "$LOG")"
check "当番のロックは残る" "$LIVE" "$(cat "$TMP/asobiba-ai-duty.lock/pid")"
[ -d "$TMP/asobiba-ai-qa.lock" ] && ng "QA 自身のロックが残っている" || ok "QA 自身のロックは解放される"

echo "== 3. 死んだ当番のロックは回収して先へ進み、終了時に解放する =="
rm -rf "$TMP/asobiba-ai-duty.lock"; mkdir -p "$TMP/asobiba-ai-duty.lock"; echo 999999 >"$TMP/asobiba-ai-duty.lock/pid"
# 偽 xcrun: 起動中 2 台を返す → 上限で見送る（当番ロックを取った後の経路まで進んだことの確認）
cat >"$HOME_T/.local/bin/xcrun" <<'MOCK'
#!/bin/bash
if [ "$1 $2 $3" = "simctl list devices" ]; then printf '    A (X) (Booted)\n    B (Y) (Booted)\n'; fi
exit 0
MOCK
chmod +x "$HOME_T/.local/bin/xcrun"
: >"$LOG"
env HOME="$HOME_T" TMPDIR="$TMP" bash "$TARGET"
check "起動中 2 台なら上限で見送る" "1" "$(grep -c '2 台以上' "$LOG")"
[ -d "$TMP/asobiba-ai-duty.lock" ] && ng "取った当番ロックが終了時に残っている" || ok "取った当番ロックは終了時に解放される"

echo
echo "合計: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
