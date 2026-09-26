import Foundation
import CoreEngine
import Testing
@testable import GameGomoku

private func makeBoard(black: [(Int, Int)] = [], white: [(Int, Int)] = []) -> GomokuBoard {
    var board = GomokuBoard()
    for (row, col) in black { board[row, col] = .black }
    for (row, col) in white { board[row, col] = .white }
    return board
}

// MARK: - 手の選び方（#1399）

@Suite("五目並べ CPU の手の選び方")
struct GomokuMovePolicyTests {

    private let scores: [(move: Int, score: Int)] = [(10, 900), (11, 800), (12, 500), (13, -60_000)]

    @Test func exactPolicyPicksTheBestMove() {
        var rng = MMIXRandom(seed: 1)
        for _ in 0..<50 { #expect(GomokuMovePolicy.exact.choose(scores, using: &rng) == 10) }
    }

    /// 見逃し（slip）は最善から `slipMargin` 以内の手だけを選ぶ。損の幅を超える手は出ない。
    @Test func slipStaysWithinTheMargin() {
        let policy = GomokuMovePolicy(slipProbability: 1, slipMargin: 150, tieMargin: 0)
        var rng = MMIXRandom(seed: 2)
        let picked = Set((0..<200).compactMap { _ in policy.choose(scores, using: &rng) })
        #expect(picked == [10, 11], "最善(900)と 150 以内(800)だけ。500 以下は選ばれない: \(picked)")
    }

    /// 見逃しの確率どおりに最善手以外が混ざる（0% なら混ざらない・100% なら常に混ぜる幅）。
    @Test func slipProbabilityControlsHowOftenTheBestIsSkipped() {
        let sometimes = GomokuMovePolicy(slipProbability: 0.25, slipMargin: 150, tieMargin: 0)
        var rng = MMIXRandom(seed: 3)
        let skipped = (0..<2000).filter { _ in sometimes.choose(scores, using: &rng) != 10 }.count
        // 25% の手番で見逃し、その半分（2 手から乱択）が最善以外 → 約 12.5%。
        #expect((150...350).contains(skipped), "最善以外が \(skipped)/2000")
        var rng2 = MMIXRandom(seed: 3)
        let never = GomokuMovePolicy(slipProbability: 0, slipMargin: 150, tieMargin: 0)
        #expect((0..<500).allSatisfy { _ in never.choose(scores, using: &rng2) == 10 })
    }

    /// 相手に五を作らせる手（-50,000 以下）は、他に手があれば損の幅がどれだけ広くても選ばない。
    @Test func neverPicksAMoveThatLosesOutright() {
        let policy = GomokuMovePolicy(slipProbability: 1, slipMargin: 1_000_000, tieMargin: 0)
        var rng = MMIXRandom(seed: 4)
        #expect((0..<300).allSatisfy { _ in policy.choose(scores, using: &rng) != 13 })
        // 最善がそれしか無い（全部負け）なら、負けの中から選ぶ。
        let doomed: [(move: Int, score: Int)] = [(1, -70_000), (2, -80_000)]
        #expect(policy.choose(doomed, using: &rng) != nil)
    }

    @Test func emptyScoresGiveNoMove() {
        var rng = MMIXRandom(seed: 5)
        #expect(GomokuMovePolicy.exact.choose([], using: &rng) == nil)
    }
}

// MARK: - 段階の設定（#1399）

@Suite("五目並べ CPU の探索の上限")
struct GomokuSearchBudgetTests {

    /// 段階の強さは読む局面数で決まり、時計に左右されない（端末が遅くても同じ深さになる）。
    /// 時計を止めた探索と実時間の探索が、同じ手・同じ局面数・同じ深さになること。
    @Test func nodeLimitMakesTheSearchIndependentOfTheClock() {
        let board = makeBoard(black: [(7, 7), (7, 8), (9, 9), (6, 9)], white: [(7, 9), (8, 8), (6, 6)])
        let frozen = Date()
        let a = SimpleGomokuEngine(level: CPUStrength.normal.rawValue, seed: 1, now: { frozen })
            .analyze(board: board, stone: .white)
        let b = SimpleGomokuEngine(level: CPUStrength.normal.rawValue, seed: 1).analyze(board: board, stone: .white)
        #expect(a.nodes == b.nodes && a.depth == b.depth)
        #expect(a.move?.0 == b.move?.0 && a.move?.1 == b.move?.1)
        #expect(a.nodes <= SimpleGomokuEngine.normalNodeLimit + 1, "局面数の上限を超えて読んでいる: \(a.nodes)")
    }

    /// 局面数の上限が小さいほど浅くしか読めない（上限が読みの深さを決めている）。
    @Test func aSmallerNodeLimitReadsLessDeep() {
        let board = makeBoard(black: [(7, 7), (7, 8), (9, 9), (6, 9)], white: [(7, 9), (8, 8), (6, 6)])
        let small = SimpleGomokuEngine(level: CPUStrength.normal.rawValue, seed: 1, maxDepth: 6, nodeLimit: .some(300))
            .analyze(board: board, stone: .white)
        let large = SimpleGomokuEngine(level: CPUStrength.normal.rawValue, seed: 1, maxDepth: 6, nodeLimit: .some(60_000))
            .analyze(board: board, stone: .white)
        #expect(small.depth < large.depth, "\(small.depth) / \(large.depth)")
    }
}

// MARK: - 戦術（#1399）

@Suite("五目並べ ふつうの戦術")
struct GomokuNormalTacticsTests {

