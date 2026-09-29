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

/// 連番の種をそのまま渡すと MMIX の出目が似通うので、散らばった種にする。
private func spread(_ i: Int) -> UInt64 { UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15 }

// MARK: - 段階の設定（#1463）

@Suite("五目並べ CPU の段階の設定（#1463）")
struct GomokuStrengthConfigTests {

    /// 会長決裁（2026-09-26）: 入門 0.3 秒 / かんたん 0.5 秒 / ふつう 1 秒 / むずかしい 2 秒。
    /// 局面数の上限は強さの主軸にしない（出荷値では使わない）。
    @Test("考える時間は 0.3 / 0.5 / 1 / 2 秒で、局面数の上限は無い")
    func timeLimitsFollowTheDecision() {
        let engines = CPUStrength.allCases.map { SimpleGomokuEngine(level: $0.rawValue) }
        #expect(engines.map(\.timeLimit) == [0.3, 0.5, 1, 2])
        #expect(engines.allSatisfy { $0.nodeLimit == nil })
    }

    /// 深さの上限は 入門 1 / かんたん 1 / ふつう 1 手先、むずかしいは上限なし（#1566 の段階表。会長決裁 2026-09-29 の合格範囲）。
    /// 探索の形（候補手の絞り方）は全段で同じ（`SimpleGomokuEngine.breadth`）なので、違いは深さ・時間・確率だけ。
    @Test("読む深さの上限は 1 / 1 / 1 手先・むずかしいは上限なし")
    func depthCapsFollowTheDecision() {
        let depths = CPUStrength.allCases.map { SimpleGomokuEngine(level: $0.rawValue).depth }
        #expect(depths == [1, 1, 1, SimpleGomokuEngine.maxDepth])
    }

    /// 会長決裁（2026-09-29・#1566）の制約: 深さ・確率とも 入門 ≤ かんたん ≤ ふつう ≤ むずかしい、
    /// 確率は 10% 刻み（入門 20% を除き 30% 以上）・隣との差 10〜40 ポイント、深さは隣との差 0〜1 手（むずかしいは上限なしで対象外）。
    @Test("段階の深さと確率は会長決裁の制約を満たす")
    func stagesSatisfyTheLadderConstraints() {
        let engines = CPUStrength.allCases.map { SimpleGomokuEngine(level: $0.rawValue) }
        let percents = engines.map { Int(($0.policy.bestMoveProbability * 100).rounded()) }
        #expect(percents == [20, 60, 90, 100])
        #expect(percents.dropFirst().allSatisfy { $0 >= 30 && $0 <= 100 && $0 % 10 == 0 })
        for (lower, upper) in zip(percents, percents.dropFirst()) {
            #expect((10...40).contains(upper - lower), "確率の差 \(lower)% → \(upper)%")
        }
        let depths = engines.map(\.depth)
        for (lower, upper) in zip(depths.dropLast(), depths.dropLast().dropFirst()) {
            #expect((0...1).contains(upper - lower), "深さの差 \(lower) → \(upper)")
        }
        #expect(depths == depths.sorted())
    }

    /// むずかしいは 100%。下の段の確率は段階表（入門 `docs/analytics/gomoku-1463-ladder.md`・かんたん / ふつう `gomoku-1566-ladder.md`）で決めた値。
    @Test("最善手を打つ確率は むずかしい 100%・下の段は段階表の値で、損の幅は全段共通")
    func probabilitiesFollowTheLadder() {
        let policies = CPUStrength.allCases.map { SimpleGomokuEngine(level: $0.rawValue).policy }
        #expect(policies.map(\.bestMoveProbability) == [
            SimpleGomokuEngine.noviceBestMoveProbability, SimpleGomokuEngine.easyBestMoveProbability,
            SimpleGomokuEngine.normalBestMoveProbability, 1,
        ])
        #expect(policies.last == .exact)
        #expect(policies.dropLast().allSatisfy { $0.slipMargin == SimpleGomokuEngine.slipMargin })
    }
}

