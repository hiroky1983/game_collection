import Testing
import CoreEngine
@testable import GameChess

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("チェス: 英語の文言")
struct ChessLocalizationTests {

    @Test("表示名・駒の名前・終局の理由に英語の訳がある")
    func englishTerms() {
        #expect(GameChess.tr("チェス", language: .english) == "Chess")
        #expect(GameChess.tr("ナイト", language: .english) == "Knight")
        #expect(GameChess.tr("チェックメイト", language: .english) == "Checkmate")
        #expect(GameChess.tr("アンパッサン", language: .english) == "En passant")
        #expect(GameChess.tr("%1$@の%2$@", "White", "Knight", language: .english) == "White Knight")
        #expect(GameChess.tr("%lld手", 1, language: .english) == "1 move")
        #expect(GameChess.tr("%lld手", 12, language: .english) == "12 moves")
    }
}
