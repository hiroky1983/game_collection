import Testing
import Foundation
import CoreEngine
@testable import GameYonmoku

@Suite("四目並べの CPU")
struct YonmokuEngineTests {
    @Test("ビットボードの「4 つになる手」は盤の勝ち判定と一致する")
    func bitboardMatchesBoard() throws {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<200 {
            var board = YonmokuBoard()
            var disc = YonmokuDisc.black
            var finished = false
            while !finished, !board.isFull {
                let bits = YonmokuBits(board: board, toMove: disc)
                for col in board.playableColumns {
                    var copy = board
                    let dropped = copy.drop(disc, in: col)
                    let point = try #require(dropped)
                    #expect(bits.isWinningMove(col) == (copy.winningLine(through: point) != nil))
                }
                let cols = board.playableColumns
                let col = cols[Int(rng.next() % UInt64(cols.count))]
                let dropped = board.drop(disc, in: col)
                let point = try #require(dropped)
                finished = board.winningLine(through: point) != nil
                disc = disc.opponent
            }
        }
    }

    @Test("どの段階も、打てる列だけを返す（満杯の列は選ばない）", arguments: CPUStrength.allCases)
    func legalMovesOnly(strength: CPUStrength) throws {
        var rng = SplitMix64(seed: 7)
        for game in 0..<12 {
            var board = YonmokuBoard()
            var disc = YonmokuDisc.black
            while !board.isFull {
                let engine = YonmokuEngine(maxDepth: min(YonmokuEngine.settings(for: strength).depth, 4),
                                           timeLimit: 5, policy: YonmokuEngine.settings(for: strength).policy,
                                           seed: UInt64(game * 100 + board.discCount))
                let col = try #require(engine.bestMove(board: board, disc: disc))
                #expect(board.canDrop(in: col), "\(strength): 入らない列 \(col)")
                let dropped = board.drop(disc, in: col)
                let point = try #require(dropped)
                if board.winningLine(through: point) != nil { break }
                disc = disc.opponent
                // 半分くらいは無作為の手で進めて、いろいろな局面を通す。
                if rng.next() % 2 == 0, !board.isFull {
                    let cols = board.playableColumns
                    let dropped = board.drop(disc, in: cols[Int(rng.next() % UInt64(cols.count))])
                    let p = try #require(dropped)
                    if board.winningLine(through: p) != nil { break }
                    disc = disc.opponent
                }
            }
        }
    }

    @Test("満杯の列が混ざっても、残りの列から選ぶ。打てる列が無ければ nil")
    func fullColumns() throws {
        // 0〜5 列を埋めた（4 つ並ばない引き分け用の並びから 6 列ぶん）。残りは 6 列だけ。
        var board = YonmokuBoard()
        let starts: [YonmokuDisc] = [.black, .black, .white, .white, .black, .black]
        for (col, s) in starts.enumerated() {
            for row in 0..<YonmokuBoard.rows { board.drop(row % 2 == 0 ? s : s.opponent, in: col) }
        }
        for level in -1...2 {
            #expect(YonmokuEngine(level: level, seed: 1).bestMove(board: board, disc: .black) == 6)
        }
        let full = try #require(YonmokuBoard.replay(YonmokuRulesTests.drawMoves))
        #expect(YonmokuEngine(level: 2).bestMove(board: full, disc: .black) == nil)
    }

    @Test("かんたん以上は、あと 1 つで勝てるなら必ず勝つ", arguments: [0, 1, 2])
    func takesImmediateWin(level: Int) throws {
        // 黒が 1,2,3 列の一番下。黒の番で 0 か 4 で勝ち。
        let board = try #require(YonmokuBoard.replay([1, 1, 2, 2, 3, 6]))
        for seed in 0..<20 {
            let col = YonmokuEngine(level: level, seed: UInt64(seed)).bestMove(board: board, disc: .black)
            #expect(col == 0 || col == 4)
        }
    }

    @Test("かんたん以上は、相手の即勝ちを必ず止める", arguments: [0, 1, 2])
    func blocksImmediateThreat(level: Int) throws {
        // 黒がたてに 3 つ（0 列）。白の番。白は 0 列に入れないと負け。
        let board = try #require(YonmokuBoard.replay([0, 6, 0, 6, 0]))
        // むずかしいは乱数を使わないので 1 回で足りる（1 回 2 秒近く考える）。
        for seed in 0..<(level == 2 ? 1 : 20) {
            #expect(YonmokuEngine(level: level, seed: UInt64(seed)).bestMove(board: board, disc: .white) == 0)
        }
    }

