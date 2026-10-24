import Testing
import Core
@testable import GameFreeCell

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("フリーセル: はじめての遊び方")
struct FreeCellOnboardingTests {
    private func board(_ tableau: [[FreeCellCard]] = [], cells: [FreeCellCard?]? = nil,
                       foundations: [Int] = [0, 0, 0, 0]) -> FreeCellBoard {
        var tableau = tableau
        while tableau.count < FreeCellBoard.pileCount { tableau.append([]) }
        if let cells { return FreeCellBoard(tableau: tableau, cells: cells, foundations: foundations) }
        return FreeCellBoard(tableau: tableau, foundations: foundations)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(FreeCellOnboarding.guide.isWellFormed)
        #expect(FreeCellOnboarding.guide.gameID == "freecell")
    }

    @Test("フリーセルは 4 つで、札を 1 枚ずつ置け、列や組札へ戻せる")
    func cells() {
        #expect(FreeCellBoard.cellCount == 4)
        let card = FreeCellCard(.spade, 1)
        var b = board([[card]])
        #expect(b.isLegal(.tableauToCell(from: 0, cell: 0)))
        let moved = b.apply(.tableauToCell(from: 0, cell: 0))
        #expect(moved)
        #expect(b.cells[0] == card && b.freeCellCount == 3)
        #expect(b.isLegal(.cellToFoundation(cell: 0)))
        #expect(b.isLegal(.cellToTableau(cell: 0, to: 1)))
        // 1 つの枠には 1 枚しか入らない。
        #expect(!b.isLegal(.tableauToCell(from: 0, cell: 0)))
    }

    @Test("重ね方の図: 黒の 8 に赤の 7 は置け、同色の 7 は置けない")
    func stacking() {
        let b = board([[FreeCellCard(.spade, 8)]])
        #expect(b.canPlace([FreeCellCard(.heart, 7)], onPile: 0))
        #expect(!b.canPlace([FreeCellCard(.club, 7)], onPile: 0))
    }

    @Test("空いた列にはどの札でも置ける。空きが多いほど、まとめて動かせる枚数が増える")
    func emptyColumnAndRunLimit() {
        let b = board()
        #expect(b.canPlace([FreeCellCard(.diamond, 5)], onPile: 0))
        let full = [FreeCellCard?](repeating: FreeCellCard(.spade, 1), count: FreeCellBoard.cellCount)
        let crowded = board([[FreeCellCard(.club, 2)]], cells: full)
        // 空きセル 0・空き列 7 本（置き先が空列なら 6 本）。
        #expect(crowded.maxMovableCount() > 1)
        let half = board([[FreeCellCard(.club, 2)]], cells: [nil, nil, FreeCellCard(.spade, 1), FreeCellCard(.heart, 1)])
        let none = board((0..<FreeCellBoard.pileCount).map { [FreeCellCard(.club, $0 + 1)] }, cells: full)
        #expect(none.maxMovableCount() == 1)
        #expect(half.maxMovableCount() > none.maxMovableCount())
    }

    @Test("4 つの組札が K まで積み上がったらクリア")
    func win() {
        #expect(!board(foundations: [13, 13, 13, 12]).isWon)
        #expect(board(foundations: [13, 13, 13, 13]).isWon)
    }

    @Test("文言の数字（フリーセルの数）が実装の値から作られ、全部の文言に英語の訳がある")
    func numbersAndEnglish() {
        let key = "左上の %lld つの枠が「フリーセル」です。"
        let lines = FreeCellOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("左上の \(FreeCellBoard.cellCount) つの枠が「フリーセル」です。"))
        #expect(tr.hasTranslation(key, language: .english))
        let filled = tr(key, FreeCellBoard.cellCount)
        for text in FreeCellOnboarding.guide.texts where text != filled {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
