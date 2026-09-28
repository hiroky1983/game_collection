import Foundation
#if !GO_BENCH_STANDALONE
import CoreEngine
@testable import GameGo
#endif

/// 段階どうしの対局の計測（#1465）。`CPUBenchTests` と `Scripts/go-cpu-bench` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D GO_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない・デバッグビルドでは 9 路の対局が現実的な時間に収まらない）。
enum CPUBenchLadder {
    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        var games: Int { upperWins + lowerWins + draws }
        /// 上の段の得点率 =（勝ち + 引き分け × 0.5）÷ 全局数（会長決裁 2026-09-27）。
        var upperScore: Double { games == 0 ? 0 : (Double(upperWins) + Double(draws) * 0.5) / Double(games) }
    }

    /// 対局者。`nil` の段階は「眼を埋めない合法手から一様乱択で打つ相手」。
    struct Player {
        var level: GoLevel?
        /// 最善手を打つ確率の差し替え（`nil` なら出荷値）。
        var bestMoveChance: Double? = nil

        static func random() -> Player { Player(level: nil, bestMoveChance: nil) }

        /// 出荷の設定から実時間の上限だけ外した設定（回数の上限で打ち切るので結果が再現する）。
        func config(seed: UInt64) -> GoEngineConfig? {
            guard let level else { return nil }
            var config = GoEngineConfig.level(level, seed: seed)
            config.timeLimit = nil
            if let bestMoveChance { config.bestMoveChance = bestMoveChance }
            return config
        }
    }

    /// 1 局。黒が先手。序盤の 2 手（黒・白 1 手ずつ）は開始局面の番号から決まる乱数で打ち、局面をばらけさせる。
    static func play(upper: Player, lower: Player, upperIsBlack: Bool, opening: Int) -> Outcome {
        let ruleset = GoRuleset(size: 9)
        var state = GoState.initial(ruleset: ruleset)
        let seed = spread(UInt64(opening))
        var random = GoRandom(seed: seed)
        var plies = 0
        let limit = state.board.pointCount * GoPlayout.moveLimitFactor
        while !state.isTwoPassEnd, plies < limit {
            let upperToMove = (state.sideToMove == .black) == upperIsBlack
            let player = upperToMove ? upper : lower
            let move: GoMove
            if plies < 2 {
                let candidates = GoPlayout.candidateMoves(in: state)
                move = candidates[random.index(below: candidates.count)]
            } else if let config = player.config(seed: spread(seed &* 1_000 &+ UInt64(plies) &+ (upperIsBlack ? 0 : 500))) {
                move = GoEngine(config: config, ruleset: ruleset).bestMove(state: state)
            } else {
                move = GoPlayout.move(in: state, random: &random)
            }
            // 非合法手は反則負け（引き分けに数えると、エンジンの不具合が基準をすり抜ける）。
            guard state.play(move) == nil else { return upperToMove ? .lowerWon : .upperWon }
            plies += 1
        }
        guard let winner = GoScoring.score(board: state.board, ruleset: ruleset).winner else { return .draw }
        return (winner == .black) == upperIsBlack ? .upperWon : .lowerWon
    }

    static func spread(_ i: UInt64) -> UInt64 { (i &+ 1) &* 0x9E37_79B9_7F4A_7C15 }

    /// `upper` が `lower` に、開始局面 `firstOpening` から `openings` 個を先後入れ替えで戦う（openings × 2 局）。
    static func run(upper: Player, lower: Player, openings: Int, firstOpening: Int = 1,
                    concurrency: Int = 4) -> Tally {
        let jobs = (0..<openings).flatMap { i in [true, false].map { (firstOpening + i, $0) } }
        let shared = Shared()
        DispatchQueue.concurrentPerform(iterations: concurrency) { _ in
            while true {
                shared.lock.lock()
                guard shared.next < jobs.count else { shared.lock.unlock(); return }
                let (opening, upperIsBlack) = jobs[shared.next]
                shared.next += 1
                shared.lock.unlock()
                let outcome = play(upper: upper, lower: lower, upperIsBlack: upperIsBlack, opening: opening)
                shared.lock.lock()
                switch outcome {
                case .upperWon: shared.tally.upperWins += 1
                case .lowerWon: shared.tally.lowerWins += 1
                case .draw: shared.tally.draws += 1
                }
                shared.lock.unlock()
            }
        }
        return shared.tally
    }

    /// 並列の対局が共有する状態。`lock` を取ってから触る（Linux の Dispatch は `concurrentPerform` の
    /// クロージャを `@Sendable` にしているので、ローカル変数を書き換えられない）。
    private final class Shared: @unchecked Sendable {
        let lock = NSLock()
        var next = 0
        var tally = Tally()
    }

    static let ladder: [(name: String, upper: GoLevel, lower: GoLevel)] = [
        ("むずかしい 対 ふつう", .hard, .normal),
        ("ふつう 対 かんたん", .normal, .easy),
        ("かんたん 対 入門", .easy, .novice),
    ]
}
