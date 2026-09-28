import Testing
import Foundation
import CoreEngine
@testable import GameChess

/// 最善手を外すときの手の選び方と局面数の上限（#1462）。数秒で終わるものだけを置く。
/// CPU 同士の対局・所要時間の計測は `Scripts/chess-cpu-bench`（`CPUBenchTests` は `CPU_BENCH=1` のときだけ）。
@Suite("チェスの難易度: 最善手の確率と外したときの手（#1462）")
struct ChessMovePolicyTests {

    /// 白ルークが黒ポーンを只で取れる局面。1 手先の読みでは取る手（e1e5）が最善（2 手先以上は、逃げられない
    /// ポーンを後回しにしてキングを寄せる手を選ぶので、読みは 1 手先に固定する）。
    private static let freePawn = "k7/8/8/4p3/8/8/8/K3R3 w - - 0 1"

    /// 只のポーンを取らずに別の手を指す割合。外したときは最善（取る手）を除いて選ぶので、
    /// 割合は 1 − 確率にそのまま近づく。
    private func missRate(probability: Double, trials: Int) async -> Double {
        let policy = SimpleChessEngine.policy(probability)
        var missed = 0
        for seed in 1...UInt64(trials) {
            let e = SimpleChessEngine(depth: 1, usePositional: true, useQuiescence: true, useBook: false,
                                      timeLimit: .infinity, policy: policy, seed: seed)
            if await e.bestMove(fen: Self.freePawn) != "e1e5" { missed += 1 }
        }
        return Double(missed) / Double(trials)
    }

    @Test("最善手を外す割合が設定した確率どおりになる（0% と 100% の両端を含む）")
    func missRateFollowsTheProbability() async {
        #expect(await missRate(probability: 1, trials: 20) == 0)
        #expect(await missRate(probability: 0, trials: 20) == 1, "確率 0% は最善手を一度も指さない")
        for p in [0.1, 0.6, 0.9] {
            let rate = await missRate(probability: p, trials: 400)
            #expect(abs(rate - (1 - p)) < 0.09, "確率 \(p) の外し率が \(rate)（期待 \(1 - p)）")
        }
    }

    /// 白の 1 段目が空いていて、黒の Re1 でバックランクメイトになる局面。脅威を放っておく手（ビショップの
    /// 多くの手など）は次の一手で詰まされ、ポーンで逃げ道を空ける手・Bf1/Be2 などは詰まされない。
    private static let backRankThreat = "4r1k1/5ppp/8/8/2B5/8/5PPP/6K1 w - - 0 1"

    private func slippingEngine(seed: UInt64, margin: Int = SimpleChessEngine.slipMargin) -> SimpleChessEngine {
        SimpleChessEngine(depth: 2, usePositional: true, useQuiescence: true, useBook: false, timeLimit: .infinity,
                          policy: ChessMovePolicy(bestMoveProbability: 0, slipMargin: margin), seed: seed)
    }

    @Test("外したときの手に、次の一手でチェックメイトされる手は入らない")
    func slipNeverWalksIntoMate() {
        let pos = ChessPosition.fromFEN(Self.backRankThreat)!
        let moves = pos.legalMoves()
        var probe = pos
        let mating = Set(moves.filter { SimpleChessEngine.allowsMateInOne(&probe, after: $0) }.map(\.uci))
        #expect(!mating.isEmpty && mating.count < moves.count, "前提: 詰まされる手とそうでない手の両方がある")

        // 対照: 損の幅を実質無制限にすると、候補（詰みの確認前）に詰まされる手が入る。
        // 確認が効いていなければ、下のループで選ばれる。
        var pooled = pos
        let pool = slippingEngine(seed: 1, margin: 1_000_000).slipPool(&pooled, moves: moves).map(\.uci)
        #expect(pool.contains { mating.contains($0) }, "対照: 候補に詰まされる手が入っていない（前提が崩れている）")

        for seed in 1...60 {
            var p = pos
            var rng = SplitMix64(seed: UInt64(seed))
            let e = slippingEngine(seed: UInt64(seed), margin: 1_000_000)
            if let m = e.slipMove(&p, moves: moves, using: &rng) {
                #expect(!mating.contains(m.uci), "詰まされる手を選んだ: \(m.uci)")
            }
        }
    }

    @Test("外しの手は、最善と損の幅の外の手（クイーンを只で取られる手）を選ばない")
    func slipStaysWithinTheMargin() {
        // e1 の白クイーンは e5 の黒ポーンを只で取れる（最善）。d4・f4 はそのポーンに、a7・b7・b8 は黒キングに
        // クイーンを取られる。幅（350 = ナイト・ビショップ 1 枚ぶん）の外。
        let fen = "k7/8/8/4p3/8/8/8/K3Q3 w - - 0 1"
        let pos = ChessPosition.fromFEN(fen)!
        var p = pos
        let pool = slippingEngine(seed: 1).slipPool(&p, moves: pos.legalMoves())
        #expect(!pool.isEmpty)
        #expect(!pool.contains { $0.uci == "e1e5" }, "最善（ポーンを取る手）は外しの候補に入らない")
        for move in pool {
            var q = pos
            q.make(move)
            let lostQueen = q.legalMoves().contains { q.squares[$0.to]?.type == .queen }
            #expect(!lostQueen, "クイーンを只で取られる手が候補に入っている: \(move.uci)")
        }
    }

