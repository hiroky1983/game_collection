import Testing
import Foundation
@testable import GameGo

/// CPU 同士の対局の計測（#1400）。**CI と通常の `swift test` では走らせない**
/// （環境変数 `CPU_BENCH=1` を付けたときだけ動く）。
///
/// 実行例: `CPU_BENCH=1 swift test --package-path Packages/GameKit --filter CPUBenchTests`
/// （デバッグビルドでは遅いので、対局は `swiftc -O -D GO_BENCH_STANDALONE` の単体バイナリでも回せる）
enum CPUBench {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CPU_BENCH"] == "1" }
}

@Suite("囲碁 CPU の計測（CPU_BENCH=1 のときだけ）", .serialized)
struct CPUBenchTests {
    /// 隣り合う段階どうしを先後入れ替えで戦わせ、**上の段階の負けが対局数の 3% 以下**であることを確かめる
    /// （会長決裁 2026-09-26。引き分けは負けに数えない）。1 組 `CPU_BENCH_PAIRS`（既定 20）組 × 先後 = 40 局。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(240)))
    func upperStageRarelyLosesToLowerStage() {
        let pairs = Int(ProcessInfo.processInfo.environment["CPU_BENCH_PAIRS"] ?? "") ?? 20
        for stage in CPUBenchLadder.ladder {
            let t = CPUBenchLadder.run(upper: stage.upper, lower: stage.lower, pairs: pairs)
            print("BENCH \(stage.name): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)")
            #expect(Double(t.lowerWins) <= Double(t.games) * 0.03, "\(stage.name): 上の段階が \(t.lowerWins)/\(t.games) 局負けた")
        }
    }
}
