import Foundation
#if !CHESS_BENCH_STANDALONE
import CoreEngine
@testable import GameChess
#endif

/// 段階どうしの総当たり計測（#1398）。`CPUBenchTests` が呼ぶ。Testing に依存しないので、
/// `swiftc -O -D CHESS_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない・デバッグビルドでは深さ 6 の対局が現実的な時間に収まらない）。
enum CPUBenchLadder {
    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        /// 引き分け（手数上限・ステイルメイト）のうち、下の段階が駒得で上回っていた局（参考値）。
        var drawsLowerAhead = 0
        var games: Int { upperWins + lowerWins + draws }
    }

    /// 開始局面から `plies` 手を乱数で進めた局面（対局の多様性を作る）。駒得が偏った局面
    /// （乱数の手で駒を取られた・詰んだ）は、先後を入れ替えても片方の段階に不利な出発になるので
    /// 引き直す（駒の価値の差がポーン 1 枚以内になるまで）。
    static func opening(seed: UInt64, plies: Int = 6) -> ChessPosition {
        var rng = MMIXRandom(seed: seed)
        for _ in 0..<200 {
            var pos = ChessPosition.start()
            var finished = false
            for _ in 0..<plies {
                let moves = pos.legalMoves()
                guard !moves.isEmpty else { finished = true; break }
                _ = pos.make(moves[Int(rng.next() % UInt64(moves.count))])
            }
            if !finished && !pos.legalMoves().isEmpty && abs(material(pos)) <= ChessPieceValue.base(.pawn) { return pos }
        }
        return ChessPosition.start()
    }

    /// キングを除いた駒の価値の差（白視点）。
    static func material(_ pos: ChessPosition) -> Int {
        var s = 0
        for sq in 0..<ChessSquare.count {
            guard let p = pos.squares[sq], p.type != .king else { continue }
            s += (p.color == .white ? 1 : -1) * ChessPieceValue.base(p.type)
        }
        return s
    }

    /// 1 局。返り値の Bool は「手数上限で終わり、下の段階が駒得で上回っていた」。
    /// 種を渡した同じエンジンは同じ手番なら同じ見逃しの目を引くので、エンジンは手ごとに作り直す
    /// （`upper` / `lower` は手数を受け取って種の違うエンジンを返す。実機は種なしで毎回違う乱数）。
    static func play(upper: (Int) -> SimpleChessEngine, lower: (Int) -> SimpleChessEngine,
                     upperIsWhite: Bool, opening: ChessPosition, maxPlies: Int) async -> (Outcome, lowerAhead: Bool) {
        var pos = opening
        for ply in 0..<maxPlies {
            let moves = pos.legalMoves()
            if moves.isEmpty {
                // ステイルメイトは引き分け。チェックメイトは手番側の負け。
                guard pos.isKingInCheck(pos.sideToMove) else {
                    let lead = material(pos)
                    return (.draw, (upperIsWhite ? -lead : lead) > 0)
                }
                let upperLost = (pos.sideToMove == .white) == upperIsWhite
                if upperLost { print("LOSS 詰まされた局面 \(pos.toFEN()) 駒得(白視点) \(material(pos)) 上は\(upperIsWhite ? "白" : "黒")") }
                return (upperLost ? .lowerWon : .upperWon, false)
            }
            let upperToMove = (pos.sideToMove == .white) == upperIsWhite
            let engine = upperToMove ? upper(ply) : lower(ply)
            guard let uci = await engine.bestMove(fen: pos.toFEN()),
                  let move = ChessMove.fromUCI(uci), moves.contains(move) else {
                return (upperToMove ? .lowerWon : .upperWon, false)  // 手を返せない・非合法は反則負け
            }
            _ = pos.make(move)
        }
        let whiteLead = material(pos)
        let lowerLead = upperIsWhite ? -whiteLead : whiteLead
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
                let (seed, upperIsWhite) = jobs[next]
                next += 1
                group.addTask {
                    let r = await play(
                        upper: { SimpleChessEngine(level: upperLevel, seed: seed &* 100_000 &+ UInt64($0) &* 2 &+ 1) },
                        lower: { SimpleChessEngine(level: lowerLevel, seed: seed &* 100_000 &+ UInt64($0) &* 2 &+ 2) },
                        upperIsWhite: upperIsWhite, opening: opening(seed: seed), maxPlies: maxPlies)
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
