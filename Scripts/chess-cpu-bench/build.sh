#!/bin/bash
# チェス CPU の計測（#1462）を最適化ビルドの単体バイナリにして作る。
# `swift test -c release` は GameKit で通らず、デバッグビルドでは 1 手 2 秒の探索が現実の速さで測れないため。
# 使い方: bash Scripts/chess-cpu-bench/build.sh <出力先バイナリ>
# 走らせ方は main.swift の冒頭を参照。
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?出力先を渡してください}"
G=Packages/GameKit
WORK="$(mktemp -d "${DUTY_SCRATCH_DIR:-${TMPDIR:-/tmp}}/chess-bench-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# 単一モジュールにまとめるため、モジュール間の import を外したコピーを作る。
for f in $G/Sources/CoreEngine/{MMIXRandom,SplitMix64,CPUStrength,BookPicker}.swift \
         $G/Sources/GameChess/{ChessMove,ChessMoveGenerator,ChessOpeningBook,ChessPosition,ChessSquare,ChessTypes,ChessEngine}.swift \
         $G/Tests/GameChessTests/CPUBenchLadder.swift; do
  grep -v -e '^import CoreEngine$' -e '^import Core$' "$f" >"$WORK/$(basename "$f")"
done
cp Scripts/chess-cpu-bench/main.swift "$WORK/main.swift"
# CPUStrength が参照するだけの型（解析の本体は GameKit の CoreEngine にあり、計測には要らない）。
echo 'public enum AnalyticsLevel { case novice, beginner, normal, hard }' >"$WORK/AnalyticsLevelStub.swift"
# 文言の表（Core の StringTable・リソース読み込み）は計測に要らないので、日本語をそのまま返す（#3362）。
echo 'func tr(_ s: String) -> String { s }' >"$WORK/TrStub.swift"
# ヒント用エンジン（`SimpleChessEngine.hint`）が参照する値だけ。本体は順位表の型まで引き込むので写さない。
grep -h -E 'static let (engineLevel|extraThinkingTime)' $G/Sources/CoreEngine/BoardHintBudget.swift \
  | sed 's/public //' | { echo 'import Foundation'; echo 'enum BoardHintBudget {'; cat; echo '}'; } >"$WORK/BoardHintBudgetStub.swift"
swiftc -O -wmo -D CHESS_BENCH_STANDALONE -parse-as-library -o "$OUT" "$WORK"/*.swift 2>"$WORK/swiftc.log" \
  || { grep -v "warning:" "$WORK/swiftc.log" >&2; echo "ビルドに失敗しました" >&2; exit 1; }
