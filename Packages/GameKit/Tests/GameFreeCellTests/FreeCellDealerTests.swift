import Testing
import Foundation
import Core
@testable import GameFreeCell

@Suite("配札")
struct FreeCellDealerTests {

    @Test("配札はフリーセルの初期配置になる")
    func dealsFreeCellLayout() {
        let board = FreeCellDealer.deal(seed: 12345)
        #expect(board.tableau.count == 8)
        // 8 列へ 1 枚ずつ順に配るので、左 4 列が 7 枚・右 4 列が 6 枚。
        #expect(board.tableau.prefix(4).allSatisfy { $0.count == 7 })
        #expect(board.tableau.suffix(4).allSatisfy { $0.count == 6 })
        #expect(board.cells == Array(repeating: nil, count: 4))
        #expect(board.foundations == [0, 0, 0, 0])
    }

    @Test("52枚がちょうど1枚ずつ配られる")
    func usesEveryCardOnce() {
        let board = FreeCellDealer.deal(seed: 999)
        let all = board.tableau.flatMap { $0 }
        #expect(all.count == 52)
        #expect(Set(all.map(\.id)).count == 52)
    }

    @Test("同じ種はいつでも同じ配札になる")
    func isDeterministic() {
        #expect(FreeCellDealer.deal(seed: 7) == FreeCellDealer.deal(seed: 7))
        #expect(FreeCellDealer.deal(seed: 7) != FreeCellDealer.deal(seed: 8))
    }

    @Test("検証済みの種は十分な数があり、重複していない")
    func verifiedSeedsAreUsable() {
        #expect(FreeCellDealer.verifiedSeeds.count >= 1000)
        #expect(Set(FreeCellDealer.verifiedSeeds).count == FreeCellDealer.verifiedSeeds.count)
    }

    /// **`FreeCellVerifiedSeeds.swift` を作り直す手順**
    ///
    /// 種の並びは「1 から順に試して、ソルバーが勝ち筋を見つけた種を採用したもの」で、
    /// `FreeCellSolver.defaultMaxStates` と手の並び（`successors`）・評価関数（`heuristic`）を
    /// 変えると結果も変わる。ソルバーに手を入れたら、次を実行して出力でファイルの配列を丸ごと
    /// 置き換える:
    ///
    /// ```
    /// FREECELL_REGENERATE_SEEDS=1200 swift test --filter 検証済みの種を作り直す
    /// ```
    ///
    /// デバッグビルドでは 1 配札あたり数秒かかるので、本数が多いときは `-O` でビルドした
    /// 単体バイナリから `FreeCellSolver.solve` を回したほうが速い（GameKit は
    /// `swift test -c release` が通らないため、別パッケージから `GameFreeCell` を
    /// `.product` として読み込む形にする）。
    @Test("検証済みの種を作り直す",
          .enabled(if: ProcessInfo.processInfo.environment["FREECELL_REGENERATE_SEEDS"] != nil))
    func regenerateVerifiedSeeds() {
        let target = Int(ProcessInfo.processInfo.environment["FREECELL_REGENERATE_SEEDS"] ?? "400") ?? 400
        var seeds: [UInt64] = []
        var seed: UInt64 = 1
        while seeds.count < target {
            if FreeCellSolver.solve(FreeCellDealer.deal(seed: seed)).isSolvable { seeds.append(seed) }
            seed += 1
        }
        var out = "let freeCellVerifiedSeeds: [UInt64] = [\n"
        for start in stride(from: 0, to: seeds.count, by: 10) {
            out += "    " + seeds[start..<min(start + 10, seeds.count)]
                .map(String.init).joined(separator: ", ") + ",\n"
        }
        print(out + "]")
    }

    /// 配列の中身が本当に「クリア可能」であることを、**勝ち筋を実際に指し切って**確かめる。
    /// ソルバーの結論をそのまま信じず、公開 API（`apply`）を通してクリアに到達することまで見る。
    @Test("検証済みの種は勝ち筋を指し切ればクリアできる", arguments: [0, 137, 999])
    func verifiedSeedsAreActuallyWinnable(index: Int) {
        let seed = FreeCellDealer.verifiedSeeds[index]
        var board = FreeCellDealer.deal(seed: seed)
        let result = FreeCellSolver.solve(board)
        guard let solution = result.solution else {
            Issue.record("種 \(seed) の勝ち筋が見つからなかった（探索局面 \(result.statesExplored)）")
            return
        }
        for move in solution {
            let didApply = board.apply(move)
            #expect(didApply, "種 \(seed) の勝ち筋に非合法手が混ざっている: \(move)")
        }
        #expect(board.isWon, "種 \(seed) は勝ち筋を指し切ってもクリアにならなかった")
    }

