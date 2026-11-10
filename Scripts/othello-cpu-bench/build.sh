#!/bin/bash
# オセロ CPU の計測（#1464）を最適化ビルドの単体バイナリにして作る。
# `swift test -c release` は GameKit で通らず、デバッグビルドでは 1 手 1.5 秒の探索が現実の速さで測れないため。
# 使い方: bash Scripts/othello-cpu-bench/build.sh <出力先バイナリ>
# 走らせ方は main.swift の冒頭を参照。
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?出力先を渡してください}"
G=Packages/GameKit
WORK="$(mktemp -d "${DUTY_SCRATCH_DIR:-${TMPDIR:-/tmp}}/othello-bench-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# 単一モジュールにまとめるため、モジュール間の import を外したコピーを作る。
for f in $G/Sources/CoreEngine/{SplitMix64,CPUStrength,BoardHintBudget}.swift \
         $G/Sources/GameOthello/{OthelloTypes,OthelloEngine}.swift \
         $G/Tests/GameOthelloTests/CPUBenchLadder.swift; do
  grep -v -E '^import (Core|CoreEngine)$' "$f" >"$WORK/$(basename "$f")"
done
cp Scripts/othello-cpu-bench/main.swift "$WORK/main.swift"
# CPUStrength が参照するだけの型（解析の本体は GameKit の CoreEngine にあり、計測には要らない）。
# CPUStrength.label が呼ぶ翻訳関数（本物は Core の StringTable。計測には文字列が要らない）と、
# ヒントの回数制（BoardHintBudget）が成績の型として参照する GameScore（本物の PlayRecord.swift は AppLanguage 等を引くので写せない）。
echo 'public enum AnalyticsLevel { case novice, beginner, normal, hard }' >"$WORK/AnalyticsLevelStub.swift"
echo 'func tr(_ s: String, _ args: CVarArg...) -> String { s }' >>"$WORK/AnalyticsLevelStub.swift"
echo 'public enum RecordMetric { case winLoss }; public struct GameScore { public var variant: String?; public var variantLabel: String?; public init(metric: RecordMetric, isLeaderboardEligible: Bool) {} }' >>"$WORK/AnalyticsLevelStub.swift"
# BoardHintBudget が段階の表示名を引く RecordVariantLabels（本物は AppLanguage 等を引くので、計測には要らない文字列を返す写し）。
echo 'enum RecordVariantLabels { static func stored(gameID: String, variant: String) -> String { variant } }' >>"$WORK/AnalyticsLevelStub.swift"
swiftc -O -wmo -D OTHELLO_BENCH_STANDALONE -parse-as-library -o "$OUT" "$WORK"/*.swift 2>"$WORK/swiftc.log" \
  || { grep -v "warning:" "$WORK/swiftc.log" >&2; echo "ビルドに失敗しました" >&2; exit 1; }
