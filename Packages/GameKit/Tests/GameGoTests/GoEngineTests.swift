import Testing
import Foundation
@testable import GameGo

/// 自己対戦の道具。実時間で打ち切ると再現しないので `timeLimit` は常に nil。
enum GoSelfPlay {
    struct Result {
        var finalState: GoState
        var score: GoScore
        var moves: [GoMove]
    }

    static func play(
        black: Int,
        white: Int,
        ruleset: GoRuleset = GoRuleset(size: 9),
        seed: UInt64,
        maxMoves: Int = 300
    ) -> Result {
        var state = GoState.initial(ruleset: ruleset)
        var moves: [GoMove] = []
        while !state.isTwoPassEnd, moves.count < maxMoves {
            let playouts = state.sideToMove == .black ? black : white
            // 手番・手数ごとに種をずらす（同じ種を使い回すと毎手まったく同じ探索になる）。
            let engine = GoEngine(
                config: GoEngineConfig(
                    playouts: playouts,
                    seed: seed &+ UInt64(moves.count) &* 0x9E37,
                    timeLimit: nil
                ),
                ruleset: ruleset
            )
            let move = engine.bestMove(state: state)
            let rejection = state.play(move)
            #expect(rejection == nil, "CPU が非合法手を選んだ: \(move) / \(String(describing: rejection))")
            moves.append(move)
        }
        return Result(
            finalState: state,
            score: GoScoring.score(board: state.board, ruleset: ruleset),
            moves: moves
        )
    }
}

@Suite("囲碁の CPU: 決定性と合法性")
struct GoEngineBasicTests {

    private let ruleset = GoRuleset(size: 9)

    @Test("同じ種・同じ局面なら常に同じ手を返す")
    func isDeterministicForTheSameSeed() {
        let state = GoState.initial(ruleset: ruleset)
        let config = GoEngineConfig(playouts: 200, seed: 4242, timeLimit: nil)
        let engine = GoEngine(config: config, ruleset: ruleset)
        let first = engine.bestMove(state: state)
        for _ in 0..<2 {
            #expect(GoEngine(config: config, ruleset: ruleset).bestMove(state: state) == first)
        }
    }

    @Test("種が違えば別の手も選びうる（探索が乱数に効いている）")
    func differentSeedsCanDiverge() {
        let state = GoState.initial(ruleset: ruleset)
        let moves = Set((0..<6).map { seed -> GoMove in
            GoEngine(
                config: GoEngineConfig(playouts: 80, seed: UInt64(seed) &* 7919 &+ 1, timeLimit: nil),
                ruleset: ruleset
            ).bestMove(state: state)
        })
        #expect(moves.count > 1, "どの種でも同じ手なら乱数が効いていない")
    }

    @Test("返す手は必ず合法（ランダムな局面 30 件）")
    func alwaysReturnsALegalMove() {
        var random = GoRandom(seed: 0xBEEF)
        for iteration in 0..<30 {
            var state = GoState.initial(ruleset: ruleset)
            for _ in 0..<random.index(below: 60) {
                state.play(GoPlayout.move(in: state, random: &random))
            }
            guard !state.isTwoPassEnd else { continue }
            let engine = GoEngine(
                config: GoEngineConfig(playouts: 30, seed: UInt64(iteration) &+ 1, timeLimit: nil),
                ruleset: ruleset
            )
            let move = engine.bestMove(state: state)
            #expect(state.isLegal(move), "非合法手を返した: \(move)\n\(GoDiagram.text(state.board))")
        }
    }

    @Test("序盤ではパスしない（面積計算だけを見て投げ出さない）")
    func doesNotPassInTheOpening() {
        var state = GoState.initial(ruleset: ruleset)
        var random = GoRandom(seed: 7)
        for ply in 0..<12 {
            let engine = GoEngine(
                config: GoEngineConfig(playouts: 50, seed: UInt64(ply) &+ 31, timeLimit: nil),
                ruleset: ruleset
            )
            #expect(engine.bestMove(state: state) != .pass, "\(ply) 手目でパスした")
            state.play(GoPlayout.move(in: state, random: &random))
        }
    }

    @Test("打つところが眼しか残っていなければパスする")
    func passesWhenOnlyEyesRemain() {
        // 盤全体が黒石で、空点は黒の眼が 2 つだけ。黒はどちらも埋めたくない。
        var cells = [GoStone?](repeating: .black, count: 81)
        cells[1 * 9 + 1] = nil
        cells[7 * 9 + 7] = nil
        let state = GoState(board: GoBoard(size: 9, cells: cells), sideToMove: .black)
        let engine = GoEngine(
            config: GoEngineConfig(playouts: 50, seed: 5, timeLimit: nil),
            ruleset: ruleset
        )
        #expect(engine.bestMove(state: state) == .pass)
    }

