import Foundation
#if !GOMOKU_BENCH_STANDALONE
import CoreEngine
@testable import GameGomoku
#endif

/// 段階どうしの総当たり計測（#1399）。`CPUBenchTests` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D GOMOKU_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない・デバッグビルドでは探索の対局が現実的な時間に収まらない）。
enum CPUBenchLadder {
    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        var games: Int { upperWins + lowerWins + draws }
    }

    /// 先手の利が出ない開始局面（黒 2 子・白 1 子で白番）。黒の 2 子は 3 マス以上離し、白は黒の 1 子目の隣に置く。
    /// 先手が連を作れる形から始めると、後手の段階が強くても先手の下の段階が偶然勝ってしまい、段階の差を測れない。
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

    /// 1 局。黒が先手。`upperIsBlack` で上の段階の先後を決める。エンジンは手ごとに種の違うものを作る。
    static func play(upper: (Int) -> SimpleGomokuEngine, lower: (Int) -> SimpleGomokuEngine,
                     upperIsBlack: Bool, opening: GomokuBoard) async -> Outcome {
        var board = opening
        var stone = GomokuStone.black
        let placedAtStart = board.cells.filter { $0 != nil }.count
        stone = placedAtStart % 2 == 0 ? .black : .white
        var ply = 0
        while board.cells.contains(where: { $0 == nil }) {
            let upperToMove = (stone == .black) == upperIsBlack
            let engine = upperToMove ? upper(ply) : lower(ply)
            guard let (r, c) = await engine.bestMove(board: board, stone: stone), board[r, c] == nil else {
                return upperToMove ? .lowerWon : .upperWon  // 手を返せない・非合法は反則負け
            }
            board[r, c] = stone
            if board.checkWin(row: r, col: c) {
                if !upperToMove { print("LOSS \(upperIsBlack ? "上=黒" : "上=白") \(ply) 手目 \(board.cells.map { $0 == nil ? "." : ($0 == .black ? "x" : "o") }.joined())") }
                return upperToMove ? .upperWon : .lowerWon
            }
            stone = stone.opponent
            ply += 1
        }
        return .draw
    }

    /// 連番の種をそのまま渡すと MMIX の出目が似通うので、散らばった種にする。
    static func spread(_ i: UInt64) -> UInt64 { (i &+ 1) &* 0x9E37_79B9_7F4A_7C15 }

    /// `upper` が `lower` に、先後を入れ替えて `openings` 通り × 2 局戦う。
    static func run(upperLevel: Int, lowerLevel: Int, openings: Int, concurrency: Int = 4) async -> Tally {
        var tally = Tally()
        let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(i + 1), $0) } }
        var next = 0
        await withTaskGroup(of: Outcome.self) { group in
            func add() {
                guard next < jobs.count else { return }
                let (seed, upperIsBlack) = jobs[next]
                next += 1
                group.addTask {
                    await play(
                        upper: { SimpleGomokuEngine(level: upperLevel, seed: CPUBenchLadder.spread(seed &* 100_000 &+ UInt64($0) &* 2 &+ 1)) },
                        lower: { SimpleGomokuEngine(level: lowerLevel, seed: CPUBenchLadder.spread(seed &* 100_000 &+ UInt64($0) &* 2 &+ 2)) },
                        upperIsBlack: upperIsBlack, opening: opening(seed: seed))
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

    static let pairs: [(name: String, upper: CPUStrength, lower: CPUStrength)] = [
        ("簡単 対 入門", .easy, .novice),
        ("ふつう 対 簡単", .normal, .easy),
        ("むずかしい 対 ふつう", .hard, .normal),
    ]
}