// MARK: - 外したときの手（#1463）

@Suite("五目並べ CPU の最善手の確率と外したときの手（#1463）")
struct GomokuMovePolicyTests {

    private let scores: [(move: Int, score: Int)] = [(10, 900), (11, 800), (12, 500), (13, -60_000)]

    /// 外したときは最善を除き、最善から損の幅（`slipMargin`）以内の手だけを選ぶ。
    @Test func slipExcludesTheBestAndStaysWithinTheMargin() {
        let policy = GomokuMovePolicy(bestMoveProbability: 0, slipMargin: 150)
        var rng = MMIXRandom(seed: 2)
        let picked = Set((0..<200).compactMap { _ in policy.slip(scores, best: 10, using: &rng) })
        #expect(picked == [11], "最善(900)は除き、150 以内(800)だけ。500 以下は選ばれない: \(picked)")
    }

    /// 相手に五を作られる読み筋の手（`losingScore` 以下）は、損の幅がどれだけ広くても選ばない。
    @Test func slipNeverPicksALosingMove() {
        let policy = GomokuMovePolicy(bestMoveProbability: 0, slipMargin: 1_000_000)
        var rng = MMIXRandom(seed: 4)
        #expect((0..<300).allSatisfy { _ in policy.slip(scores, best: 10, using: &rng) != 13 })
        // 最善のほかに候補が無ければ外さない（呼び出し側が最善手を打つ）。
        #expect(policy.slip([(1, 100), (2, -70_000)], best: 1, using: &rng) == nil)
        #expect(policy.slip([], best: 1, using: &rng) == nil)
    }

    /// 中盤の局面で、探索の最善手を打たない割合。外した手番は最善を除いて選ぶので、割合は 1 − 確率に近づく。
    /// 時間ではなく深さ 2 で止めて、実行環境の速さで結果が揺れないようにする。
    private func missRate(probability: Double, trials: Int) async -> Double {
        let board = makeBoard(black: [(7, 7), (7, 8), (9, 9), (6, 9)], white: [(7, 9), (8, 8), (6, 6)])
        let best = SimpleGomokuEngine(level: CPUStrength.hard.rawValue, seed: 1, timeLimit: .infinity, maxDepth: 2)
            .analyze(board: board, stone: .white).move!
        var missed = 0
        for i in 0..<trials {
            let e = SimpleGomokuEngine(level: CPUStrength.normal.rawValue, seed: spread(i), timeLimit: .infinity,
                                       maxDepth: 2, policy: SimpleGomokuEngine.policy(probability))
            let m = await e.bestMove(board: board, stone: .white)!
            if m.row != best.0 || m.col != best.1 { missed += 1 }
        }
        return Double(missed) / Double(trials)
    }

    @Test("最善手を外す割合が設定した確率どおりになる（0% と 100% の両端を含む）")
    func missRateFollowsTheProbability() async {
        #expect(await missRate(probability: 1, trials: 20) == 0)
        #expect(await missRate(probability: 0, trials: 20) == 1, "確率 0% は最善手を一度も打たない")
        let rate = await missRate(probability: 0.5, trials: 200)
        #expect(abs(rate - 0.5) < 0.12, "確率 50% の外し率が \(rate)")
    }

    /// 相手の四は、確率 0% でも必ず止める（止めない手は外しの候補に入らない）。自分の五も必ず取る。
    @Test func slipNeverIgnoresAFourOrAWin() async {
        let mustBlock = makeBoard(black: [(7, 3), (7, 4), (7, 5), (7, 6)], white: [(7, 2), (3, 3)])
        let winnable = makeBoard(black: [(3, 10), (4, 10), (5, 10), (1, 1)],
                                 white: [(7, 3), (7, 4), (7, 5), (7, 6)])
        for i in 0..<30 {
            let e = SimpleGomokuEngine(level: CPUStrength.novice.rawValue, seed: spread(i), timeLimit: .infinity,
                                       policy: SimpleGomokuEngine.policy(0))
            let block = await e.bestMove(board: mustBlock, stone: .white)
            #expect(block?.row == 7 && block?.col == 7, "四を止めていない: \(String(describing: block))")
            let win = await e.bestMove(board: winnable, stone: .white)
            #expect(win?.row == 7 && (win?.col == 7 || win?.col == 2), "五を取っていない: \(String(describing: win))")
        }
    }
}

