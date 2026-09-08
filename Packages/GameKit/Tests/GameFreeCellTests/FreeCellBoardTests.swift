import Testing
import Foundation
import Core
@testable import GameFreeCell

@Suite("フリーセルの盤面と規則")
struct FreeCellBoardTests {

    /// 空の盤（8列すべて空・セルも空）。局面を手で組むための下地。
    private func emptyBoard() -> FreeCellBoard {
        FreeCellBoard(tableau: Array(repeating: [], count: FreeCellBoard.pileCount))
    }

    // MARK: - 場札の並び

    @Test("降順・交互色の並びだけがまとめて動かせる")
    func orderedRun() {
        var board = emptyBoard()
        board.tableau[0] = [FreeCellCard(.spade, 8), FreeCellCard(.heart, 7), FreeCellCard(.club, 6)]
        #expect(board.isOrderedRun(pile: 0, from: 0))
        #expect(board.isOrderedRun(pile: 0, from: 1))
        #expect(board.isOrderedRun(pile: 0, from: 2))

        // 同色が続いたら並びではない。
        board.tableau[1] = [FreeCellCard(.spade, 8), FreeCellCard(.club, 7)]
        #expect(!board.isOrderedRun(pile: 1, from: 0))
        #expect(board.isOrderedRun(pile: 1, from: 1))

        // ランクが飛んでいたら並びではない。
        board.tableau[2] = [FreeCellCard(.spade, 8), FreeCellCard(.heart, 6)]
        #expect(!board.isOrderedRun(pile: 2, from: 0))
    }

    @Test("範囲外の添字は動かせる並びとして扱わない")
    func orderedRunOutOfRange() {
        var board = emptyBoard()
        board.tableau[0] = [FreeCellCard(.spade, 8)]
        #expect(!board.isOrderedRun(pile: 0, from: 1))
        #expect(!board.isOrderedRun(pile: 0, from: -1))
        #expect(!board.isOrderedRun(pile: 99, from: 0))
    }

    @Test("場札には1つ小さくて色ちがいの札だけ置ける")
    func placementRule() {
        var board = emptyBoard()
        board.tableau[0] = [FreeCellCard(.spade, 8)]
        #expect(board.canPlace([FreeCellCard(.heart, 7)], onPile: 0))
        #expect(board.canPlace([FreeCellCard(.diamond, 7)], onPile: 0))
        #expect(!board.canPlace([FreeCellCard(.club, 7)], onPile: 0))   // 同色
        #expect(!board.canPlace([FreeCellCard(.heart, 6)], onPile: 0))  // ランクが飛ぶ
        #expect(!board.canPlace([FreeCellCard(.heart, 9)], onPile: 0))  // 昇順
    }

    /// クロンダイク（空列は K だけ）との決定的な違い。
    @Test("空いた列にはどの札でも置ける")
    func anyCardOnEmptyPile() {
        let board = emptyBoard()
        for rank in 1...13 {
            #expect(board.canPlace([FreeCellCard(.spade, rank)], onPile: 0))
        }
    }

    // MARK: - 連続移動の上限（受け入れ条件: 境界テスト）

    @Test("上限は（空きセル + 1）×（2の空き列数乗）",
          arguments: [
            // (埋まっているセル, 空いている列, 期待する上限)
            (filled: 4, empty: 0, expected: 1), (filled: 3, empty: 0, expected: 2),
            (filled: 0, empty: 0, expected: 5), (filled: 4, empty: 1, expected: 2),
            (filled: 3, empty: 1, expected: 4), (filled: 0, empty: 1, expected: 10),
            (filled: 0, empty: 2, expected: 20), (filled: 2, empty: 3, expected: 24),
          ])
    func maxMovableCount(testCase: (filled: Int, empty: Int, expected: Int)) {
        let filledCells = testCase.filled
        let emptyPiles = testCase.empty
        let expected = testCase.expected
        var board = emptyBoard()
        // 空でない列を作るために、まず全列へ1枚ずつ置いてから空けたい本数を取り除く。
        var deck = FreeCellCard.makeDeck()
        for pile in board.tableau.indices {
            board.tableau[pile] = [deck.removeFirst()]
        }
        for pile in 0..<emptyPiles { board.tableau[pile] = [] }
        for cell in 0..<filledCells { board.cells[cell] = deck.removeFirst() }

        #expect(board.freeCellCount == FreeCellBoard.cellCount - filledCells)
        #expect(board.emptyPileCount == emptyPiles)
        #expect(board.maxMovableCount() == expected)
    }

    /// フリーセル実装で最も典型的な取りこぼし。置き先の空列は退避先として使えない。
    @Test("置き先が空列のときは、その列を空き列に数えない")
    func emptyDestinationIsNotCounted() {
        var board = emptyBoard()
        var deck = FreeCellCard.makeDeck()
        for pile in 1..<FreeCellBoard.pileCount { board.tableau[pile] = [deck.removeFirst()] }
        // 空列は 0 番の1本だけ・セルは全部空き。
        #expect(board.emptyPileCount == 1)
        #expect(board.maxMovableCount() == 10)            // (4+1) × 2^1
        #expect(board.maxMovableCount(destination: 0) == 5)   // 置き先が空列 → (4+1) × 2^0
        #expect(board.maxMovableCount(destination: 1) == 10)  // 置き先が空でない列 → そのまま
    }

