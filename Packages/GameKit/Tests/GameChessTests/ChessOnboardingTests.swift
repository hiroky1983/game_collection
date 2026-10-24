import Testing
import Core
@testable import GameChess

/// 図で見る「はじめての遊び方」（#2827）の図が、実装のルールのとおりに指せる・詰む・引き分けになること。
@MainActor
@Suite("チェス: はじめての遊び方")
struct ChessOnboardingTests {
    private func position(_ name: String) -> ChessPosition {
        ChessPosition.fromFEN(ChessOnboarding.sampleFENs[name]!)!
    }

    private func move(_ uci: String, in position: ChessPosition) -> ChessMove? {
        ChessMove.fromUCI(uci).flatMap { position.legalMoves().contains($0) ? $0 : nil }
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(ChessOnboarding.guide.isWellFormed)
        #expect(ChessOnboarding.guide.gameID == ChessGameModel().gameID)
    }

    @Test("キャスリング: キングを 2 マス動かして入れ替われる")
    func castling() throws {
        let pos = position("castling")
        let castle = try #require(move("e1g1", in: pos))
        #expect(pos.isCastling(castle))
    }

    @Test("アンパッサン: 2 マス進んだ直後のポーンを、通り過ぎたマスへ斜めに取れる")
    func enPassant() throws {
        let pos = position("enPassant")
        let capture = try #require(move("e5d6", in: pos))
        #expect(pos.isEnPassant(capture))
    }

    @Test("プロモーション: 奥に届いたポーンはクイーンなど好きな駒になれる")
    func promotion() throws {
        let pos = position("promotion")
        let queen = try #require(move("a7a8q", in: pos))
        #expect(queen.promotion == .queen)
    }

    @Test("王手: キングが狙われているが、逃げる手は残っている")
    func check() {
        let pos = position("check")
        #expect(pos.isKingInCheck(.black))
        #expect(!pos.legalMoves().isEmpty)
    }

    @Test("チェックメイト: 王手で逃げ場が無い")
    func checkmate() {
        let pos = position("mate")
        #expect(pos.isKingInCheck(.black))
        #expect(pos.legalMoves().isEmpty)
    }

    @Test("ステイルメイト: 王手ではないのに動ける手が無い（引き分け）")
    func stalemate() {
        let pos = position("stalemate")
        #expect(!pos.isKingInCheck(.black))
        #expect(pos.legalMoves().isEmpty)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in ChessOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
