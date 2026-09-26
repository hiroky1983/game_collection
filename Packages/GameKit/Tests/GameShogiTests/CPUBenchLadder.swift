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

    /// 手ごとに、種の違うエンジンを作る（実機は種なしで毎回違う乱数）。`nil` を渡した側は合法手から一様乱択する。
    typealias EngineFactory = @Sendable (_ seed: UInt64) -> SimpleMinimaxEngine

    /// 1 局。返り値の Bool は「手数上限で終わり、下の段階が駒得で上回っていた」。
    /// 種を渡した同じエンジンは同じ手番なら同じ外しの目を引くので、エンジンは手ごとに作り直す。
    static func play(upper: @escaping EngineFactory, lower: EngineFactory?, seed: UInt64,
                     upperIsBlack: Bool, opening: Position, maxPlies: Int) async -> (Outcome, lowerAhead: Bool) {
        var pos = opening
        var rng = MMIXRandom(seed: seed &* 7 &+ 3)
        for ply in 0..<maxPlies {
            let moves = pos.legalMoves()
            if moves.isEmpty {
                let upperLost = (pos.sideToMove == .black) == upperIsBlack
                return (upperLost ? .lowerWon : .upperWon, false)
            }
            let upperToMove = (pos.sideToMove == .black) == upperIsBlack
            let move: Move
            if let factory = upperToMove ? upper : lower {
                let engineSeed = seed &* 100_000 &+ UInt64(ply) &* 2 &+ (upperToMove ? 1 : 2)
                guard let usi = await factory(engineSeed).bestMove(sfen: pos.toSFEN()),
                      let m = Move.fromUSI(usi), moves.contains(m) else {
                    return (upperToMove ? .lowerWon : .upperWon, false)  // 手を返せない・非合法は反則負け
                }
                move = m
            } else {
                move = moves[Int(rng.next() % UInt64(moves.count))]
            }
            pos.make(move)
        }
        let blackLead = material(pos)
        let lowerLead = upperIsBlack ? -blackLead : blackLead
        return (.draw, lowerLead > 0)
    }

    /// `upper` が `lower` に、先後を入れ替えて `openings` 通り × 2 局戦う。
    static func run(upper: @escaping EngineFactory, lower: EngineFactory?, openings: Int, maxPlies: Int,
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
                    let r = await play(upper: upper, lower: lower, seed: seed, upperIsBlack: upperIsBlack,
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
    /// `slipMargin` は外したときに許す損の幅の差し替え。
    static func engine(_ strength: CPUStrength, nodesPerSecond: Double, bestMoveProbability: Double? = nil,
                       slipMargin: Int? = nil, seed: UInt64) -> SimpleMinimaxEngine {
        let shipped = SimpleMinimaxEngine(level: strength.rawValue)
        var policy = shipped.policy
        if let p = bestMoveProbability { policy.bestMoveProbability = p }
        if let m = slipMargin, !policy.isExact { policy.slipMargin = m }
        return SimpleMinimaxEngine(
            depth: shipped.depth, usePositional: shipped.usePositional, useQuiescence: shipped.useQuiescence,
            useBook: shipped.useBook, timeLimit: .infinity,
            nodeLimit: Int(shipped.timeLimit * nodesPerSecond), policy: policy, seed: seed)
    }
}
