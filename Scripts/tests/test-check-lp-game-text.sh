#!/bin/bash
# check-lp-game-text.py の検証（#2941）。
#
# このチェックは「LP の紹介文がアプリの文言とずれたまま公開される」のを防ぐ側なので、
# 見逃し（ずれを通す）が再発になる。一方、誤検知は LP の PR を止める。固定する落とし穴:
#   - ja と en の片方だけがずれているのを見逃す
#   - LP の slug がアプリの id と違う麻雀ソリティア（id "mahjong"）を照合対象から落とす
#   - 対応する Module が無い LP エントリ（comingSoon の未リリース分）で落ちる
#   - 文字列の途中に `\"` を含む LP の文言を読み違える
#   - xcstrings に英訳が無いのを黙って通す
#
# 使い方: bash Scripts/tests/test-check-lp-game-text.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-lp-game-text.py"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -r -f "$TMP"' EXIT
SRC="$TMP/Sources"

# Module と xcstrings を書く。引数: Target id ja en（en が空なら英訳なしの xcstrings）
write_module() {
  local d="$SRC/$1"
  mkdir -p "$d/Resources/Localization"
  {
    echo "public struct $1Module: GameModule {"
    echo "    public let id = \"$2\""
    echo "    public var description: String { tr(\"$3\") }"
    echo "}"
  } > "$d/$1Module.swift"
  if [ -n "$4" ]; then
    printf '{"strings":{"%s":{"localizations":{"en":{"stringUnit":{"state":"translated","value":"%s"}}}}}}\n' \
      "$3" "$4" > "$d/Resources/Localization/Localizable.xcstrings"
  else
    echo '{"strings":{}}' > "$d/Resources/Localization/Localizable.xcstrings"
  fi
}

# LP を書く。引数: slug tagline taglineEn を3つ組で並べる
write_lp() {
  local path="$TMP/games-$RANDOM$RANDOM.ts"
  {
    echo "export const games: Game[] = ["
    while [ $# -ge 3 ]; do
      echo "  {"
      echo "    slug: \"$1\","
      echo "    tagline:"
      echo "      \"$2\","
      echo "    taglineEn: \"$3\","
      echo "  },"
      shift 3
    done
    echo "];"
  } > "$path"
  printf '%s' "$path"
}

check() {
  local desc="$1" want="$2" lp="$3" got
  python3 "$TARGET" "$lp" "$SRC" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "${desc}（期待 ${want} / 実際 ${got}）"; fi
}

write_module GameA a "Aを遊ぼう" "Play A"
# Swift ソース・xcstrings の JSON・LP の TS のどれでも `\"` が同じ引用符を表す
write_module GameB mahjong '麻雀を \"組む\"' 'Build \"mahjong\"'

echo "check-lp-game-text.py"

check "ja・en とも一致すれば通る（麻雀ソリティアは slug を読み替え・引用符入りも読める）" 0 \
  "$(write_lp a "Aを遊ぼう" "Play A" mahjong-solitaire '麻雀を \"組む\"' 'Build \"mahjong\"')"
check "ja だけずれていると落ちる" 1 \
  "$(write_lp a "Aで遊ぼう" "Play A" mahjong-solitaire '麻雀を \"組む\"' 'Build \"mahjong\"')"
check "en だけずれていると落ちる" 1 \
  "$(write_lp a "Aを遊ぼう" "Play the A" mahjong-solitaire '麻雀を \"組む\"' 'Build \"mahjong\"')"
check "麻雀ソリティアの文言がずれていても見逃さない" 1 \
  "$(write_lp a "Aを遊ぼう" "Play A" mahjong-solitaire '麻雀を組む' 'Build \"mahjong\"')"
check "Module の無い LP エントリ（comingSoon の未リリース分）は照合しない" 0 \
  "$(write_lp a "Aを遊ぼう" "Play A" mahjong-solitaire '麻雀を \"組む\"' 'Build \"mahjong\"' soon "なんでも" "Anything")"

write_module GameC c "Cを遊ぼう" ""
check "xcstrings に英訳が無いと落ちる（黙って通さない）" 1 \
  "$(write_lp a "Aを遊ぼう" "Play A" mahjong-solitaire '麻雀を \"組む\"' 'Build \"mahjong\"' c "Cを遊ぼう" "Play C")"

python3 "$TARGET" "$TMP/none.ts" "$SRC" >/dev/null 2>&1 && ng "games.ts が無いのに通った" || ok "games.ts が読めなければ落ちる"
python3 "$TARGET" >/dev/null 2>&1 && ok "実リポジトリの LP がアプリの文言と一致" || ng "実リポジトリの LP がアプリの文言とずれている"

echo "結果: ok=$PASS ng=$FAIL"
[ "$FAIL" -eq 0 ]
