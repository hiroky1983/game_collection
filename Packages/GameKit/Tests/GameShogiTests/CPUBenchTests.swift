import Testing
import Foundation
import CoreEngine
@testable import GameShogi

/// CPU 同士の対局・所要時間の計測（#1397・#1461）。**CI と通常の `swift test` では走らせない**
/// （環境変数 `CPU_BENCH=1` を付けたときだけ動く）。
///
/// 確率の根拠になる 200 局の総当たりは、最適化ビルドの単体バイナリで回す（`Scripts/shogi-cpu-bench`。
/// `swift test -c release` は通らず、デバッグビルドでは 1 手 3 秒の探索が現実の速さで測れない）。
/// ここには、デバッグビルドでも回せる小さい確認だけを置く。
///
/// 実行例: `CPU_BENCH=1 swift test --package-path Packages/GameKit --filter CPUBenchTests`
enum CPUBench {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CPU_BENCH"] == "1" }
}

@Suite("将棋 CPU の計測（CPU_BENCH=1 のときだけ）", .serialized)
struct CPUBenchTests {
    /// 出荷の設定（実時間）で 1 手にかかる時間が、段階の上限を大きく超えないこと（ヒントは「むずかしい」と同じ）。
    /// デバッグビルドは遅いので余裕を見る。平均・最大・上限で打ち切られた割合の実測は単体バイナリ（`timing`）。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(30)))
    func eachMoveStaysWithinItsTimeLimit() async {
        let sfen = "lnsgkgsnl/1r5b1/ppppppppp/9/9/2P6/PP1PPPPPP/1B5R1/LNSGKGSNL w - 2"
        for strength in CPUStrength.allCases {
            let engine = SimpleMinimaxEngine(level: strength.rawValue)
            let t = Date()
            _ = await engine.bestMove(sfen: sfen)
            let elapsed = Date().timeIntervalSince(t)
            print("BENCH \(strength.label): \(String(format: "%.2f", elapsed)) 秒（上限 \(engine.timeLimit) 秒）")
            #expect(elapsed < engine.timeLimit + 1.0, "\(strength.label) が上限を超えた: \(elapsed)")
        }
    }
}