    @Test("むずかしいは両側があいた 3 つ（どちらも止められない形）を先に作らせない")
    func hardPreventsOpenThree() throws {
        // 黒が 2,3 列の一番下。白の番。白が 1 か 4 を取らないと、黒は 1 か 4 で両側のあいた 3 つを作れる。
        let board = try #require(YonmokuBoard.replay([2, 6, 3]))
        let col = YonmokuEngine(level: 2).bestMove(board: board, disc: .white)
        #expect(col == 1 || col == 4)
    }

    @Test("入門は見のがしもする（同じ局面でも種によって止めない手を打つ）")
    func noviceSometimesMisses() throws {
        let board = try #require(YonmokuBoard.replay([0, 6, 0, 6, 0]))
        let picks = (0..<40).compactMap { YonmokuEngine(level: -1, seed: UInt64($0)).bestMove(board: board, disc: .white) }
        #expect(picks.contains(0), "止めることもある")
        #expect(picks.contains { $0 != 0 }, "見のがすこともある")
    }

    @Test("むずかしいは考える時間の上限（2 秒）を大きく超えない")
    func hardRespectsTimeLimit() throws {
        let board = try #require(YonmokuBoard.replay([3, 3, 2]))
        let start = Date()
        _ = YonmokuEngine(level: 2).bestMove(board: board, disc: .white)
        #expect(Date().timeIntervalSince(start) < 3.0)
    }

    @Test("時計が先に切れても、1 手目の読みが終わっていれば打てる列を返す")
    func timeoutFallsBack() throws {
        let board = try #require(YonmokuBoard.replay([3]))
        let engine = YonmokuEngine(maxDepth: 42, timeLimit: 0, policy: .exact, now: { Date() })
        let col = try #require(engine.bestMove(board: board, disc: .white))
        #expect(board.canDrop(in: col))
    }

    @Test("強さの順: ふつうは入門に、むずかしい（深さを抑えた版）はかんたんに大きく勝ち越す")
    func strengthOrder() throws {
        let novice = YonmokuEngine.settings(for: .novice)
        let easy = YonmokuEngine.settings(for: .easy)
        let normal = YonmokuEngine.settings(for: .normal)
        // テストの時間を抑えるため、むずかしいは深さ 8 に抑えて比べる（本番は時間の許す限り深く読む）。
        let normalVsNovice = Self.score(
            strong: { YonmokuEngine(maxDepth: normal.depth, timeLimit: 5, policy: normal.policy, seed: $0) },
            weak: { YonmokuEngine(maxDepth: novice.depth, timeLimit: 5, policy: novice.policy, seed: $0) },
            games: 10)
        let hardVsEasy = Self.score(
            strong: { _ in YonmokuEngine(maxDepth: 8, timeLimit: 5, policy: .exact) },
            weak: { YonmokuEngine(maxDepth: easy.depth, timeLimit: 5, policy: easy.policy, seed: $0) },
            games: 10)
        #expect(normalVsNovice >= 0.8, "ふつう対入門の得点率 \(normalVsNovice)")
        #expect(hardVsEasy >= 0.8, "むずかしい対かんたんの得点率 \(hardVsEasy)")
    }

    /// 強い側の得点率（勝ち 1・引き分け 0.5）。先手・後手を交互に入れ替える。
    static func score(strong: (UInt64) -> YonmokuEngine, weak: (UInt64) -> YonmokuEngine, games: Int) -> Double {
        var points = 0.0
        for g in 0..<games {
            let strongIsBlack = g % 2 == 0
            var board = YonmokuBoard()
            var disc = YonmokuDisc.black
            var winner: YonmokuDisc?
            while !board.isFull, winner == nil {
                let isStrong = (disc == .black) == strongIsBlack
                let seed = UInt64(g * 1000 + board.discCount)
                let engine = isStrong ? strong(seed) : weak(seed)
                guard let col = engine.bestMove(board: board, disc: disc),
                      let point = board.drop(disc, in: col) else { break }
                if board.winningLine(through: point) != nil { winner = disc }
                disc = disc.opponent
            }
            let strongDisc: YonmokuDisc = strongIsBlack ? .black : .white
            if winner == strongDisc { points += 1 } else if winner == nil { points += 0.5 }
        }
        return points / Double(games)
    }
}
