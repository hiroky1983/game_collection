import Testing
import Core
@testable import GameGomoku

/// 図で見る「はじめての遊び方」（#2825）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("五目並べ: はじめての遊び方")
struct GomokuOnboardingTests {
    private func board(black: [(Int, Int)] = [], white: [(Int, Int)] = []) -> GomokuBoard {
        var b = GomokuBoard()
        for (r, c) in black { b[r, c] = .black }
        for (r, c) in white { b[r, c] = .white }
        return b
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まる。禁じ手ありのときだけ 1 枚多い")
    func wellFormed() {
        let free = GomokuOnboarding.guide(forbiddenMoves: false)
        let renju = GomokuOnboarding.guide(forbiddenMoves: true)
        #expect(free.isWellFormed)
        #expect(renju.isWellFormed)
        #expect(renju.pages.count == free.pages.count + 1)
        #expect(free.gameID == GomokuModel(services: nil).gameID)
    }

    @Test("たて・よこ・ななめのどれでも 5 つで勝ち")
    func fiveInAnyDirection() {
        #expect(board(black: (0..<5).map { (7, 4 + $0) }).checkWin(row: 7, col: 8))
        #expect(board(black: (0..<5).map { (4 + $0, 7) }).checkWin(row: 8, col: 7))
        #expect(board(black: (0..<5).map { (4 + $0, 4 + $0) }).checkWin(row: 8, col: 8))
    }

    @Test("止める図: 4 つ並んだ端に置かれると 5 つ目ができない")
    func block() {
        let four = (1...4).map { (7, 4 + $0) }
        #expect(board(black: four + [(7, 9)], white: [(7, 4)]).checkWin(row: 7, col: 9))
        #expect(!board(black: four, white: [(7, 4), (7, 9)]).checkWin(row: 7, col: 8))
    }

    @Test("禁じ手の図: 黒の三三の点は禁じ手ありで打てない")
    func doubleThree() {
        let b = board(black: [(7, 5), (7, 6), (5, 7), (6, 7)])
        #expect(b.renjuForbidden(row: 7, col: 7) == .doubleThree)
    }

    @Test("長連: 自由五目では 6 つでも勝ち。禁じ手ありでは黒の長連は打てず、白は勝つ")
    func overline() {
        let six = board(black: [(7, 3), (7, 4), (7, 5), (7, 7), (7, 8), (7, 6)])
        #expect(six.checkWin(row: 7, col: 6))
        let beforeSix = board(black: [(7, 3), (7, 4), (7, 5), (7, 7), (7, 8)])
        #expect(beforeSix.renjuForbidden(row: 7, col: 6) == .overline)
        var whiteSix = board(white: [(7, 3), (7, 4), (7, 5), (7, 7), (7, 8)])
        whiteSix[7, 6] = .white
        #expect(whiteSix.winningLine(row: 7, col: 6)?.count == 6)
    }

    @Test("勝ちの図: ななめに 5 つ並ぶ")
    func winFigure() {
        let b = board(black: (0..<5).map { (4 + $0, 4 + $0) }, white: [(4, 7), (6, 8), (8, 5)])
        #expect(b.checkWin(row: 8, col: 8))
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for renju in [false, true] {
            for text in GomokuOnboarding.guide(forbiddenMoves: renju).texts {
                #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
            }
        }
    }
}
