import Foundation
import Testing
import Core
@testable import GameGomoku

/// 最後の根手の評価中に時間切れになった深さの結果は採用しない（#1226）。
/// 実時間は使わず、`now` を注入して「N 回目の呼び出しから期限切れ」を決定的に作る。
@Suite("五目並べ 反復深化の時間切れ（#1226）")
struct GomokuIterativeDeepeningTests {

    /// 石が散らばった中盤（即勝ち・即ブロックが無く、探索が実際に走る局面）。
    private static func midgame() -> GomokuBoard {
        var b = GomokuBoard()
        let black = [(7, 7), (8, 8), (6, 8), (7, 9), (9, 7)]
        let white = [(7, 8), (8, 7), (6, 7), (8, 9), (7, 6)]
        for (r, c) in black { b[r, c] = .black }
        for (r, c) in white { b[r, c] = .white }
        return b
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private let expireAfter: Int?
        private let base = Date()
        init(expireAfter: Int?) { self.expireAfter = expireAfter }
        var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
        func now() -> Date {
            lock.lock(); calls += 1; let c = calls; lock.unlock()
            if let expireAfter, c > expireAfter { return base.addingTimeInterval(1_000_000) }
            return base
        }
    }

    private func run(maxDepth: Int, expireAfter: Int?) async -> (move: (row: Int, col: Int)?, calls: Int) {
        let clock = Clock(expireAfter: expireAfter)
        let engine = SimpleGomokuEngine(level: CPUStrength.hard.rawValue, seed: nil,
                                        maxDepth: maxDepth, now: clock.now)
        let move = await engine.bestMove(board: Self.midgame(), stone: .black)
        return (move, clock.callCount)
    }

    @Test("深さ2の途中（最後の根手を含む）で期限切れになっても、深さ1の結果を使う")
    func expiryDuringDepthTwoFallsBackToDepthOne() async throws {
        let depth1 = await run(maxDepth: 1, expireAfter: nil)
        let depth2 = await run(maxDepth: 2, expireAfter: nil)
        let r1 = try #require(depth1.move)
        try #require(depth2.calls > depth1.calls + 4, "前提が崩れている: 深さ2の探索が短すぎる")

        var mismatches: [Int] = []
        for n in depth1.calls..<depth2.calls {
            let r = await run(maxDepth: 2, expireAfter: n)
            if r.move?.row != r1.row || r.move?.col != r1.col { mismatches.append(n) }
        }
        #expect(mismatches.isEmpty, "期限切れ後に深さ1以外の手を採用している（呼び出し \(mismatches) 回目以降で切れた場合）")
    }
}