    /// 連番の種をそのまま渡すと MMIX の初手が似通うので、散らばった種にする。
    private func moves(_ board: GomokuBoard, stone: GomokuStone, level: Int, seeds: Int = 30) async -> Set<[Int]> {
        var out = Set<[Int]>()
        for i in 0..<seeds {
            if let m = await SimpleGomokuEngine(level: level, seed: UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15).bestMove(board: board, stone: stone) {
                out.insert([m.row, m.col])
            }
        }
        return out
    }

    /// 相手の開三（両端が空いた 3 連）は、次で活四にされる前に止める。深さ 3 の探索だけでは届かない。
    @Test func normalBlocksAnOpenThree() async {
        let board = makeBoard(black: [(7, 6), (7, 7), (7, 8)], white: [(3, 3), (11, 11)])
        let picked = await moves(board, stone: .white, level: CPUStrength.normal.rawValue)
        #expect(picked.isSubset(of: [[7, 5], [7, 9]]), "開三を止めていない: \(picked)")
    }

    /// 三三になる点を先に潰す（相手が置くと開三が 2 本できる点）。
    @Test func normalStopsAThreeThreeFork() async {
        let board = makeBoard(black: [(7, 8), (7, 9), (8, 10), (9, 10)], white: [(3, 3), (11, 11)])
        let picked = await moves(board, stone: .white, level: CPUStrength.normal.rawValue)
        #expect(picked == [[7, 10]], "三三の点を取っていない: \(picked)")
    }

    /// 四三（四を作りながら開三も作る手）は、相手に止める手が無いので必ず打つ。
    @Test func normalPlaysAFourThree() async {
        let board = makeBoard(black: [(7, 5), (7, 6), (7, 7), (8, 8), (9, 8)], white: [(7, 4), (3, 12), (12, 3)])
        let picked = await moves(board, stone: .black, level: CPUStrength.normal.rawValue)
        #expect(picked == [[7, 8]], "四三を打っていない: \(picked)")
    }

    /// 弱い 2 段（入門・簡単）はこの補いを持たない（開三を放置する回がある）。
    @Test func weakLevelsSometimesIgnoreAnOpenThree() async {
        let board = makeBoard(black: [(7, 6), (7, 7), (7, 8)], white: [(3, 3), (11, 11)])
        for level in [CPUStrength.easy.rawValue, CPUStrength.novice.rawValue] {
            let picked = await moves(board, stone: .white, level: level)
            #expect(!picked.isSubset(of: [[7, 5], [7, 9]]), "level \(level) が毎回開三を止めている: \(picked)")
        }
    }

    /// むずかしいは即勝ちも即防ぎも、開三への対処も外さない（深く読ませても足元が崩れていない）。
    @Test func hardDoesNotLoseToAnOpenThree() async {
        let board = makeBoard(black: [(7, 6), (7, 7), (7, 8)], white: [(3, 3), (11, 11)])
        let move = await SimpleGomokuEngine(level: CPUStrength.hard.rawValue, seed: 1).bestMove(board: board, stone: .white)
        // 活四を作らせない手（両端か、片側を先に塞ぐ手）であること。
        var after = board
        after[move!.row, move!.col] = .white
        let openFourRemains = [(7, 5), (7, 9)].contains { p in
            after[p.0, p.1] == nil && {
                var b = after; b[p.0, p.1] = .black
                let left = b[7, 4] == nil, right = b[7, 10] == nil
                return p.1 == 5 ? (left && b[7, 9] == nil) : (right && b[7, 5] == nil)
            }()
        }
        #expect(!openFourRemains, "活四を作られる: \(String(describing: move))")
    }
}

// MARK: - 段階の序列（#1399）

@Suite("五目並べ 段階の序列")
struct GomokuLadderQuickTests {

    /// 簡単は入門に負けない（先後を入れ替えて 20 局。会長決裁 2026-09-25。基準は 2026-09-26 に「負け 3% 以下」へ緩和済みだが、固定 seed の 20 局は負け 0 で通っている）。
    /// 重い組（ふつう対簡単・むずかしい対ふつう）は `CPUBenchTests`（`CPU_BENCH=1`）で計測する。
    @Test func easyNeverLosesToNovice() async {
        let t = await CPUBenchLadder.run(upperLevel: CPUStrength.easy.rawValue,
                                         lowerLevel: CPUStrength.novice.rawValue, openings: 10)
        #expect(t.games == 20)
        #expect(t.lowerWins == 0, "簡単が入門に \(t.lowerWins) 局負けた（勝ち \(t.upperWins)・引き分け \(t.draws)）")
    }
}