    /// 全件の検証は時間がかかるので、既定では走らせない。
    @Test("検証済みの種を全件確かめる",
          .enabled(if: ProcessInfo.processInfo.environment["FREECELL_VERIFY_ALL_SEEDS"] != nil))
    func allVerifiedSeedsAreWinnable() {
        for seed in FreeCellDealer.verifiedSeeds {
            #expect(FreeCellSolver.solve(FreeCellDealer.deal(seed: seed)).isSolvable,
                    "種 \(seed) の勝ち筋が見つからなかった")
        }
    }

    @Test("出題は検証済みの種からしか選ばない")
    func randomSeedComesFromTheVerifiedList() {
        var rng = FreeCellSeededGenerator(seed: 42)
        let verified = Set(FreeCellDealer.verifiedSeeds)
        for _ in 0..<50 {
            #expect(verified.contains(FreeCellDealer.randomVerifiedSeed(using: &rng)))
        }
    }
}

@Suite("ソルバー")
struct FreeCellSolverTests {

    @Test("あと1手でクリアの局面は解ける")
    func solvesTrivialBoard() {
        var tableau: [[FreeCellCard]] = Array(repeating: [], count: FreeCellBoard.pileCount)
        tableau[0] = [FreeCellCard(.spade, 13)]
        let board = FreeCellBoard(tableau: tableau, foundations: [12, 13, 13, 13])
        let result = FreeCellSolver.solve(board)
        #expect(result.isSolvable)
        #expect(!result.hitLimit)
    }

    @Test("行き止まりの盤面は「クリア不能」と言い切れる")
    func provesDeadEndUnsolvable() {
        var tableau: [[FreeCellCard]] = []
        for suit in PlayingCardSuit.allCases {
            tableau.append((1...6).map { FreeCellCard(suit, $0) })
            tableau.append((7...12).map { FreeCellCard(suit, $0) })
        }
        let board = FreeCellBoard(
            tableau: tableau,
            cells: PlayingCardSuit.allCases.map { FreeCellCard($0, 13) }
        )
        let result = FreeCellSolver.solve(board)
        #expect(!result.isSolvable)
        // 探索を尽くしたうえでの「不能」であること（上限で打ち切った「不明」ではない）。
        #expect(!result.hitLimit)
    }

    @Test("上限に達したら「不明」に倒れる（不能とは言わない）")
    func hitLimitIsUnknownNotUnsolvable() {
        let result = FreeCellSolver.solve(FreeCellDealer.deal(seed: FreeCellDealer.verifiedSeeds[3]),
                                          maxStates: 0)
        #expect(!result.isSolvable)
        #expect(result.hitLimit)
    }

    @Test("取り消されたら「不明」に倒れる")
    func cancellationIsUnknown() {
        let result = FreeCellSolver.solve(FreeCellDealer.deal(seed: FreeCellDealer.verifiedSeeds[3]),
                                          isCancelled: { true })
        #expect(!result.isSolvable)
        #expect(result.hitLimit)
    }

    @Test("安全な組札送りは A と 2 を必ず含む")
    func autoplaySafeSendsAcesAndTwos() {
        var tableau: [[FreeCellCard]] = Array(repeating: [], count: FreeCellBoard.pileCount)
        tableau[0] = [FreeCellCard(.spade, 1)]
        tableau[1] = [FreeCellCard(.spade, 2)]
        // 4 は反対色の組札が進んでいないので、この時点では安全ではない。
        tableau[2] = [FreeCellCard(.spade, 3), FreeCellCard(.spade, 4)]
        let (board, moves) = FreeCellSolver.autoplaySafe(FreeCellBoard(tableau: tableau))
        #expect(!moves.isEmpty)
        #expect(board.foundations[PlayingCardSuit.spade.rawValue] == 2)
        #expect(board.tableau[2].count == 2)
    }

    @Test("勝ち筋の手はすべて合法手として適用できる")
    func solutionIsApplicable() {
        let seed = FreeCellDealer.verifiedSeeds[1]
        var board = FreeCellDealer.deal(seed: seed)
        guard let solution = FreeCellSolver.solve(board).solution else {
            Issue.record("種 \(seed) の勝ち筋が見つからなかった")
            return
        }
        for move in solution {
            let didApply = board.apply(move)
            #expect(didApply, "勝ち筋に非合法手が混ざっている: \(move)")
        }
        #expect(board.isWon)
    }
}
