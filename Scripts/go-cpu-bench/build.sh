#!/bin/bash
# 囲碁 CPU の計測（#1465）を最適化ビルドの単体バイナリにして作る。
# `swift test -c release` は GameKit で通らず、デバッグビルドでは 9 路の対局が現実の速さで測れないため。
# 使い方: bash Scripts/go-cpu-bench/build.sh <出力先バイナリ>
# 走らせ方は main.swift の冒頭を参照。
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?出力先を渡してください}"
G=Packages/GameKit
WORK="$(mktemp -d "${DUTY_SCRATCH_DIR:-${TMPDIR:-/tmp}}/go-bench-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# 単一モジュールにまとめるため、モジュール間の import を外したコピーを作る。
for f in $G/Sources/CoreEngine/{SplitMix64,CPUStrength,BoardHintBudget}.swift \
         $G/Sources/GameGo/{GoEngine,GoPlayout,GoRandom,GoRules,GoScoring,GoTypes}.swift \
         $G/Tests/GameGoTests/CPUBenchLadder.swift; do
  grep -v '^import CoreEngine$' "$f" >"$WORK/$(basename "$f")"
done
cp Scripts/go-cpu-bench/main.swift "$WORK/main.swift"
# CPUStrength が参照するだけの型（解析の本体は GameKit の CoreEngine にあり、計測には要らない）。
# CPUStrength.label が呼ぶ翻訳関数（本物は Core の StringTable。計測には文字列が要らない）と、
# ヒントの回数制（BoardHintBudget）が成績の型として参照する GameScore（本物の PlayRecord.swift は AppLanguage 等を引くので写せない）。
echo 'public enum AnalyticsLevel { case novice, beginner, normal, hard }' >"$WORK/AnalyticsLevelStub.swift"
echo 'func tr(_ s: String, _ args: CVarArg...) -> String { s }' >>"$WORK/AnalyticsLevelStub.swift"
echo 'public enum RecordMetric { case winLoss }; public struct GameScore { public init(metric: RecordMetric, isLeaderboardEligible: Bool) {} }' >>"$WORK/AnalyticsLevelStub.swift"
swiftc -O -wmo -D GO_BENCH_STANDALONE -parse-as-library -o "$OUT" "$WORK"/*.swift 2>"$WORK/swiftc.log" \
  || { grep -v "warning:" "$WORK/swiftc.log" >&2; echo "ビルドに失敗しました" >&2; exit 1; }
