import Testing
import Foundation
import CoreEngine
@testable import GameShogi

/// 手の選び方（見逃し）と読む局面数の上限（#1397）。数秒で終わるものだけを置く。
/// CPU 同士の対局・探索深さの計測は `CPUBenchTests`（`CPU_BENCH=1` のときだけ）。
@Suite("将棋の難易度: 手の選び方と局面数の上限（#1397）")
struct ShogiMovePolicyTests {

    /// 手 A（最善）・B（歩 1 枚損）・C（駒 1 枚損）・D（玉を取られる）。
    private var scored: [(move: Move, score: Int)] {
        [(.drop(type: .pawn, to: 0), 0), (.drop(type: .pawn, to: 1), -100), (.drop(type: .pawn, to: 2), -400), (.drop(type: .pawn, to: 3), -100_000)]
    }

    private func picks(margin: Int, count: Int) -> [Move] {
        var rng = SplitMix64(seed: 42)
        return (0..<count).compactMap { _ in
            SimpleMinimaxEngine.pick(scored, best: 0, margin: margin, using: &rng)
        }
    }

    @Test("同等幅 0 なら常に最初の最善手")
    func zeroMarginPicksTheBest() {
        let moves = picks(margin: 0, count: 200)
        #expect(moves.count == 200 && moves.allSatisfy { $0 == .drop(type: .pawn, to: 0) })
    }

    @Test("幅の中からだけ乱択し、幅の外（玉を取られる手）は選ばない")
    func picksOnlyWithinTheMargin() {
        let moves = picks(margin: 400, count: 600)
        let allowed: [Move] = [.drop(type: .pawn, to: 0), .drop(type: .pawn, to: 1), .drop(type: .pawn, to: 2)]
        #expect(moves.allSatisfy { allowed.contains($0) })
        #expect(allowed.allSatisfy { moves.contains($0) }, "幅の中の手が使われていない")
    }

    /// 歩が只で取れる局面で、取らずに別の手を指す割合（＝見逃しの確率）を段階ごとに測る。
    /// 入門は歩 1 枚の損（=見逃し）を許す 35%、簡単・ふつうは 8%・10%
    /// （見逃しの手番は、別の手のうち損が幅に収まるものから選ぶ）。むずかしいは 0%。
    private func overlookRate(level: Int, trials: Int) async -> Double {
        let sfen = "4k4/9/9/4p4/4G4/9/9/9/4K4 b - 1"
        var overlooked = 0
        for seed in 1...UInt64(trials) {
            let e = ShogiSelfPlay.untimed(level: level, seed: seed, slips: true)
            if await e.bestMove(sfen: sfen) != "5e5d" { overlooked += 1 }
        }
        return Double(overlooked) / Double(trials)
    }

    @Test("入門は只の歩を約 3 割見逃し、むずかしいは見逃さない")
    func overlookRatesFollowTheStage() async {
        let novice = await overlookRate(level: CPUStrength.novice.rawValue, trials: 300)
        #expect((0.2...0.45).contains(novice), "入門の見逃し率が想定（約 32%）から外れている: \(novice)")
        let hard = await overlookRate(level: CPUStrength.hard.rawValue, trials: 5)
        #expect(hard == 0, "むずかしいが見逃した: \(hard)")
    }

    /// 簡単・ふつうも見逃す（確率 0 や、深い探索の段階で見逃しの分岐が死んでいる変異を捕まえる）。
    /// 別の手の候補は複数あり、見逃しの手番でも最善が選ばれる目もあるので、率は確率より少し下になる。
    @Test("簡単は只の歩を約 8%、ふつうは約 10% 見逃す")
    func easyAndNormalOverlookSometimes() async {
        let easy = await overlookRate(level: CPUStrength.easy.rawValue, trials: 400)
        #expect((0.03...0.15).contains(easy), "簡単の見逃し率が想定（約 7%）から外れている: \(easy)")
        let normal = await overlookRate(level: CPUStrength.normal.rawValue, trials: 100)
        // 深さ 4 は 1 回ごとに時間がかかるので回数を絞り、幅を広げる（期待 9%・全く出ない確率は 0.003%）。
        #expect((0.01...0.30).contains(normal), "ふつうの見逃し率が想定（約 9%）から外れている: \(normal)")
    }