// MARK: - 探索の上限

@Suite("五目並べ CPU の探索の上限")
struct GomokuSearchBudgetTests {

    /// 局面数の上限（計測・テスト用の口）が小さいほど浅くしか読めない。
    @Test func aSmallerNodeLimitReadsLessDeep() {
        let board = makeBoard(black: [(7, 7), (7, 8), (9, 9), (6, 9)], white: [(7, 9), (8, 8), (6, 6)])
        let small = SimpleGomokuEngine(level: CPUStrength.hard.rawValue, seed: 1, timeLimit: .infinity, maxDepth: 6,
                                       nodeLimit: 300).analyze(board: board, stone: .white)
        let large = SimpleGomokuEngine(level: CPUStrength.hard.rawValue, seed: 1, timeLimit: .infinity, maxDepth: 6,
                                       nodeLimit: 20_000).analyze(board: board, stone: .white)
        #expect(small.depth < large.depth, "\(small.depth) / \(large.depth)")
    }

    /// 下の段は深さの上限まで読み終えたら、時間を残して打つ（時間ではなく深さで止まる）。
    @Test func lowerStagesStopAtTheirDepthCap() {
        let board = makeBoard(black: [(7, 7), (7, 8), (9, 9), (6, 9)], white: [(7, 9), (8, 8), (6, 6)])
        for (strength, cap) in [(CPUStrength.novice, 1), (.easy, 1), (.normal, 1)] {
            let r = SimpleGomokuEngine(level: strength.rawValue, seed: 1, timeLimit: .infinity)
                .analyze(board: board, stone: .white)
            #expect(r.depth == cap, "\(strength.label) が深さ \(r.depth) まで読んだ（上限 \(cap)）")
        }
    }
}

// MARK: - 戦術

@Suite("五目並べ CPU の戦術")
struct GomokuTacticsTests {

    /// むずかしいは開三（両端が空いた 3 連）を放置せず、活四を作らせない（深く読ませても足元が崩れていない）。
    @Test func hardDoesNotLoseToAnOpenThree() async {
        let board = makeBoard(black: [(7, 6), (7, 7), (7, 8)], white: [(3, 3), (11, 11)])
        let move = await SimpleGomokuEngine(level: CPUStrength.hard.rawValue, seed: 1, timeLimit: .infinity,
                                            nodeLimit: 30_000).bestMove(board: board, stone: .white)
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

    /// 連珠ルールの黒は、禁じ手（三三）の点を打たない（探索の候補から外れている。外した手番も同じ）。
    /// デバッグビルドで深さ 5 まで読むと 10 回で 1 分を超えるので、深さ 3 で止める。
    @Test func neverPlaysAForbiddenPoint() async {
        let board = makeBoard(black: [(5, 5), (6, 6), (6, 8), (5, 9)], white: [(7, 8), (7, 9), (8, 7), (9, 7)])
        for i in 0..<10 {
            let engine = SimpleGomokuEngine(level: CPUStrength.normal.rawValue, forbiddenMoves: true, seed: spread(i),
                                            timeLimit: .infinity, maxDepth: 3, policy: SimpleGomokuEngine.policy(0.5))
            let move = await engine.bestMove(board: board, stone: .black)
            #expect(!(move?.row == 7 && move?.col == 7), "三三の禁じ手 (7,7) を打った（種 \(i)）")
        }
    }
}
