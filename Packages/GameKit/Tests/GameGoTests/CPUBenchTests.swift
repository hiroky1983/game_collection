import Testing
import Foundation
@testable import GameGo

/// CPU 同士の対局の計測（#1465）。**CI と通常の `swift test` では走らせない**
/// （環境変数 `CPU_BENCH=1` を付けたときだけ動く）。
///
/// 実行例: `CPU_BENCH=1 swift test --package-path Packages/GameKit --filter CPUBenchTests`
/// （デバッグビルドでは遅いので、段階表の計測は `Scripts/go-cpu-bench` の最適化ビルドの単体バイナリで回した）
enum CPUBench {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CPU_BENCH"] == "1" }
}

@Suite("囲碁 CPU の計測（CPU_BENCH=1 のときだけ）", .serialized)
struct CPUBenchTests {
    /// 隣り合う段階どうしを先後入れ替えで戦わせ、**上の段の得点率（勝ち + 引き分け × 0.5）が 90% 以上**で
    /// あることを確かめる（会長決裁 2026-09-27）。1 組 `CPU_BENCH_PAIRS`（既定 20）組 × 先後 = 40 局。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(240)))
    func upperStageScoresNinetyPercent() {
        let pairs = Int(ProcessInfo.processInfo.environment["CPU_BENCH_PAIRS"] ?? "") ?? 20
        for stage in CPUBenchLadder.ladder {
            let t = CPUBenchLadder.run(upper: .init(level: stage.upper), lower: .init(level: stage.lower), openings: pairs)
            print("BENCH \(stage.name): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)")
            #expect(t.upperScore >= 0.9, "\(stage.name): 上の段の得点率が \(t.upperScore)")
        }
    }

    /// 入門は一様乱択の相手（眼は埋めない）に先後入れ替え 100 局で 8 割以上勝つ（#1465）。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(240)))
    func noviceBeatsRandomPlayer() {
        let t = CPUBenchLadder.run(upper: .init(level: .novice), lower: .random(), openings: 50)
        print("BENCH 入門 対 一様乱択: \(t.games)局 勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)")
        #expect(Double(t.upperWins) >= Double(t.games) * 0.8)
    }
}