    @Test("見逃しを切った方針は同等幅だけが残る（読みを固定するテストの前提）")
    func withoutSlip() {
        #expect(SimpleMinimaxEngine.novicePolicy.withoutSlip.slipProbability == 0)
        #expect(SimpleMinimaxEngine.easyPolicy.withoutSlip.isExact)
        #expect(SimpleMinimaxEngine.normalPolicy.withoutSlip.isExact)
        #expect(!SimpleMinimaxEngine.novicePolicy.withoutSlip.isExact)
    }

    @Test("ふつうよりむずかしいのほうが多く読み、時間は安全用に長めに残してある")
    func nodeLimitsAreOrdered() {
        let normal = SimpleMinimaxEngine(level: CPUStrength.normal.rawValue)
        let hard = SimpleMinimaxEngine(level: CPUStrength.hard.rawValue)
        let easy = SimpleMinimaxEngine(level: CPUStrength.easy.rawValue)
        #expect(normal.nodeLimit != nil && hard.nodeLimit != nil)
        #expect(normal.nodeLimit! < hard.nodeLimit!)
        #expect(normal.timeLimit >= 3 && hard.timeLimit >= 5, "時間の上限が主になって端末の速さで強さが変わる")
        #expect(easy.nodeLimit == nil && !easy.policy.isExact)
        #expect(hard.policy.isExact, "むずかしいは当面 100% 最善手（会長決裁 2026-09-25）")
    }

    @Test("局面数の上限に達したら読みを打ち切り、途中の深さは採用せず合法手を返す")
    func nodeLimitStopsTheSearch() {
        let engine = SimpleMinimaxEngine(depth: 5, usePositional: true, useQuiescence: true,
                                         useBook: false, timeLimit: .infinity, nodeLimit: 3_000)
        let r = engine.analyze(sfen: Position.startSFEN)
        #expect(r != nil)
        #expect((r?.depth ?? 99) < 5, "上限があるのに深さ 5 まで読み切った")
        // 打ち切り後に上限を大きく超えて読み続けない（1 手ぶんの余りは許す）。
        #expect((r?.nodes ?? .max) < 3_000 + 2_000, "上限を超えて読み続けている（\(r?.nodes ?? 0)）")
        let move = r?.usi.flatMap(Move.fromUSI)
        #expect(move != nil && Position.start().legalMoves().contains(move!))
    }

    /// `bestMove` が上限を探索へ渡していること。上限が渡らないと深さ 7 の全読みになり、
    /// デバッグビルドでは何分もかかる（時間の上限は無限にしてあるので、止めるのは局面数だけ）。
    @Test("bestMove も局面数の上限で止まる")
    func bestMoveHonorsTheNodeLimit() async {
        let engine = SimpleMinimaxEngine(depth: 7, usePositional: true, useQuiescence: true,
                                         useBook: false, timeLimit: .infinity, nodeLimit: 300)
        let start = Date()
        let usi = await engine.bestMove(sfen: Position.startSFEN)
        #expect(Date().timeIntervalSince(start) < 20, "局面数の上限が bestMove の探索に渡っていない")
        #expect(usi.flatMap(Move.fromUSI) != nil)
    }

    @Test("上限が極端に小さくても合法手を返す")
    func tinyNodeLimitStillReturnsALegalMove() {
        let engine = SimpleMinimaxEngine(depth: 4, usePositional: true, useQuiescence: true,
                                         useBook: false, timeLimit: .infinity, nodeLimit: 1)
        let r = engine.analyze(sfen: Position.startSFEN)
        let move = r?.usi.flatMap(Move.fromUSI)
        #expect(r?.depth == 0)
        #expect(move != nil && Position.start().legalMoves().contains(move!))
    }
}
