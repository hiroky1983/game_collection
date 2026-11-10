#!/bin/bash
# 将棋 達人（#2698）の計測を最適化ビルドの単体バイナリにして作る（`shogi-cpu-bench` と同じ作り方）。
# GameKit 全体は Linux で通らない（SwiftUI・CoreEngine の並行性の制約）が、将棋のエンジンは純ロジックなので、
# 必要なファイルだけを 1 モジュールにまとめれば Linux（クラウド）でも動く。
# 使い方: bash Scripts/shogi-master-bench/build.sh <出力先バイナリ>
# 走らせ方は main.swift の冒頭を参照。
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?出力先を渡してください}"
G=Packages/GameKit
WORK="$(mktemp -d "${DUTY_SCRATCH_DIR:-${TMPDIR:-/tmp}}/shogi-master-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for f in $G/Sources/CoreEngine/{MMIXRandom,SplitMix64,BookPicker,CPUStrength,BoardHintBudget}.swift \
         $G/Sources/GameShogi/{Move,MoveGenerator,OpeningBook,Position,ShogiSquare,ShogiTypes,ShogiEngine,ShogiMateSearch,ShogiMasterEngine}.swift \
         $G/Tests/GameShogiTests/CPUBenchLadder.swift; do
  grep -v '^import CoreEngine$' "$f" >"$WORK/$(basename "$f")"
done
cp Scripts/shogi-master-bench/main.swift "$WORK/main.swift"
# CPUStrength・BoardHintBudget が参照するだけの型と関数（本物は Core・CoreEngine にあり、計測には要らない。`shogi-cpu-bench` と同じ写し）。
cat >"$WORK/BenchStubs.swift" <<'SWIFT'
public enum AnalyticsLevel { case novice, beginner, normal, hard }
func tr(_ s: String, _ args: CVarArg...) -> String { s }
public enum RecordMetric { case winLoss }
public struct GameScore { public var variant: String?; public var variantLabel: String?; public init(metric: RecordMetric, isLeaderboardEligible: Bool) {} }
enum RecordVariantLabels { static func stored(gameID: String, variant: String) -> String { variant } }
SWIFT
swiftc -O -wmo -D SHOGI_BENCH_STANDALONE -parse-as-library -o "$OUT" "$WORK"/*.swift 2>"$WORK/swiftc.log" \
  || { grep -v "warning:" "$WORK/swiftc.log" >&2; echo "ビルドに失敗しました" >&2; exit 1; }
