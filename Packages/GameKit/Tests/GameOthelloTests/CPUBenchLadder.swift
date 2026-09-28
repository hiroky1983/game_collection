import Foundation
#if !OTHELLO_BENCH_STANDALONE
import CoreEngine
@testable import GameOthello
#endif

/// 段階どうしの総当たり計測（#1401）。`CPUBenchTests` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D OTHELLO_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない）。
enum CPUBenchLadder {
    /// 乱数で決める序盤の手数。エンジンが乱数を使わない段は同じ局面から同じ対局になるので、少ないと同じ対局を数え直すだけになる。
    static let openingPlies = 4

    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        var games: Int { upperWins + lowerWins + draws }
    }

    /// 1 局。黒が先手。オセロのエンジンは乱数を使わず、同じ局面には必ず同じ手を返すので、
    /// 序盤の 4 手（黒白 2 手ずつ）を乱数で決めて局面をばらけさせる。
    static func play(upper: CPUStrength, lower: CPUStrength, upperIsBlack: Bool, seed: UInt64) -> Outcome {
        var board = OthelloBoard()
        var turn = OthelloStone.black
        var rng = SplitMix(seed: seed)
        var plies = 0
        var passes = 0
        while passes < 2 {
            let moves = board.validMoves(for: turn)
            if moves.isEmpty {
                passes += 1
                turn = turn.opponent
                continue
            }
            passes = 0
            let move: (Int, Int)
            if plies < openingPlies {
                move = moves[Int(rng.next() % UInt64(moves.count))]
            } else {
                let upperToMove = (turn == .black) == upperIsBlack
                let engine = OthelloEngine(level: (upperToMove ? upper : lower).rawValue)
                guard let m = engine.move(board: board, stone: turn) else { break }
                move = (m.row, m.col)
            }
            board.place(row: move.0, col: move.1, stone: turn)
            turn = turn.opponent
            plies += 1
        }
        let black = board.count(for: .black), white = board.count(for: .white)
        if black == white { return .draw }
        return (black > white) == upperIsBlack ? .upperWon : .lowerWon
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// `upper` が `lower` に、先後を入れ替えて `pairs` 組 × 2 局戦う。
    static func run(upper: CPUStrength, lower: CPUStrength, pairs: Int, concurrency: Int = 4) -> Tally {
        let jobs = (0..<pairs).flatMap { i in [true, false].map { (UInt64(i + 1), $0) } }
        let lock = NSLock()
        var tally = Tally()
        var next = 0
        DispatchQueue.concurrentPerform(iterations: concurrency) { _ in
            while true {
                lock.lock()
                guard next < jobs.count else { lock.unlock(); return }
                let (seed, upperIsBlack) = jobs[next]
                next += 1
                lock.unlock()
                let outcome = play(upper: upper, lower: lower, upperIsBlack: upperIsBlack, seed: seed)
                lock.lock()
                switch outcome {
                case .upperWon: tally.upperWins += 1
                case .lowerWon: tally.lowerWins += 1
                case .draw: tally.draws += 1
                }
                lock.unlock()
            }
        }
        return tally
    }

    static let ladder: [(name: String, upper: CPUStrength, lower: CPUStrength)] = [
        ("簡単 対 入門", .easy, .novice),
        ("ふつう 対 簡単", .normal, .easy),
        ("むずかしい 対 ふつう", .hard, .normal),
    ]
}
