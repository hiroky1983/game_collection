import Foundation
#if !GO_BENCH_STANDALONE
import CoreEngine
@testable import GameGo
#endif

/// 段階どうしの総当たり計測（#1400）。`CPUBenchTests` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D GO_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない・デバッグビルドでは 9 路の対局が現実的な時間に収まらない）。
enum CPUBenchLadder {
    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        var games: Int { upperWins + lowerWins + draws }
    }

    /// 1 局。黒が先手。序盤の 2 手（黒・白 1 手ずつ）は乱数で決め、局面をばらけさせる。
    /// エンジンの設定は実運用と同じ `GoEngineConfig.level`（実時間の上限だけ外して再現性を保つ）。
    static func play(upper: GoLevel, lower: GoLevel, upperIsBlack: Bool, seed: UInt64) -> Outcome {
        let ruleset = GoRuleset(size: 9)
        var state = GoState.initial(ruleset: ruleset)
        var random = GoRandom(seed: seed)
        var plies = 0
        let limit = state.board.pointCount * GoPlayout.moveLimitFactor
        while !state.isTwoPassEnd, plies < limit {
            let move: GoMove
            if plies < 2 {
                let candidates = GoPlayout.candidateMoves(in: state)
                move = candidates[random.index(below: candidates.count)]
            } else {
                let upperToMove = (state.sideToMove == .black) == upperIsBlack
                var config = GoEngineConfig.level(upperToMove ? upper : lower, seed: spread(seed &* 1_000 &+ UInt64(plies)))
                config.timeLimit = nil
                move = GoEngine(config: config, ruleset: ruleset).bestMove(state: state)
            }
            guard state.play(move) == nil else { return .draw }
            plies += 1
        }
        guard let winner = GoScoring.score(board: state.board, ruleset: ruleset).winner else { return .draw }
        return (winner == .black) == upperIsBlack ? .upperWon : .lowerWon
    }

    static func spread(_ i: UInt64) -> UInt64 { (i &+ 1) &* 0x9E37_79B9_7F4A_7C15 }

    /// `upper` が `lower` に、先後を入れ替えて `pairs` 組 × 2 局戦う。
    static func run(upper: GoLevel, lower: GoLevel, pairs: Int, concurrency: Int = 4) -> Tally {
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
                let outcome = play(upper: upper, lower: lower, upperIsBlack: upperIsBlack, seed: spread(seed))
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

    static let ladder: [(name: String, upper: GoLevel, lower: GoLevel)] = [
        ("簡単 対 入門", .easy, .novice),
        ("ふつう 対 簡単", .normal, .easy),
        ("むずかしい 対 ふつう", .hard, .normal),
    ]
}
