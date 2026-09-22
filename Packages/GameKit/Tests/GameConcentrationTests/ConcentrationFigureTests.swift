import Foundation
import Testing
import Core
@testable import GameConcentration

/// 絵柄の定義（#601 → #1244）。抽象図形を具体物カード（`ObjectCardKind`）に替えたことと、
/// 旧版の中断データが読み替えられることを、定義の側から固定する。
@Suite("神経衰弱: 絵柄の定義（#601・#1244）")
struct ConcentrationFigureDefinitionTests {

    /// 盤で使われるのは最大 18 種（18 ペア）。図案がこれを下回ると盤を組めない。
    @Test("図案は最大の盤（18ペア）を賄える数だけある")
    func figureCountCoversLargestBoard() {
        #expect(ConcentrationFigure.allCases.count >= ConcentrationPairCount.large.rawValue)
    }

    @Test("識別子・読み上げ文が重複しない")
    func figureAttributesAreUnique() {
        let all = ConcentrationFigure.allCases
        #expect(Set(all.map(\.rawValue)).count == all.count, "識別子が重複している")
        #expect(Set(all.map(\.displayName)).count == all.count, "読み上げ文が重複している")
    }

    /// 中断データに書く識別子に絵文字が混ざっていたら、OS 依存を持ち込んだまま名前だけ変えたことになる。
    @Test("識別子は ASCII だけで書かれている")
    func rawValuesAreASCII() {
        for figure in ConcentrationFigure.allCases {
            let isPlainASCII = figure.rawValue.allSatisfy { $0.isASCII && $0.isLetter }
            #expect(isPlainASCII,
                    "\(figure) の識別子 '\(figure.rawValue)' に ASCII の英字以外が入っている")
        }
    }

    @Test("盤に使う先頭 18 種は絵が描かれている")
    func boardFiguresHaveArt() {
        for figure in ConcentrationFigure.allCases.prefix(ConcentrationPairCount.large.rawValue) {
            #expect(figure.cgImage != nil, "\(figure) のドット絵が作れない")
        }
    }

    @Test("現行の識別子は現行の図案へ読み替えられる")
    func currentRawValueDecodesToItself() {
        for figure in ConcentrationFigure.allCases {
            #expect(ConcentrationFigure.decode(figure.rawValue) == figure)
        }
    }

    /// 旧版（図形・絵文字）の中断データが、1 対 1 で新しいカードへ移ること。
    /// 1 対 1 でないと、対だった 2 枚が別の絵になって盤が崩れる。
    @Test("旧版の図形の識別子・絵文字は、どちらも同じ新カードへ 1 対 1 で読み替えられる")
    func legacySymbolsDecodeOneToOne() {
        var seen = Set<String>()
        for legacy in LegacyConcentrationFigure.allCases {
            let byIdentifier = ConcentrationFigure.decode(legacy.identifier)
            let byEmoji = ConcentrationFigure.decode(legacy.emoji)
            #expect(byIdentifier != nil, "\(legacy.identifier) が読み替えられない")
            #expect(byIdentifier == byEmoji, "\(legacy.identifier) の識別子と絵文字で行き先が違う")
            if let kind = byIdentifier { seen.insert(kind.rawValue) }
        }
        #expect(seen.count == LegacyConcentrationFigure.allCases.count, "旧 18 種が別々の新カードに移っていない")
    }

    /// 旧識別子が現行の識別子と同じ綴りだと、読み替えのつもりが現行の図案に吸われる。
    @Test("旧版の識別子は現行の識別子と重ならない")
    func legacyIdentifiersDoNotCollideWithCurrent() {
        let current = Set(ConcentrationFigure.allCases.map(\.rawValue))
        for legacy in LegacyConcentrationFigure.allCases {
            #expect(!current.contains(legacy.identifier), "\(legacy.identifier) が現行の識別子と重なる")
        }
    }

    @Test("知らない文字列は読み替えない")
    func unknownSymbolDoesNotDecode() {
        #expect(ConcentrationFigure.decode("s0") == nil)
        #expect(ConcentrationFigure.decode("") == nil)
        #expect(ConcentrationFigure.decode("🍕") == nil)   // 旧版でも盤には出てこない絵文字
    }
}

extension LegacyConcentrationFigure {
    /// 新カードに対応する旧版の絵文字（テストが旧版の中断データを作るのに使う）。
    static func emoji(ofReplacement rawValue: String) -> String {
        allCases.first { $0.replacement.rawValue == rawValue }!.emoji
    }
}