    @Test("ダメが無くなって勝っているならパスを候補に入れる")
    func considersPassWhenTheBoardIsSettled() {
        // 地の境界が決まりきった局面。左下の空所は黒地なので中立の点は 0 で、
        // 面積は黒 40（石 24 + 地 16）・白 41。コミ 6.5 を足した白が勝っている。
        // 空所が残っているので「打てる手が無いからパス」ではないことも同時に確かめられる。
        let board = GoDiagram.board([
            "XXXXOOOOO",
            "XXXXOOOOO",
            "XXXXOOOOO",
            "XXXXOOOOO",
            "XXXXOOOOO",
            "....XOOOO",
            "....XOOOO",
            "....XOOOO",
            "....XOOOO",
        ])
        #expect(GoScoring.area(of: board) == (black: 40, white: 41, neutral: 0))
        let engine = GoEngine(config: GoEngineConfig(playouts: 10, seed: 1, timeLimit: nil), ruleset: ruleset)
        #expect(engine.rootCandidates(GoState(board: board, sideToMove: .white)).contains(.pass),
                "勝っている白はパスを選べるべき")
        #expect(!engine.rootCandidates(GoState(board: board, sideToMove: .black)).contains(.pass),
                "負けている黒がパスで終わらせてはいけない")
    }

    @Test("実時間の上限を超えたら打ち切る（プレイアウト数を使い切らない）")
    func respectsTheTimeLimit() {
        let state = GoState.initial(ruleset: ruleset)
        // 上限 0 秒 = 32 回ごとの検査で即座に打ち切る。極端に大きなプレイアウト数でも一瞬で返る。
        let engine = GoEngine(
            config: GoEngineConfig(playouts: 5_000_000, seed: 3, timeLimit: 0),
            ruleset: ruleset
        )
        let clock = ContinuousClock()
        let started = clock.now
        let move = engine.bestMove(state: state)
        let elapsed = clock.now - started
        #expect(state.isLegal(move))
        #expect(elapsed < .seconds(5), "実時間の上限が効いていない（\(elapsed)）")
    }

    @Test("強さ 3 段階はプレイアウト数と持ち時間の両方で分かれている")
    func levelsAreOrdered() {
        #expect(GoLevel.easy.playouts < GoLevel.normal.playouts)
        #expect(GoLevel.normal.playouts < GoLevel.hard.playouts)
        // 遅い端末で普通と強が同じ上限に張り付かないよう、持ち時間も段階で分ける。
        #expect(GoLevel.easy.timeLimit < GoLevel.normal.timeLimit)
        #expect(GoLevel.normal.timeLimit < GoLevel.hard.timeLimit)
        #expect(GoLevel.allCases.allSatisfy { $0.timeLimit <= 1.0 }, "1 手 1 秒以内に収める")
    }
}

@Suite("囲碁の CPU: 強さの体感差", .timeLimit(.minutes(5)))
struct GoEngineStrengthTests {

    /// 受け入れ条件「CPU 3 段階に体感差がある（自己対戦の勝率で検証しテスト化）」。
    ///
    /// 種を固定しているので**結果は決定的**（実時間で打ち切らないので実行環境にも依存しない）。
    /// 8 局を先後入れ替えて打ち、読みの多い側が勝ち越すことを確認する。
    ///
    /// **5 路盤で行う**。CI は最適化なしのデバッグビルドで走るため 9 路の自己対戦 8 局は
    /// 分単位になってしまう。読みの量が強さに効くかどうかは盤の大きさに依らないので、
    /// 検証したい性質はそのまま確かめられる（1 交点あたりの探索密度はむしろ 5 路のほうが高く、
    /// 差が出るかどうかの試験としては厳しい側）。
    @Test("読みの多い CPU が勝ち越す（8 局・先後入れ替え）")
    func strongerLevelWinsMoreOften() {
        let weak = 20
        let strong = 400
        var strongWins = 0
        for game in 0..<8 {
            let strongIsBlack = game % 2 == 0
            let result = GoSelfPlay.play(
                black: strongIsBlack ? strong : weak,
                white: strongIsBlack ? weak : strong,
                ruleset: GoRuleset(size: 5),
                seed: UInt64(game) &* 104_729 &+ 17
            )
            guard let winner = result.score.winner else { continue }
            if (winner == .black) == strongIsBlack { strongWins += 1 }
        }
        #expect(strongWins >= 5, "強い側の勝ち数が 8 局中 \(strongWins) 局しかない")
    }
}

@Suite("囲碁の自己対戦: 不変条件", .timeLimit(.minutes(5)))
struct GoSelfPlayPropertyTests {

    /// #398 のプロパティテスト: (a) 全着手が合法 (b) 必ず終局する (c) 保存則 (d) クラッシュゼロ。
    @Test("ランダム自己対戦 300 局で不変条件が崩れない")
    func randomSelfPlayKeepsInvariants() {
        let ruleset = GoRuleset(size: 9)
        var random = GoRandom(seed: 0x9A55)
        for game in 0..<300 {
            var state = GoState.initial(ruleset: ruleset)
            var plies = 0
            let limit = state.board.pointCount * GoPlayout.moveLimitFactor
            while !state.isTwoPassEnd, plies < limit {
                let move = GoPlayout.move(in: state, random: &random)
                // (a) 生成した手は必ず合法。
                #expect(state.play(move) == nil, "非合法手が生成された: \(move)")
                plies += 1
            }
            // (b) 手数上限に達する前に両者パスで終わる。
            #expect(state.isTwoPassEnd, "\(game) 局目が終局しなかった\n\(GoDiagram.text(state.board))")
            // (c) 保存則。
            let counted = GoScoring.area(of: state.board)
            #expect(counted.black + counted.white + counted.neutral == state.board.pointCount)
        }
    }

    @Test("MCTS 同士の自己対戦も必ず終局し、全着手が合法（9 路）")
    func engineSelfPlayTerminates() {
        let result = GoSelfPlay.play(black: 25, white: 25, seed: 500)
        #expect(result.finalState.isTwoPassEnd, "終局しなかった\n\(GoDiagram.text(result.finalState.board))")
        #expect(result.score.winner != nil)
        #expect(result.moves.count < 300, "手数上限に張り付いている")
    }
}