    @Test("上限を超える枚数はまとめて置けない")
    func placementRespectsTheLimit() {
        var board = emptyBoard()
        // セルを全部埋め、空列も作らない → 一度に動かせるのは1枚だけ。
        var deck = FreeCellCard.makeDeck()
        for cell in board.cells.indices { board.cells[cell] = deck.removeFirst() }
        for pile in board.tableau.indices { board.tableau[pile] = [deck.removeFirst()] }
        board.tableau[0] = [FreeCellCard(.spade, 9)]
        let run = [FreeCellCard(.heart, 8), FreeCellCard(.club, 7)]
        #expect(board.maxMovableCount() == 1)
        #expect(!board.canPlace(run, onPile: 0))
        #expect(board.canPlace([FreeCellCard(.heart, 8)], onPile: 0))

        // セルを1つ空けると2枚まで動かせるようになる。
        board.cells[0] = nil
        #expect(board.maxMovableCount() == 2)
        #expect(board.canPlace(run, onPile: 0))
    }

    // MARK: - 手の適用

    @Test("組札は A から順にしか積めない")
    func foundationOrder() {
        var board = emptyBoard()
        board.tableau[0] = [FreeCellCard(.spade, 2)]
        // A より先に 2 は積めない。
        let sentTwoFirst = board.apply(.tableauToFoundation(pile: 0))
        #expect(!sentTwoFirst)

        board.tableau[1] = [FreeCellCard(.spade, 1)]
        let sentAce = board.apply(.tableauToFoundation(pile: 1))
        #expect(sentAce)
        #expect(board.foundations[PlayingCardSuit.spade.rawValue] == 1)

        let sentTwo = board.apply(.tableauToFoundation(pile: 0))
        #expect(sentTwo)
        #expect(board.foundations[PlayingCardSuit.spade.rawValue] == 2)
    }

    @Test("セルは1枚だけ持ち、埋まっていれば入れられない")
    func cellsHoldOneCard() {
        var board = emptyBoard()
        board.tableau[0] = [FreeCellCard(.spade, 5), FreeCellCard(.heart, 9)]
        let intoEmptyCell = board.apply(.tableauToCell(from: 0, cell: 0))
        #expect(intoEmptyCell)
        #expect(board.cells[0] == FreeCellCard(.heart, 9))
        #expect(board.tableau[0] == [FreeCellCard(.spade, 5)])

        // 同じセルにはもう入らない。
        let intoFilledCell = board.apply(.tableauToCell(from: 0, cell: 0))
        #expect(!intoFilledCell)

        // 別のセルには入る。
        let intoAnotherCell = board.apply(.tableauToCell(from: 0, cell: 1))
        #expect(intoAnotherCell)
        #expect(board.tableau[0].isEmpty)
    }

    @Test("セルから場札・組札へ戻せる")
    func cellsCanBeEmptied() {
        var board = emptyBoard()
        board.cells[2] = FreeCellCard(.heart, 7)
        board.tableau[0] = [FreeCellCard(.spade, 8)]
        let backToTableau = board.apply(.cellToTableau(cell: 2, to: 0))
        #expect(backToTableau)
        #expect(board.cells[2] == nil)
        #expect(board.tableau[0].last == FreeCellCard(.heart, 7))

        board.cells[3] = FreeCellCard(.club, 1)
        let toFoundation = board.apply(.cellToFoundation(cell: 3))
        #expect(toFoundation)
        #expect(board.cells[3] == nil)
        #expect(board.foundations[PlayingCardSuit.club.rawValue] == 1)
    }

    @Test("非合法な手は盤面を変えずに false を返す")
    func illegalMovesAreRejected() {
        var board = emptyBoard()
        board.tableau[0] = [FreeCellCard(.spade, 8)]
        let before = board
        let sameColumn = board.apply(.tableauToTableau(from: 0, cardIndex: 0, to: 0))
        let pileOutOfRange = board.apply(.tableauToTableau(from: 9, cardIndex: 0, to: 1))
        let fromEmptyCell = board.apply(.cellToTableau(cell: 0, to: 1))
        let cellOutOfRange = board.apply(.cellToFoundation(cell: 9))
        let fromEmptyPile = board.apply(.tableauToCell(from: 1, cell: 0))
        #expect(!sameColumn)
        #expect(!pileOutOfRange)
        #expect(!fromEmptyCell)
        #expect(!cellOutOfRange)
        #expect(!fromEmptyPile)
        #expect(board == before)
    }

