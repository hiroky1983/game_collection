import Foundation
#if !GOMOKU_BENCH_STANDALONE
import CoreEngine
@testable import GameGomoku
#endif

/// 段階どうしの総当たり計測（#1399・#1463）。`CPUBenchTests` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D GOMOKU_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`Scripts/gomoku-cpu-bench`。`swift test -c release` は通らず、デバッグビルドでは探索の対局が現実的な時間に収まらない）。
enum CPUBenchLadder {
    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        var games: Int { upperWins + lowerWins + draws }
        /// 上の段の得点率（勝ち + 引き分け × 0.5）÷ 全局数。
        var upperScore: Double { games == 0 ? 0 : (Double(upperWins) + Double(draws) * 0.5) / Double(games) }
    }

    /// 先手の利が出ない開始局面（黒 2 子・白 1 子で白番）。黒の 2 子は 3 マス以上離し、白は黒の 1 子目の隣に置く。
    /// 先手が連を作れる形から始めると、後手の段階が強くても先手の下の段階が偶然勝ってしまい、段階の差を測れない。
    /// 種ごとに石の位置を乱数で変えるので、同じ対局の繰り返しにならない（先後を入れ替えた 2 局だけが同じ開始局面）。
    static func opening(seed: UInt64) -> GomokuBoard {
        var rng = MMIXRandom(state: seed &* 0x9E3779B97F4A7C15 &+ 1)
        let mid = gomokuBoardSize / 2
        func near(_ r: Int, _ c: Int, _ radius: Int) -> (Int, Int) {
            (r - radius + Int(rng.next() % UInt64(2 * radius + 1)), c - radius + Int(rng.next() % UInt64(2 * radius + 1)))
        }
        while true {
            let first = near(mid, mid, 1)
            let white = near(first.0, first.1, 1)
            let second = near(mid, mid, 4)
            guard white != first, max(abs(second.0 - first.0), abs(second.1 - first.1)) >= 3, second != white else { continue }
            var board = GomokuBoard()
            board[first.0, first.1] = .black
            board[white.0, white.1] = .white
            board[second.0, second.1] = .black
            return board
        }
    }

    /// 手ごとに、種の違うエンジンを作る（実機は種なしで毎回違う乱数）。`nil` を渡した側は合法手（空いている交点）から一様乱択する。
    typealias EngineFactory = @Sendable (_ seed: UInt64) -> SimpleGomokuEngine

    /// 連番の種をそのまま渡すと MMIX の出目が似通うので、散らばった種にする。
    static func spread(_ i: UInt64) -> UInt64 { (i &+ 1) &* 0x9E37_79B9_7F4A_7C15 }

    /// 1 局。黒が先手。`upperIsBlack` で上の段階の先後を決める。盤が埋まったら引き分け。
    static func play(upper: @escaping EngineFactory, lower: EngineFactory?, seed: UInt64,
                     upperIsBlack: Bool, opening: GomokuBoard) async -> Outcome {
        var board = opening
        var stone: GomokuStone = board.cells.filter { $0 != nil }.count % 2 == 0 ? .black : .white
        var rng = MMIXRandom(state: spread(seed &* 7 &+ 3))
        var ply = 0
        while board.cells.contains(where: { $0 == nil }) {
            let upperToMove = (stone == .black) == upperIsBlack
            let r: Int, c: Int
            if let factory = upperToMove ? upper : lower {
                let engineSeed = spread(seed &* 100_000 &+ UInt64(ply) &* 2 &+ (upperToMove ? 1 : 2))
                guard let m = await factory(engineSeed).bestMove(board: board, stone: stone), board[m.row, m.col] == nil else {
                    return upperToMove ? .lowerWon : .upperWon  // 手を返せない・非合法は反則負け
                }
                (r, c) = m
            } else {
                let empty = board.cells.indices.filter { board.cells[$0] == nil }
                let pick = empty[Int(rng.next() % UInt64(empty.count))]
                (r, c) = (pick / gomokuBoardSize, pick % gomokuBoardSize)
            }
            board[r, c] = stone
            if board.checkWin(row: r, col: c) { return upperToMove ? .upperWon : .lowerWon }
            stone = stone.opponent
            ply += 1
        }
        return .draw
    }

    /// `upper` が `lower` に、先後を入れ替えて `openings` 通り × 2 局戦う。
    /// `firstOpening` は最初の開始局面の番号（計測を小分けにして続きから回すため）。
    static func run(upper: @escaping EngineFactory, lower: EngineFactory?, openings: Int,
                    concurrency: Int = 4, firstOpening: Int = 1) async -> Tally {
        var tally = Tally()
        let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(firstOpening + i), $0) } }
        var next = 0
        await withTaskGroup(of: Outcome.self) { group in
            func add() {
                guard next < jobs.count else { return }
                let (seed, upperIsBlack) = jobs[next]
                next += 1
                group.addTask {
                    await play(upper: upper, lower: lower, seed: seed, upperIsBlack: upperIsBlack, opening: opening(seed: seed))
                }
            }
            for _ in 0..<concurrency { add() }
            for await outcome in group {
                switch outcome {
                case .upperWon: tally.upperWins += 1
                case .lowerWon: tally.lowerWins += 1
                case .draw: tally.draws += 1
                }
                add()
            }
        }
        return tally
    }

    /// 出荷している段階の設定で、考える時間を「読む局面数」に置き換えたエンジン。
    /// `nodesPerSecond` は最適化ビルドで測った 1 秒あたりの局面数。時間で打ち切ると同時に走る対局の
    /// 負荷で強さが揺れるので、計測の対局は局面数で打ち切る（実機の時間で読める量と等しい）。
    /// `bestMoveProbability` を渡すと、その段階の確率だけを差し替える（確率の候補を試すため）。
    static func engine(_ strength: CPUStrength, nodesPerSecond: Double, bestMoveProbability: Double? = nil,
                       seed: UInt64) -> SimpleGomokuEngine {
        let shipped = SimpleGomokuEngine(level: strength.rawValue)
        return SimpleGomokuEngine(
            level: strength.rawValue, seed: seed, timeLimit: .infinity,
            nodeLimit: Int(shipped.timeLimit * nodesPerSecond),
            policy: bestMoveProbability.map(SimpleGomokuEngine.policy))
    }
}
