import Testing
import Foundation
import CoreEngine
@testable import GameChess

/// CPU 同士の対局・所要時間の計測（#1398・#1462）。**CI と通常の `swift test` では走らせない**
/// （環境変数 `CPU_BENCH=1` を付けたときだけ動く）。
///
/// 確率の根拠になる総当たりは、最適化ビルドの単体バイナリで回す（`Scripts/chess-cpu-bench`。
/// `swift test -c release` は通らず、デバッグビルドでは 1 手 2 秒の探索が現実の速さで測れない）。
/// ここには、デバッグビルドでも回せる小さい確認だけを置く。
///
/// 実行例: `CPU_BENCH=1 swift test --package-path Packages/GameKit --filter CPUBenchTests`
enum CPUBench {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CPU_BENCH"] == "1" }
}

@Suite("チェス CPU の計測（CPU_BENCH=1 のときだけ）", .serialized)
struct CPUBenchTests {
    /// 出荷の設定（実時間）で 1 手にかかる時間が、段階の上限を大きく超えないこと（ヒントは「むずかしい」と同じ）。
    /// デバッグビルドは遅いので余裕を見る。平均・最大・上限で打ち切られた割合の実測は単体バイナリ（`timing`）。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(30)))
    func eachMoveStaysWithinItsTimeLimit() async {
        // 定跡に載っている局面だと「むずかしい」が探索せず即答してしまうので、乱数で進めた中盤を使う。
        let fen = CPUBenchLadder.opening(seed: 3, plies: 20).toFEN()
        for strength in CPUStrength.allCases {
            let engine = SimpleChessEngine(level: strength.rawValue)
            let t = Date()
            _ = await engine.bestMove(fen: fen)
            let elapsed = Date().timeIntervalSince(t)
            print("BENCH \(strength.label): \(String(format: "%.2f", elapsed)) 秒（上限 \(engine.timeLimit) 秒）")
            #expect(elapsed < engine.timeLimit + 1.0, "\(strength.label) が上限を超えた: \(elapsed)")
        }
    }
}