    @Test("まとめて動かすと並びが丸ごと移る")
    func superMove() {
        var board = emptyBoard()
        board.tableau[0] = [FreeCellCard(.diamond, 4),
                            FreeCellCard(.spade, 3), FreeCellCard(.heart, 2)]
        // 動かす並びの下端は ♠3（黒）なので、置き先は赤の 4 でなければならない。
        board.tableau[1] = [FreeCellCard(.heart, 4)]
        let movedRun = board.apply(.tableauToTableau(from: 0, cardIndex: 1, to: 1))
        #expect(movedRun)
        #expect(board.tableau[0] == [FreeCellCard(.diamond, 4)])
        #expect(board.tableau[1] == [FreeCellCard(.heart, 4),
                                     FreeCellCard(.spade, 3), FreeCellCard(.heart, 2)])

        // 同色の 4（♣）へは置けない。
        var sameColor = emptyBoard()
        sameColor.tableau[0] = [FreeCellCard(.diamond, 4),
                                FreeCellCard(.spade, 3), FreeCellCard(.heart, 2)]
        sameColor.tableau[1] = [FreeCellCard(.club, 4)]
        let ontoSameColor = sameColor.apply(.tableauToTableau(from: 0, cardIndex: 1, to: 1))
        #expect(!ontoSameColor)
    }

    // MARK: - 決着と行き止まり

    @Test("4スートすべてが K まで積まれたら勝ち")
    func winCondition() {
        var board = emptyBoard()
        #expect(!board.isWon)
        board.foundations = [13, 13, 13, 12]
        #expect(!board.isWon)
        board.foundations = [13, 13, 13, 13]
        #expect(board.isWon)
    }

    /// フリーセルの行き止まりは**合法手が本当にゼロ**。近似が入らないことを実際の盤面で固定する。
    @Test("合法手がゼロの盤面だけが行き止まりになる")
    func deadEnd() {
        // セルに K を4枚（rank+1 が存在しないのでどこにも置けない）、
        // 場札はスートごとに A〜6 / 7〜Q を昇順に積んだ 8 列（上は 6 と Q だけ）。
        var tableau: [[FreeCellCard]] = []
        for suit in PlayingCardSuit.allCases {
            tableau.append((1...6).map { FreeCellCard(suit, $0) })
            tableau.append((7...12).map { FreeCellCard(suit, $0) })
        }
        let board = FreeCellBoard(
            tableau: tableau,
            cells: PlayingCardSuit.allCases.map { FreeCellCard($0, 13) }
        )
        #expect(board.legalMoves.isEmpty)
        #expect(board.isDeadEnd)

        // セルを1つ空けるだけで退避できるようになり、行き止まりではなくなる。
        var loosened = board
        loosened.cells[0] = nil
        #expect(!loosened.isDeadEnd)
        #expect(!loosened.legalMoves.isEmpty)
    }

    @Test("勝っている盤面は行き止まりにしない")
    func wonBoardIsNotDeadEnd() {
        var board = emptyBoard()
        board.foundations = [13, 13, 13, 13]
        #expect(board.legalMoves.isEmpty)
        #expect(!board.isDeadEnd)
    }

    @Test("列挙した合法手はすべて実際に適用できる")
    func legalMovesAreApplicable() {
        var board = FreeCellDealer.deal(seed: FreeCellDealer.verifiedSeeds[0])
        // 少し進めた局面でも確かめたいので、序盤を機械的に指してから見る。
        for _ in 0..<12 {
            guard let move = board.legalMoves.first else { break }
            let didApply = board.apply(move)
            #expect(didApply)
            for candidate in board.legalMoves {
                var probe = board
                let applied = probe.apply(candidate)
                #expect(applied, "列挙された手が適用できない: \(candidate)")
            }
        }
    }

    // MARK: - 探索用のキー

    /// 列とセルの並びはルールに一切効かないので、正準化していないと探索が同じ局面を掘り直す。
    @Test("列とセルを並べ替えても同じ局面として扱う")
    func stateKeyIsCanonical() {
        var a = emptyBoard()
        a.tableau[0] = [FreeCellCard(.spade, 5)]
        a.tableau[3] = [FreeCellCard(.heart, 9)]
        a.cells[0] = FreeCellCard(.club, 2)
        a.cells[2] = FreeCellCard(.diamond, 4)

        var b = emptyBoard()
        b.tableau[6] = [FreeCellCard(.heart, 9)]
        b.tableau[7] = [FreeCellCard(.spade, 5)]
        b.cells[1] = FreeCellCard(.diamond, 4)
        b.cells[3] = FreeCellCard(.club, 2)

        #expect(a.stateKey == b.stateKey)

        // 中身が違えば別の局面になる。
        var c = a
        c.foundations[0] = 1
        #expect(a.stateKey != c.stateKey)
    }

    /// 正準化は「列の中の並び」までは崩さない。崩すと本当に違う局面まで同一視してしまう。
    @Test("列の中の並びが違えば別の局面になる")
    func stateKeyKeepsPileOrder() {
        var a = emptyBoard()
        a.tableau[0] = [FreeCellCard(.spade, 5), FreeCellCard(.heart, 4)]
        var b = emptyBoard()
        b.tableau[0] = [FreeCellCard(.heart, 4), FreeCellCard(.spade, 5)]
        #expect(a.stateKey != b.stateKey)
    }
}
