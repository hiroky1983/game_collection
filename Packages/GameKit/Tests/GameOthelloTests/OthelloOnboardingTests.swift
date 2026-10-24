import Testing
import Core
@testable import GameOthello

/// 図で見る「はじめての遊び方」（#2825）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("オセロ: はじめての遊び方")
struct OthelloOnboardingTests {
    /// 図の盤（左上の隅）を 8×8 の盤へ写す。
    private func board(_ rows: [String]) -> OthelloBoard {
        var b = OthelloBoard(cells: [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize))
        for (r, line) in rows.enumerated() {
            for (c, ch) in line.enumerated() {
                if ch == "B" { b[r, c] = .black }
                if ch == "W" { b[r, c] = .white }
            }
        }
        return b
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(OthelloOnboarding.guide.isWellFormed)
        #expect(OthelloOnboarding.guide.gameID == OthelloModel(services: nil).gameID)
    }

    @Test("置ける○: 図の 4 マスだけに黒が置ける")
    func hints() {
        let b = board([".....", ".WB..", ".BW.."])
        let corner = Set(b.validMoves(for: .black).filter { $0.0 < 4 && $0.1 < 4 }.map { [$0.0, $0.1] })
        #expect(corner == [[0, 1], [1, 0], [2, 3], [3, 2]])
    }

    @Test("はさむと裏返る: 黒を置くとあいだの白 2 つが黒になる")
    func flip() {
        var b = board(["BWW."])
        #expect(b.flippable(row: 0, col: 3, stone: .black).count == 2)
        b.place(row: 0, col: 3, stone: .black)
        #expect((0..<4).allSatisfy { b[0, $0] == .black })
    }

    @Test("置けないとき: 黒は置けず、白は置ける（黒がパスして白の番になる）")
    func pass() {
        let b = board([OthelloOnboarding.passRow])
        #expect(b.validMoves(for: .black).isEmpty)
        #expect(!b.validMoves(for: .white).isEmpty)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in OthelloOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
