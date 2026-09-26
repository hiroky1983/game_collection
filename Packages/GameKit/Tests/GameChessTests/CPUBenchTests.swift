import Testing
import Foundation
import CoreEngine
@testable import GameChess

/// CPU 同士の対局・探索の計測（#1398）。**CI と通常の `swift test` では走らせない**
/// （環境変数 `CPU_BENCH=1` を付けたときだけ動く）。
///
/// 実行例: `CPU_BENCH=1 swift test --package-path Packages/GameKit --filter CPUBenchTests`
enum CPUBench {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CPU_BENCH"] == "1" }

    /// 入門どうしで指した対局から、序盤〜終盤の局面を集める（局面の偏りを避けるため種を変える）。
    static func midgamePositions(seeds: [UInt64], plies: [Int]) async -> [String] {
        var out: [String] = []
        for seed in seeds {
            let engine = SimpleChessEngine(level: CPUStrength.novice.rawValue, seed: seed)
            var pos = ChessPosition.start()
            for ply in 0...(plies.max() ?? 0) {
                if plies.contains(ply) { out.append(pos.toFEN()) }
                guard let uci = await engine.bestMove(fen: pos.toFEN()), let m = ChessMove.fromUCI(uci) else { break }
                _ = pos.make(m)
            }
        }
        return out
    }
}

@Suite("チェス CPU の計測（CPU_BENCH=1 のときだけ）", .serialized)
struct CPUBenchTests {
    /// 各深さを最後まで読み切るのに要した局面数（中盤 20 局面）。段階ごとの読む局面数の上限を決める材料。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(60)))
    func nodesNeededPerDepth() async {
        let fens = await CPUBench.midgamePositions(seeds: [1, 2, 3, 4], plies: [10, 20, 30, 40, 50])
        for depth in 2...6 {
            var counts: [Int] = []
            var seconds: [Double] = []
            for fen in fens {
                let e = SimpleChessEngine(depth: depth, usePositional: true, useQuiescence: true,
                                          useBook: false, timeLimit: .infinity)
                let t = Date()
                guard let r = e.analyze(fen: fen) else { continue }
                seconds.append(Date().timeIntervalSince(t))
                counts.append(r.nodes)
            }
            counts.sort()
            print("BENCH depth \(depth): 局面数 中央値 \(counts[counts.count / 2]) 最小 \(counts.first!) 最大 \(counts.last!) / 平均秒 \(seconds.reduce(0, +) / Double(seconds.count))")
        }
    }

    /// 隣り合う段階どうしを先後入れ替えで戦わせ、**上の段階の負けが 0** であることを確かめる
    /// （会長決裁 2026-09-25）。1 組 24 局（開始 6 手を乱数で進めた 12 局面 × 先後）。
    /// 深い探索の対局はデバッグビルドでは現実的な時間に収まらない（`swiftc -O` 単体バイナリ参照）。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(240)))
    func upperStageNeverLosesToLowerStage() async {
        let openings = Int(ProcessInfo.processInfo.environment["CPU_BENCH_OPENINGS"] ?? "") ?? 12
        for pair in CPUBenchLadder.pairs {
            let t = await CPUBenchLadder.run(upperLevel: pair.upper.rawValue, lowerLevel: pair.lower.rawValue,
                                             openings: openings, maxPlies: 150)
            print("BENCH \(pair.name): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)（うち下が駒得 \(t.drawsLowerAhead)）")
            #expect(t.lowerWins == 0, "\(pair.name): 上の段階が \(t.lowerWins) 局負けた")
        }
    }
}
