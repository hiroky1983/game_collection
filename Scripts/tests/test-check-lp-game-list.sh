#!/bin/bash
# check-lp-game-list.sh の検証（#296）。
#
# このチェックは「LP に載っていないゲームのページが 404 のまま出荷される」のを防ぐ側なので、
# 見逃し（食い違いを通す）がそのまま #156 / #296 の再発になる。一方で誤検知（正常なのに落ちる）は
# LP の PR を止めるので、こちらも事故になる。実績のある落とし穴を固定するのが本テストの目的:
#   - registry のコメント（// 数独（#262）は末尾に足す）に現れる Module() を拾ってしまう
#   - LP の slug がアプリの id と意図的に違うケース（麻雀ソリティア: id は "mahjong"）で誤検知する
#   - リモートに無いローカルの release ブランチ（削除済み・番号付け替えの名残）を比較先に選ぶ
#
# 使い方: bash Scripts/tests/test-check-lp-game-list.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-lp-game-list.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -r -f "$TMP"' EXIT

# ------------------------------------------------------------------
# 検証用のリポジトリを組み立てる
# ------------------------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO"
cd "$REPO" || exit 1
git init -q .
git config user.email "test@example.com"
git config user.name "test"

# registry を書く。引数は `XxxModule()` に使う型名。コメントの中にも Module() と `])` を紛れ込ませ、
# コメント除去が効いていることを毎回見張る（効いていないと本数も終端位置も狂う）。
write_registry() {
  mkdir -p App
  {
    echo "@MainActor"
    echo "enum AppEnvironment {"
    echo "    /* ここは説明。DummyModule() と書いてあるが登録ではない"
    echo "       複数行のブロックコメント。ここに ]) があっても終端ではない */"
    echo "    static let registry = GameRegistry(["
    local m
    for m in "$@"; do echo "        ${m}(),"; done
    echo "        // 数独（#262）は末尾に足す。CommentOnlyModule() は登録ではない"
    echo "    ])"
    echo "}"
  } > App/AppGameServices.swift
}

# XxxModule.swift を書く。引数: 型名 id
write_module() {
  local dir="Packages/GameKit/Sources/$1"
  mkdir -p "$dir"
  {
    echo "import Core"
    echo "public struct $1: GameModule {"
    echo "    public let id = \"$2\""
    echo "}"
  } > "$dir/$1.swift"
}

# LP の games.ts 相当。引数は slug を並び順で。
write_lp() {
  local path="$TMP/games-$RANDOM$RANDOM.ts" s
  {
    echo "export const games: Game[] = ["
    for s in "$@"; do
      echo "  {"
      echo "    slug: \"$s\","
      echo "    name: \"$s\","
      echo "  },"
    done
    echo "];"
  } > "$path"
  printf '%s' "$path"
}

# 12本ぶんの registry（本番と同じ顔ぶれ・同じ順序）を用意する。
MODULES=(Game2048Module ShogiModule MahjongModule OthelloModule MahjongSolitaireModule
         DaifugoModule PokerModule BlackjackModule MinesweeperModule GomokuModule
         ConcentrationModule SudokuModule)
IDS=(2048 shogi mahjong4 othello mahjong daifugo poker blackjack minesweeper gomoku
     concentration sudoku)
# LP 側の期待値（麻雀ソリティアだけ id "mahjong" → slug "mahjong-solitaire"）
LP_SLUGS=(2048 shogi mahjong4 othello mahjong-solitaire daifugo poker blackjack
          minesweeper gomoku concentration sudoku)

write_registry "${MODULES[@]}"
for i in "${!MODULES[@]}"; do write_module "${MODULES[$i]}" "${IDS[$i]}"; done
git add -A >/dev/null
git commit -qm "12本"
git branch -q release/v1.1.2
# リモートに無いローカルの release ブランチ。番号の付け替え（docs/ai-devops.md 2026-08-24）の
# 名残として実際に残っていたもの。**比較先に選ばれてはいけない**ので、中身をわざと古くする。
git branch -q release/v1.1.9

git checkout -q release/v1.1.9
write_registry Game2048Module ShogiModule
git add -A >/dev/null
git commit -qm "古い registry（ローカルだけに残った版・2本）"
git checkout -q -

# origin を用意して release/v1.1.2 だけを remote 追跡ブランチとして持たせる。
BARE="$TMP/origin.git"
git init -q --bare "$BARE"
git remote add origin "$BARE"
git push -q origin release/v1.1.2

# 引数: 説明 / 期待する終了コード / games.ts / [ref]
check() {
  local desc="$1" want="$2" lp="$3" ref="${4:-}" got
  bash "$TARGET" "$ref" "$lp" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ng "${desc}（期待 ${want} / 実際 ${got}）"; fi
}

echo "check-lp-game-list.sh"

check "12本が一致すれば通る（ref 明示）" 0 "$(write_lp "${LP_SLUGS[@]}")" release/v1.1.2
check "1本足りないと落ちる（sudoku が 404 になるケース = #296）" 1 \
  "$(write_lp "${LP_SLUGS[@]:0:11}")" release/v1.1.2
check "アプリに無いゲームを載せていると落ちる" 1 \
  "$(write_lp "${LP_SLUGS[@]}" reversi)" release/v1.1.2
check "顔ぶれが同じでも並び順が違えば落ちる" 1 \
  "$(write_lp shogi 2048 mahjong4 othello mahjong-solitaire daifugo poker blackjack \
              minesweeper gomoku concentration sudoku)" release/v1.1.2
check "麻雀ソリティアの slug をアプリの id（mahjong）にすると落ちる（公開済み URL を守る）" 1 \
  "$(write_lp 2048 shogi mahjong4 othello mahjong daifugo poker blackjack minesweeper \
              gomoku concentration sudoku)" release/v1.1.2
check "registry を読めない ref は落ちる（黙って通さない）" 1 \
  "$(write_lp "${LP_SLUGS[@]}")" no-such-ref
check "games.ts が存在しなければ落ちる" 1 "$TMP/missing.ts" release/v1.1.2

# ref を省略したときの既定の比較先。origin/release/v1.1.2 を選ぶべきで、
# ローカルにしかない release/v1.1.9（中身は2本）を選んではいけない。
OUT="$(bash "$TARGET" "" "$(write_lp "${LP_SLUGS[@]}")" 2>&1)"
GOT=$?
if [ "$GOT" -eq 0 ] && printf '%s' "$OUT" | grep -q "origin/release/v1.1.2"; then
  ok "ref 省略時は remote 追跡ブランチを選ぶ（削除済みのローカル release を掴まない）"
else
  ng "ref 省略時の既定が誤り（exit=${GOT} / 出力: ${OUT}）"
fi

# release ブランチがどこにも無ければ「対象外」で通す（黙らずに理由は出す）。
NOREL="$TMP/norel"
git clone -q --branch release/v1.1.2 --single-branch "$BARE" "$NOREL" 2>/dev/null
cd "$NOREL" || exit 1
git checkout -q -b main
git branch -q -D release/v1.1.2 2>/dev/null
git remote remove origin
OUT="$(bash "$TARGET" "" "$(write_lp 2048)" 2>&1)"
GOT=$?
if [ "$GOT" -eq 0 ] && printf '%s' "$OUT" | grep -q "検証しません"; then
  ok "release ブランチが無ければ対象外として通す（理由は出力する）"
else
  ng "release ブランチ不在時の扱いが誤り（exit=${GOT} / 出力: ${OUT}）"
fi
cd "$REPO" || exit 1

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
