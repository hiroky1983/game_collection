import Testing
import CoreEngine
@testable import GameShogi

/// 将棋の英語の文言（#2166）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
/// `AppLanguageStore.shared` は書き換えない（並列のテストが巻き込まれる）。
@Suite("将棋の英語の文言（#2166）")
struct ShogiEnglishTests {

    @Test("駒の名前は英語の呼び名になる")
    func pieceNames() {
        #expect(GameShogi.tr("歩兵", language: .english) == "Pawn")
        #expect(GameShogi.tr("飛車", language: .english) == "Rook")
        #expect(GameShogi.tr("角行", language: .english) == "Bishop")
        #expect(GameShogi.tr("金将", language: .english) == "Gold General")
        #expect(GameShogi.tr("銀将", language: .english) == "Silver General")
        #expect(GameShogi.tr("桂馬", language: .english) == "Knight")
        #expect(GameShogi.tr("香車", language: .english) == "Lance")
        #expect(GameShogi.tr("玉将・王将", language: .english) == "King")
        #expect(GameShogi.tr("龍王（成った飛車）", language: .english) == "Dragon (promoted Rook)")
        #expect(GameShogi.tr("龍馬（成った角行）", language: .english) == "Horse (promoted Bishop)")
        #expect(GameShogi.tr("と金（成った歩兵）", language: .english) == "Tokin (promoted Pawn)")
    }

    @Test("対局の用語")
    func terms() {
        #expect(GameShogi.tr("将棋", language: .english) == "Shogi")
        #expect(GameShogi.tr("王手", language: .english) == "Check")
        #expect(GameShogi.tr("詰み", language: .english) == "Checkmate")
        #expect(GameShogi.tr("成る", language: .english) == "Promote")
        #expect(GameShogi.tr("不成", language: .english) == "Don't promote")
        #expect(GameShogi.tr("投了", language: .english) == "Resignation")
        #expect(GameShogi.tr("千日手", language: .english) == "Repetition (Sennichite)")
        #expect(GameShogi.tr("%lld手", 1, language: .english) == "1 move")
        #expect(GameShogi.tr("%lld手", 12, language: .english) == "12 moves")
    }

    @Test("決着の文言は原文で判定し、表示だけを訳す")
    @MainActor
    func resultText() {
        #expect(ShogiGameModel.localizedResultText("後手の負け（詰み）") == "後手の負け（詰み）")
        #expect(GameShogi.tr("後手の負け（詰み）", language: .english) == "Gote loses (checkmate)")
        #expect(GameShogi.tr("引き分け（千日手）", language: .english) == "Draw (repetition)")
        #expect(GameShogi.tr("あなたの負け（投了）", language: .english) == "You lose (resigned)")
        // 組み立てる 6 通りの原文は、どれも表のキーとして訳を持つ。
        let keys = [
            ShogiGameModel.checkmateResultText(loser: .black),
            ShogiGameModel.checkmateResultText(loser: .white),
            ShogiGameModel.perpetualCheckResultText(loser: .black),
            ShogiGameModel.perpetualCheckResultText(loser: .white),
            ShogiGameModel.drawRepetitionResultText,
            ShogiGameModel.resignationResultText,
        ]
        for key in keys {
            #expect(GameShogi.tr.hasTranslation(key, language: .english), "\(key) に英訳が無い")
            #expect(ShogiGameModel.localizedResultText(key) == key, "日本語では原文のまま出す")
        }
    }

    @Test("読み上げ文は英語では漢字を含まない")
    func accessibilityInEnglish() {
        let label = ShogiAccessibility.squareLabel(
            index: 60,
            piece: Piece(type: .pawn, color: .black),
            isSelected: true, isTarget: false, isLastMove: false,
            language: .english
        )
        #expect(label == "7g, Sente's Pawn, Selected")
        #expect(ShogiAccessibility.handLabel(type: .silver, color: .white, count: 2, isSelected: false,
                                             language: .english)
                == "Gote's captured pieces, Silver ×2")
        // 日本語の既定は従来どおり。
        #expect(ShogiAccessibility.squareName(60, language: .japanese) == "7七")
    }

    @Test("駒の対応表は全駒種と全成り駒を載せている")
    func pieceGuideCoversEveryPiece() {
        let pieces = ShogiPieceGuide.all.flatMap(\.pieces)
        for type in PieceType.allCases {
            #expect(pieces.contains { $0.type == type && !$0.promoted }, "\(type) が対応表に無い")
            if type.canPromote {
                #expect(pieces.contains { $0.type == type && $0.promoted }, "成った \(type) が対応表に無い")
            }
        }
        // 王と玉の両方の字を見せる（先手の玉は「玉」、後手は「王」で描かれる）。
        let kings = Set(pieces.filter { $0.type == .king }.map { Glyph.kanji(for: $0) })
        #expect(kings == ["玉", "王"])
        #expect(Set(ShogiPieceGuide.all.map(\.id)).count == ShogiPieceGuide.all.count, "行の id が重複している")
    }

    @Test("対応表の名前と動きは英語で引ける")
    func pieceGuideInEnglish() {
        // 対応表は表示言語で組むので、ここでは表のキーに英訳があることを確かめる（日本語の行 = キー）。
        for entry in ShogiPieceGuide.all {
            #expect(GameShogi.tr.hasTranslation(entry.name, language: .english), "\(entry.name) に英訳が無い")
            #expect(GameShogi.tr.hasTranslation(entry.movement, language: .english), "\(entry.movement) に英訳が無い")
        }
        #expect(GameShogi.tr("%1$@：%2$@", "Pawn", "One square straight forward", language: .english)
                == "Pawn: One square straight forward")
    }
}