    /// 外しの候補が無い（合法手が 1 手だけ）ときは、外せないので探索して最善手を指す。
    /// 何も返さない・非合法手を返すと、CPU が止まる。
    @Test("外しの候補が無ければ探索に回り、唯一の合法手を返す")
    func slipWithNoCandidatesFallsBackToSearch() async {
        // h1 の白キングは g1・h2 を g2 の黒ルークに押さえられ、そのルークを取る手しかない。
        let pos = ChessPosition.fromFEN("k7/8/8/8/8/8/6r1/7K w - - 0 1")!
        let moves = pos.legalMoves()
        #expect(moves.count == 1, "前提: 合法手が 1 手だけ（\(moves.map(\.uci))）")
        let e = SimpleChessEngine(depth: 2, usePositional: true, useQuiescence: true, useBook: false,
                                  timeLimit: .infinity, policy: SimpleChessEngine.policy(0), seed: 1)
        #expect(await e.bestMove(fen: pos.toFEN()) == moves[0].uci)
    }

    @Test("探索に残す時間は、使った時間と後始末ぶんを引く（上限を超えない・0 にならない）")
    func searchTimeSubtractsWhatWasUsed() {
        let over = SimpleChessEngine.searchOverhead
        #expect(abs(SimpleChessEngine.searchTime(limit: 1, elapsed: 0.4) - (0.6 - over)) < 1e-9)
        #expect(SimpleChessEngine.searchTime(limit: 1, elapsed: 5) == SimpleChessEngine.minSearchTime)
        #expect(SimpleChessEngine.searchTime(limit: .infinity, elapsed: 5) == .infinity)
    }

    @Test("局面数の上限に達したら読みを打ち切り、途中の深さは採用せず合法手を返す")
    func nodeLimitStopsTheSearch() {
        let engine = SimpleChessEngine(depth: 5, usePositional: true, useQuiescence: true,
                                       useBook: false, timeLimit: .infinity, nodeLimit: 3_000)
        let r = engine.analyze(fen: ChessPosition.startFEN)
        #expect(r != nil)
        #expect((r?.depth ?? 99) < 5, "上限があるのに深さ 5 まで読み切った")
        // 打ち切り後に上限を大きく超えて読み続けない（1 手ぶんの余りは許す）。
        #expect((r?.nodes ?? .max) < 3_000 + 2_000, "上限を超えて読み続けている（\(r?.nodes ?? 0)）")
        let move = r?.uci.flatMap(ChessMove.fromUCI)
        #expect(move != nil && ChessPosition.start().legalMoves().contains(move!))
    }

    /// `bestMove` が上限を探索へ渡していること。渡らないと深い全読みになり、
    /// デバッグビルドでは何分もかかる（時間の上限は無限にしてあるので、止めるのは局面数だけ）。
    @Test("bestMove も局面数の上限で止まる")
    func bestMoveHonorsTheNodeLimit() async {
        let engine = SimpleChessEngine(depth: 7, usePositional: true, useQuiescence: true,
                                       useBook: false, timeLimit: .infinity, nodeLimit: 300)
        let start = Date()
        let uci = await engine.bestMove(fen: ChessPosition.startFEN)
        #expect(Date().timeIntervalSince(start) < 20, "局面数の上限が bestMove の探索に渡っていない")
        #expect(uci.flatMap(ChessMove.fromUCI) != nil)
    }

    @Test("上限が極端に小さくても合法手を返す")
    func tinyNodeLimitStillReturnsALegalMove() {
        let engine = SimpleChessEngine(depth: 4, usePositional: true, useQuiescence: true,
                                       useBook: false, timeLimit: .infinity, nodeLimit: 1)
        let r = engine.analyze(fen: ChessPosition.startFEN)
        let move = r?.uci.flatMap(ChessMove.fromUCI)
        #expect(r?.depth == 0)
        #expect(move != nil && ChessPosition.start().legalMoves().contains(move!))
    }

    /// 確率は `docs/analytics/chess-1462-ladder.md` の段階表（すぐ上の段の得点率 90% 以上で最も高い値）で決めた値。
    /// 変えるときは同じ計測（`Scripts/chess-cpu-bench`）をやり直して表を更新する。
    @Test("最善手の確率は 入門 60% / かんたん 80% / ふつう 90% / むずかしい 100%、損の幅はナイト・ビショップ 1 枚ぶん")
    func probabilitiesArePinnedToTheMeasurement() {
        let p = CPUStrength.allCases.map { SimpleChessEngine(level: $0.rawValue).policy }
        #expect(p.map(\.bestMoveProbability) == [0.6, 0.8, 0.9, 1])
        #expect(p[3].isExact)
        #expect(p[0..<3].allSatisfy { $0.slipMargin == SimpleChessEngine.slipMargin })
        #expect(SimpleChessEngine.slipMargin > ChessPieceValue.base(.bishop))
        #expect(SimpleChessEngine.slipMargin < ChessPieceValue.base(.rook), "外しでもルーク・クイーンは只で損しない")
    }
}
