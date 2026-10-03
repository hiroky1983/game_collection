import Foundation
#if !CHESS_BENCH_STANDALONE
import CoreEngine
@testable import GameChess
#endif

/// 段階どうしの総当たり計測（#1398・#1462）。`CPUBenchTests` と `Scripts/chess-cpu-bench` が呼ぶ。
/// Testing に依存しないので、`swiftc -O -D CHESS_BENCH_STANDALONE` で単体バイナリにして最適化ビルドで回せる
/// （`swift test -c release` は通らない・デバッグビルドでは 1 手 2 秒の探索が現実の速さで測れない）。
enum CPUBenchLadder {
    enum Outcome { case upperWon, lowerWon, draw }

    struct Tally {
        var upperWins = 0, lowerWins = 0, draws = 0
        /// 引き分け（手数上限・ステイルメイト・50 手）のうち、下の段階が駒得で上回っていた局（参考値）。
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

    /// 手ごとに、種の違うエンジンを作る（実機は種なしで毎回違う乱数）。`nil` を渡した側は合法手から一様乱択する。
    typealias EngineFactory = @Sendable (_ seed: UInt64) -> SimpleChessEngine

    /// 1 局。返り値の Bool は「引き分けで終わり、下の段階が駒得で上回っていた」。
    /// 種を渡した同じエンジンは同じ手番なら同じ外しの目を引くので、エンジンは手ごとに作り直す。
    static func play(upper: @escaping EngineFactory, lower: EngineFactory?, seed: UInt64,
                     upperIsWhite: Bool, opening: ChessPosition, maxPlies: Int) async -> (Outcome, lowerAhead: Bool) {
        var pos = opening
        var rng = MMIXRandom(seed: seed &* 7 &+ 3)
        func draw() -> (Outcome, lowerAhead: Bool) {
            let whiteLead = material(pos)
            return (.draw, (upperIsWhite ? -whiteLead : whiteLead) > 0)
        }
        for ply in 0..<maxPlies {
            let moves = pos.legalMoves()
            if moves.isEmpty {
                // ステイルメイトは引き分け。チェックメイトは手番側の負け。
                guard pos.isKingInCheck(pos.sideToMove) else { return draw() }
                let upperLost = (pos.sideToMove == .white) == upperIsWhite
                return (upperLost ? .lowerWon : .upperWon, false)
            }
            // 50 手ルール（探索も 100 半手で引き分けと読む）。
            if pos.halfmoveClock >= 100 { return draw() }
            let upperToMove = (pos.sideToMove == .white) == upperIsWhite
            let move: ChessMove
            if let factory = upperToMove ? upper : lower {
                let engineSeed = seed &* 100_000 &+ UInt64(ply) &* 2 &+ (upperToMove ? 1 : 2)
                guard let uci = await factory(engineSeed).bestMove(fen: pos.toFEN()),
                      let m = ChessMove.fromUCI(uci), moves.contains(m) else {
                    return (upperToMove ? .lowerWon : .upperWon, false)  // 手を返せない・非合法は反則負け
                }
                move = m
            } else {
                move = moves[Int(rng.next() % UInt64(moves.count))]
            }
            _ = pos.make(move)
        }
        return draw()
    }

    /// `upper` が `lower` に、先後を入れ替えて `openings` 通り × 2 局戦う。
    /// `firstOpening` は最初の開始局面の番号（計測を小分けにして続きから回すため）。
    static func run(upper: @escaping EngineFactory, lower: EngineFactory?, openings: Int, maxPlies: Int,
                    concurrency: Int = 4, firstOpening: Int = 1) async -> Tally {
        var tally = Tally()
        let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(firstOpening + i), $0) } }
        var next = 0
        await withTaskGroup(of: (Outcome, Bool).self) { group in
            func add() {
                guard next < jobs.count else { return }
                let (seed, upperIsWhite) = jobs[next]
                next += 1
                group.addTask {
                    let r = await play(upper: upper, lower: lower, seed: seed, upperIsWhite: upperIsWhite,
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

    /// 出荷している段階の設定で、考える時間を「読む局面数」に置き換えたエンジン。
    /// `nodesPerSecond` は最適化ビルドで測った 1 秒あたりの局面数。時間で打ち切ると同時に走る対局の
    /// 負荷で強さが揺れるので、計測の対局は局面数で打ち切る（実機の時間で読める量と等しい）。
    /// `bestMoveProbability` を渡すと、その段階の確率だけを差し替える（確率の候補を試すため）。
    /// `slipMargin` は外したときに許す損の幅の差し替え。`depth` は読む深さの上限の差し替え（#1566）。
    static func engine(_ strength: CPUStrength, nodesPerSecond: Double, bestMoveProbability: Double? = nil,
                       slipMargin: Int? = nil, depth: Int? = nil, seed: UInt64) -> SimpleChessEngine {
        let shipped = SimpleChessEngine(level: strength.rawValue)
        var policy = shipped.policy
        if let p = bestMoveProbability {
            policy.bestMoveProbability = p
            if policy.slipMargin == 0 { policy.slipMargin = SimpleChessEngine.slipMargin }  // 「むずかしい」の確率を下げて試すとき
        }
        if let m = slipMargin, !policy.isExact { policy.slipMargin = m }
        return SimpleChessEngine(
            depth: depth ?? shipped.depth, usePositional: shipped.usePositional, useQuiescence: shipped.useQuiescence,
            useBook: shipped.useBook, timeLimit: .infinity,
            nodeLimit: max(1, Int(shipped.timeLimit * nodesPerSecond)), policy: policy, seed: seed)
    }
}
