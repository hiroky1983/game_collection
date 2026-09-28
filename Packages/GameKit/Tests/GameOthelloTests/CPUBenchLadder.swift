import Foundation
#if !OTHELLO_BENCH_STANDALONE
import CoreEngine
@testable import GameOthello
#endif

/// 段階どうしの総当たり計測（#1401・#1464）。`CPUBenchTests` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D OTHELLO_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない。`Scripts/othello-cpu-bench`）。
enum CPUBenchLadder {
    /// 乱数で決める序盤の手数（黒白 3 手ずつ）。最善手の確率が 100% の段どうしは同じ局面から同じ対局になるので、
    /// 開始局面をばらして別の対局にする（6 手で 8,200 通りほど）。
    static let openingPlies = 6

    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        /// 終局時の石差（下の段 − 上の段）の合計。平均は `lowerDiscDiffSum / games`。
        var lowerDiscDiffSum = 0
        var games: Int { upperWins + lowerWins + draws }
        /// 上の段の得点率（勝ち + 引き分け × 0.5）÷ 全局数（会長決裁 2026-09-27）。
        var upperScore: Double { games == 0 ? 0 : (Double(upperWins) + Double(draws) * 0.5) / Double(games) }
    }

    /// 手ごとに、種の違うエンジンを作る（実機は種なしで毎回違う乱数）。`nil` を渡した側は合法手から一様乱択する。
    typealias EngineFactory = @Sendable (_ seed: UInt64) -> OthelloEngine

    /// 開始局面: 初期配置から `openingPlies` 手を乱数で進めた盤面と、次に打つ石。
    static func opening(seed: UInt64) -> (board: OthelloBoard, turn: OthelloStone) {
        var board = OthelloBoard()
        var turn = OthelloStone.black
        var rng = SplitMix64(seed: seed &* 0x2545_F491_4F6C_DD1D)
        for _ in 0..<openingPlies {
            let moves = board.validMoves(for: turn)
            guard !moves.isEmpty else { break }
            let m = moves[Int(rng.next() % UInt64(moves.count))]
            board.place(row: m.0, col: m.1, stone: turn)
            turn = turn.opponent
        }
        return (board, turn)
    }

    /// 1 局。返り値は勝敗と、終局時の石差（下の段 − 上の段）。
    static func play(upper: @escaping EngineFactory, lower: EngineFactory?, upperIsBlack: Bool,
                     seed: UInt64) -> (Outcome, lowerDiscDiff: Int) {
        var (board, turn) = opening(seed: seed)
        var rng = SplitMix64(seed: seed &* 7 &+ 3)
        var ply = 0
        var passes = 0
        while passes < 2 {
            let moves = board.validMoves(for: turn)
            if moves.isEmpty {
                passes += 1
                turn = turn.opponent
                continue
            }
            passes = 0
            let upperToMove = (turn == .black) == upperIsBlack
            let move: (Int, Int)
            if let factory = upperToMove ? upper : lower {
                let engineSeed = seed &* 100_000 &+ UInt64(ply) &* 2 &+ (upperToMove ? 1 : 2)
                guard let m = factory(engineSeed).move(board: board, stone: turn),
                      board.isValid(row: m.row, col: m.col, stone: turn) else { break }
                move = (m.row, m.col)
            } else {
                move = moves[Int(rng.next() % UInt64(moves.count))]
            }
            board.place(row: move.0, col: move.1, stone: turn)
            turn = turn.opponent
            ply += 1
        }
        let black = board.count(for: .black), white = board.count(for: .white)
        let upperDiscs = upperIsBlack ? black : white, lowerDiscs = upperIsBlack ? white : black
        let outcome: Outcome = upperDiscs == lowerDiscs ? .draw : (upperDiscs > lowerDiscs ? .upperWon : .lowerWon)
        return (outcome, lowerDiscs - upperDiscs)
    }

    /// `upper` が `lower` に、先後を入れ替えて `openings` 通り × 2 局戦う。
    /// `firstOpening` は最初の開始局面の番号（計測を小分けにして続きから回すため）。
    static func run(upper: @escaping EngineFactory, lower: EngineFactory?, openings: Int,
                    concurrency: Int = 4, firstOpening: Int = 1) -> Tally {
        let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(firstOpening + i), $0) } }
        let shared = Shared()
        DispatchQueue.concurrentPerform(iterations: max(1, concurrency)) { _ in
            while let (seed, upperIsBlack) = shared.nextJob(jobs) {
                let (outcome, diff) = play(upper: upper, lower: lower, upperIsBlack: upperIsBlack, seed: seed)
                shared.record(outcome, diff)
            }
        }
        return shared.tally
    }

    /// 同時に走る対局が共有する状態（次の対局の番号と集計）。`lock` の中でだけ触る。
    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var next = 0
        private(set) var tally = Tally()

        func nextJob(_ jobs: [(UInt64, Bool)]) -> (UInt64, Bool)? {
            lock.lock(); defer { lock.unlock() }
            guard next < jobs.count else { return nil }
            next += 1
            return jobs[next - 1]
        }

        func record(_ outcome: Outcome, _ lowerDiscDiff: Int) {
            lock.lock(); defer { lock.unlock() }
            switch outcome {
            case .upperWon: tally.upperWins += 1
            case .lowerWon: tally.lowerWins += 1
            case .draw: tally.draws += 1
            }
            tally.lowerDiscDiffSum += lowerDiscDiff
        }
    }

    /// 出荷している段階の設定で、考える時間を「読む局面数」に置き換えたエンジン。
    /// `nodesPerSecond` は最適化ビルドで測った 1 秒あたりの局面数。時間で打ち切ると同時に走る対局の
    /// 負荷で強さが揺れるので、計測の対局は局面数で打ち切る（実機の時間で読める量と等しい）。
    /// `bestMoveProbability` を渡すと、その段階の確率だけを差し替える（確率の候補を試すため）。
    static func engine(_ strength: CPUStrength, nodesPerSecond: Double, bestMoveProbability: Double? = nil,
                       seed: UInt64) -> OthelloEngine {
        let shipped = OthelloEngine.settings(for: strength)
        var policy = shipped.policy
        if let p = bestMoveProbability {
            policy.bestMoveProbability = p
            if policy.slipMargin == 0 { policy.slipMargin = OthelloEngine.slipMargin }  // 「むずかしい」の確率を下げて試すとき
        }
        return OthelloEngine(level: strength.rawValue, timeLimitOverride: .infinity,
                             nodeLimit: Int(shipped.timeLimit * nodesPerSecond), policy: policy, seed: seed)
    }

    /// 隣り合う段階（上 → 下）。
    static let ladder: [(name: String, upper: CPUStrength, lower: CPUStrength)] = [
        ("むずかしい 対 ふつう", .hard, .normal),
        ("ふつう 対 かんたん", .normal, .easy),
        ("かんたん 対 入門", .easy, .novice),
    ]
}
