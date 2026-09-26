import Testing
import Foundation
import CoreEngine
@testable import GameChess

/// 手の選び方（見逃し）と読む局面数の上限（#1398）。数秒で終わるものだけを置く。
/// CPU 同士の対局・探索深さの計測は `CPUBenchTests`（`CPU_BENCH=1` のときだけ）。
@Suite("チェスの難易度: 手の選び方と局面数の上限（#1398）")
struct ChessMovePolicyTests {

    private static func mv(_ to: Int) -> ChessMove { ChessMove(from: 0, to: to) }

    /// 手 A（最善）・B（ポーン 1 枚損）・C（駒 1 枚損）・D（キングを取られる）。
    private var scored: [(move: ChessMove, score: Int)] {
        [(Self.mv(1), 0), (Self.mv(2), -100), (Self.mv(3), -300), (Self.mv(4), -100_000)]
    }

    private func picks(margin: Int, count: Int) -> [ChessMove] {
        var rng = SplitMix64(seed: 42)
        return (0..<count).compactMap { _ in
            SimpleChessEngine.pick(scored, best: 0, margin: margin, using: &rng)
        }
    }

    @Test("同等幅 0 なら常に最初の最善手")
    func zeroMarginPicksTheBest() {
        let moves = picks(margin: 0, count: 200)
        #expect(moves.count == 200 && moves.allSatisfy { $0 == Self.mv(1) })
    }

    @Test("幅の中からだけ乱択し、幅の外（キングを取られる手）は選ばない")
    func picksOnlyWithinTheMargin() {
        let moves = picks(margin: 350, count: 600)
        let allowed = [Self.mv(1), Self.mv(2), Self.mv(3)]
        #expect(moves.allSatisfy { allowed.contains($0) })
        #expect(allowed.allSatisfy { moves.contains($0) }, "幅の中の手が使われていない")
    }

    /// 指定局面で、見逃しを切った同じ段階の手と違う手を指す割合（＝見逃しの確率）を測る。
    /// 読みの深さは 4 までに絞る（デバッグビルドの CI 時間）。局面数の上限・定跡は使わない。
    private func slipRate(level: Int, fen: String, trials: Int) async -> Double {
        let shipped = SimpleChessEngine(level: level)
        func make(_ policy: ChessMovePolicy, _ seed: UInt64) -> SimpleChessEngine {
            SimpleChessEngine(
                depth: min(shipped.depth, 4), usePositional: shipped.usePositional,
                useQuiescence: shipped.useQuiescence, useBook: false, timeLimit: .infinity,
                policy: policy, seed: seed)
        }
        var slipped = 0
        for seed in 1...UInt64(trials) {
            let reference = await make(shipped.policy.withoutSlip, seed).bestMove(fen: fen)
            if await make(shipped.policy, seed).bestMove(fen: fen) != reference { slipped += 1 }
        }
        return Double(slipped) / Double(trials)
    }

    /// 白ルークが黒ナイト（320）を只で取れる局面。取らない手はどれも 320 損する。
    private static let freeKnight = "k7/8/8/4n3/8/8/8/K3R3 w - - 0 1"

    @Test("入門は只のナイトを約 3 割見逃し、むずかしいは見逃さない")
    func overlookRatesFollowTheStage() async {
        let novice = await slipRate(level: CPUStrength.novice.rawValue, fen: Self.freeKnight, trials: 300)
        #expect((0.2...0.45).contains(novice), "入門の見逃し率が想定（約 3 割）から外れている: \(novice)")
        let hard = await slipRate(level: CPUStrength.hard.rawValue, fen: Self.freeKnight, trials: 3)
        #expect(hard == 0, "むずかしいが見逃した: \(hard)")
    }

    /// 簡単・ふつうも見逃す（確率 0 や、深い探索の段階で見逃しの分岐が死んでいる変異を捕まえる）。
    /// 初期局面は候補の損得が小さく、見逃しの手番は幅の中の 20 手から乱択する（最善と同じ手を引く目もある）。
    @Test("簡単は約 8%、ふつうは約 10% 見逃す")
    func easyAndNormalOverlookSometimes() async {
        let easy = await slipRate(level: CPUStrength.easy.rawValue, fen: ChessPosition.startFEN, trials: 400)
        #expect((0.02...0.16).contains(easy), "簡単の見逃し率が想定（約 8%）から外れている: \(easy)")
        let normal = await slipRate(level: CPUStrength.normal.rawValue, fen: ChessPosition.startFEN, trials: 100)
        // 深さ 3 は 1 回ごとに時間がかかるので回数を絞り、幅を広げる（期待 10%・全く出ない確率は 0.003%）。
        #expect((0.01...0.30).contains(normal), "ふつうの見逃し率が想定（約 10%）から外れている: \(normal)")
    }

    @Test("見逃しを切った方針は同等幅だけが残る（読みを固定するテストの前提）")
    func withoutSlip() {
        #expect(SimpleChessEngine.novicePolicy.withoutSlip.slipProbability == 0)
        #expect(SimpleChessEngine.easyPolicy.withoutSlip.isExact)
        #expect(SimpleChessEngine.normalPolicy.withoutSlip.isExact)
        #expect(!SimpleChessEngine.novicePolicy.withoutSlip.isExact)
    }

    @Test("ふつうよりむずかしいのほうが多く読み、時間は安全用に長めに残してある")
    func nodeLimitsAreOrdered() {
        let normal = SimpleChessEngine(level: CPUStrength.normal.rawValue)
        let hard = SimpleChessEngine(level: CPUStrength.hard.rawValue)
        let easy = SimpleChessEngine(level: CPUStrength.easy.rawValue)
        #expect(normal.nodeLimit != nil && hard.nodeLimit != nil)
        #expect(normal.nodeLimit! < hard.nodeLimit!)
        #expect(normal.timeLimit >= 3 && hard.timeLimit >= 5, "時間の上限が主になって端末の速さで強さが変わる")
        #expect(easy.nodeLimit == nil && !easy.policy.isExact)
        #expect(hard.policy.isExact, "むずかしいは当面 100% 最善手（会長決裁 2026-09-25）")
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
}
