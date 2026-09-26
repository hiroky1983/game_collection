import Testing
import Foundation
import CoreEngine
@testable import GameGomoku

/// CPU 同士の対局・探索の計測（#1399）。**CI と通常の `swift test` では走らせない**
/// （環境変数 `CPU_BENCH=1` を付けたときだけ動く）。
///
/// 実行例: `CPU_BENCH=1 swift test --package-path Packages/GameKit --filter CPUBenchTests`
/// （デバッグビルドでは遅いので、対局は `swiftc -O -D GOMOKU_BENCH_STANDALONE` の単体バイナリでも回せる）
enum CPUBench {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CPU_BENCH"] == "1" }
}

@Suite("五目並べ CPU の計測（CPU_BENCH=1 のときだけ）", .serialized)
struct CPUBenchTests {
    /// 隣り合う段階どうしを先後入れ替えで戦わせ、**上の段階の負けが 0** であることを確かめる
    /// （会長決裁 2026-09-25）。1 組 `CPU_BENCH_OPENINGS`（既定 12）局面 × 先後 = 24 局。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(240)))
    func upperStageNeverLosesToLowerStage() async {
        let openings = Int(ProcessInfo.processInfo.environment["CPU_BENCH_OPENINGS"] ?? "") ?? 12
        for pair in CPUBenchLadder.pairs {
            let t = await CPUBenchLadder.run(upperLevel: pair.upper.rawValue, lowerLevel: pair.lower.rawValue,
                                             openings: openings)
            print("BENCH \(pair.name): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)")
            #expect(t.lowerWins == 0, "\(pair.name): 上の段階が \(t.lowerWins) 局負けた")
        }
    }

    /// 段階ごとの読み（序盤〜中盤の局面での局面数・読み切った深さ）。局面数の上限を決める材料。
    @Test(.enabled(if: CPUBench.enabled), .timeLimit(.minutes(60)))
    func nodesAndDepthPerStage() async {
        var boards: [GomokuBoard] = []
        for seed in 1...6 {
            var board = CPUBenchLadder.opening(seed: UInt64(seed))
            var stone = GomokuStone.black
            for ply in 0..<30 {
                if ply % 6 == 5 { boards.append(board) }
                guard let (r, c) = await SimpleGomokuEngine(level: CPUStrength.easy.rawValue, seed: UInt64(seed * 1000 + ply))
                    .bestMove(board: board, stone: stone), board[r, c] == nil else { break }
                board[r, c] = stone
                if board.checkWin(row: r, col: c) { break }
                stone = stone.opponent
            }
        }
        for level in [CPUStrength.normal, .hard] {
            var nodes: [Int] = [], depths: [Int] = []
            var seconds = 0.0
            for (i, board) in boards.enumerated() {
                let stone: GomokuStone = board.cells.filter { $0 != nil }.count % 2 == 0 ? .black : .white
                let t = Date()
                let r = SimpleGomokuEngine(level: level.rawValue, seed: UInt64(i)).analyze(board: board, stone: stone)
                seconds += Date().timeIntervalSince(t)
                nodes.append(r.nodes); depths.append(r.depth)
            }
            nodes.sort(); depths.sort()
            print("BENCH \(level.label): 局面 \(boards.count) 局面数 中央値 \(nodes[nodes.count / 2]) 最大 \(nodes.last!) / 読み切った深さ 中央値 \(depths[depths.count / 2]) 最小 \(depths.first!) / 平均秒 \(seconds / Double(boards.count))")
        }
    }
}
