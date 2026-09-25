import Foundation
#if !SHOGI_BENCH_STANDALONE
import CoreEngine
@testable import GameShogi
#endif

/// 段階どうしの総当たり計測（#1397）。`CPUBenchTests` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D SHOGI_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない・デバッグビルドでは深さ 5 の対局が現実的な時間に収まらない）。
enum CPUBenchLadder {
    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        /// 引き分け（手数上限）のうち、下の段階が駒得で上回っていた局（参考値）。
        var drawsLowerAhead = 0
        var games: Int { upperWins + lowerWins + draws }
    }

    /// 開始局面から `plies` 手を乱数で進めた局面（対局の多様性を作る）。駒得が偏った局面
    /// （乱数の手で駒を取られた・詰んだ）は、先後を入れ替えても片方の段階に不利な出発になるので
    /// 引き直す（駒の価値の差が歩 1 枚以内になるまで）。
    static func opening(seed: UInt64, plies: Int = 6) -> Position {
        var rng = MMIXRandom(seed: seed)
        for _ in 0..<200 {
            var pos = Position.start()
            var finished = false
            for _ in 0..<plies {
                let moves = pos.legalMoves()
                guard !moves.isEmpty else { finished = true; break }
                pos.make(moves[Int(rng.next() % UInt64(moves.count))])
            }
            if !finished && abs(material(pos)) <= PieceValue.base(.pawn) { return pos }
        }
        return Position.start()
    }

    static func material(_ pos: Position) -> Int {
        var s = 0
        for sq in 0..<Sq.count {
            guard let p = pos.squares[sq], p.type != .king else { continue }
            s += (p.color == .black ? 1 : -1) * PieceValue.onBoard(p)
        }
        for type in PieceType.allCases where type.isDroppable {
            s += pos.hands[Side.black.rawValue][type.rawValue] * PieceValue.base(type)
            s -= pos.hands[Side.white.rawValue][type.rawValue] * PieceValue.base(type)
        }
        return s
    }

    /// 1 局。返り値の Bool は「手数上限で終わり、下の段階が駒得で上回っていた」。
    /// 種を渡した同じエンジンは同じ手番なら同じ見逃しの目を引くので、エンジンは手ごとに作り直す
    /// （`upper` / `lower` は手数を受け取って種の違うエンジンを返す。実機は種なしで毎回違う乱数）。
    static func play(upper: (Int) -> SimpleMinimaxEngine, lower: (Int) -> SimpleMinimaxEngine,
                     upperIsBlack: Bool, opening: Position, maxPlies: Int) async -> (Outcome, lowerAhead: Bool) {
        var pos = opening
        for ply in 0..<maxPlies {
            let moves = pos.legalMoves()
            if moves.isEmpty {
                let upperLost = (pos.sideToMove == .black) == upperIsBlack
                if upperLost { print("LOSS 詰まされた局面 \(pos.toSFEN()) 駒得(先手視点) \(material(pos)) 上は\(upperIsBlack ? "先手" : "後手")") }
            return (upperLost ? .lowerWon : .upperWon, false)
            }
            let upperToMove = (pos.sideToMove == .black) == upperIsBlack
            let engine = upperToMove ? upper(ply) : lower(ply)
            guard let usi = await engine.bestMove(sfen: pos.toSFEN()),
                  let move = Move.fromUSI(usi), moves.contains(move) else {
                return (upperToMove ? .lowerWon : .upperWon, false)  // 手を返せない・非合法は反則負け
            }
            pos.make(move)
        }
        let blackLead = material(pos)
        let lowerLead = upperIsBlack ? -blackLead : blackLead
        return (.draw, lowerLead > 0)
    }

    /// `upper` が `lower` に、先後を入れ替えて `openings` 通り × 2 局戦う。
    static func run(upperLevel: Int, lowerLevel: Int, openings: Int, maxPlies: Int,
                    concurrency: Int = 4) async -> Tally {
        var tally = Tally()
        let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(i + 1), $0) } }
        var next = 0
        await withTaskGroup(of: (Outcome, Bool).self) { group in
            func add() {
                guard next < jobs.count else { return }
                let (seed, upperIsBlack) = jobs[next]
                next += 1
                group.addTask {
                    let r = await play(
                        upper: { SimpleMinimaxEngine(level: upperLevel, seed: seed &* 100_000 &+ UInt64($0) &* 2 &+ 1) },
                        lower: { SimpleMinimaxEngine(level: lowerLevel, seed: seed &* 100_000 &+ UInt64($0) &* 2 &+ 2) },
                        upperIsBlack: upperIsBlack,
                                       opening: opening(seed: seed), maxPlies: maxPlies)
                    return (r.0, r.lowerAhead)
                }
            }
            for _ in 0..<concurrency { add() }
            for await (outcome, lowerAhead) in group {
                switch outcome {
                case .upperWon: tally.upperWins += 1
                case .lowerWon: tally.lowerWins += 1
                case .draw:
                    tally.draws += 1
                    if lowerAhead { tally.drawsLowerAhead += 1 }
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
