#!/bin/bash
# おじさんちのねこさがしの同梱ステージ（`CatPuzzleStageBank`・#3223）の問題を、最適化ビルドで作る単体バイナリを作る。
# デバッグビルドの `swift test` では 10 倍ほど遅く、12×12 は 1 問に数分かかるため。
# 使い方: bash Scripts/catpuzzle-stage-bank/build.sh <出力先バイナリ>
#         <出力先バイナリ> <最初の面> <最後の面> [何個おき] [何番目]   （面を複数のプロセスに分けるとき: 4 個おきの 0 番目…）
# 1 面 1 行で `面番号<TAB>部屋|解` を標準出力へ出す。行は `CatPuzzleStageBank.entries` と同じ書式。
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?出力先を渡してください}"
G=Packages/GameKit/Sources
WORK="$(mktemp -d "${TMPDIR:-/tmp}/catpuzzle-stage-bank.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for f in $G/CoreEngine/SplitMix64.swift \
         $G/GameCatPuzzle/{CatPuzzleLogic,CatPuzzleSolver,CatPuzzleStage}.swift; do
  grep -v -E '^import (Core|CoreEngine)$' "$f" >"$WORK/$(basename "$f")"
done
# CatPuzzleStage.makePuzzle が参照する同梱の入れ物（ここでは使わない）。
cat >"$WORK/BankStub.swift" <<'SWIFT'
enum CatPuzzleStageBank { static func puzzle(for number: Int) -> CatPuzzle? { nil } }
SWIFT
cp Scripts/catpuzzle-stage-bank/main.swift "$WORK/main.swift"
swiftc -O -wmo -o "$OUT" "$WORK"/*.swift 2>"$WORK/swiftc.log" \
  || { grep -v "warning:" "$WORK/swiftc.log" >&2; echo "ビルドに失敗しました" >&2; exit 1; }
