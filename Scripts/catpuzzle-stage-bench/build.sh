#!/bin/bash
# おじさんちのねこさがしのステージ（#3048）を作る時間と難しさを測る単体バイナリを、最適化ビルドで作る。
# デバッグビルドの `swift test` では生成が実機より 10 倍ほど遅く、端末での待ち時間の目安にならないため。
# 使い方: bash Scripts/catpuzzle-stage-bench/build.sh <出力先バイナリ>
#         <出力先バイナリ> [最初の面] [最後の面]   （既定 1〜60）
# 1 面ごとに「番号・盤・段・点数・段ごとの回数・作るのにかかった秒」を出し、最後に盤ごとの最長の秒を出す。
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?出力先を渡してください}"
G=Packages/GameKit/Sources
WORK="$(mktemp -d "${TMPDIR:-/tmp}/catpuzzle-stage-bench.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# 単一モジュールにまとめるため、モジュール間の import を外したコピーを作る。
for f in $G/CoreEngine/SplitMix64.swift \
         $G/GameCatPuzzle/{CatPuzzleLogic,CatPuzzleSolver,CatPuzzleStage}.swift; do
  grep -v -E '^import (Core|CoreEngine)$' "$f" >"$WORK/$(basename "$f")"
done
cp Scripts/catpuzzle-stage-bench/main.swift "$WORK/main.swift"
swiftc -O -wmo -o "$OUT" "$WORK"/*.swift 2>"$WORK/swiftc.log" \
  || { grep -v "warning:" "$WORK/swiftc.log" >&2; echo "ビルドに失敗しました" >&2; exit 1; }
