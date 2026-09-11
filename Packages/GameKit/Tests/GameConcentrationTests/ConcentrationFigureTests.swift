import CoreGraphics
import Foundation
import Testing
@testable import GameConcentration

/// 絵柄の定義（#601）。絵文字をやめて自前の図案に替えたことを、定義の側から固定する。
@Suite("神経衰弱: 絵柄の定義（#601）")
struct ConcentrationFigureDefinitionTests {

    /// 盤で使われるのは最大 18 種（18 ペア）。図案がこれを下回ると盤を組めない。
    @Test("図案は最大の盤（18ペア）を賄える数だけある")
    func figureCountCoversLargestBoard() {
        #expect(ConcentrationFigure.allCases.count >= ConcentrationPairCount.large.rawValue)
    }

    @Test("識別子・読み上げ文・色・旧版の絵文字がどれも重複しない")
    func figureAttributesAreUnique() {
        let all = ConcentrationFigure.allCases
        #expect(Set(all.map(\.rawValue)).count == all.count, "識別子が重複している")
        #expect(Set(all.map(\.displayName)).count == all.count, "読み上げ文が重複している")
        #expect(Set(all.map(\.legacyEmoji)).count == all.count, "旧版の絵文字が重複している")
        #expect(Set(all.map { String(describing: $0.color) }).count == all.count, "色が重複している")
    }

    /// 中断データに書く識別子に絵文字が混ざっていたら、OS 依存を持ち込んだまま名前だけ
    /// 変えたことになる（旧版の絵文字は `legacyEmoji` だけが持つ）。
    @Test("識別子は ASCII だけで書かれている")
    func rawValuesAreASCII() {
        for figure in ConcentrationFigure.allCases {
            let isPlainASCII = figure.rawValue.allSatisfy { $0.isASCII && $0.isLetter }
            #expect(isPlainASCII,
                    "\(figure) の識別子 '\(figure.rawValue)' に ASCII の英字以外が入っている")
        }
    }

    @Test("旧版の絵文字は現行の図案へ読み替えられる")
    func legacyEmojiDecodesToItsFigure() {
        for figure in ConcentrationFigure.allCases {
            #expect(ConcentrationFigure.decode(figure.legacyEmoji) == figure)
            #expect(ConcentrationFigure.decode(figure.rawValue) == figure)
        }
    }

    @Test("知らない文字列は読み替えない")
    func unknownSymbolDoesNotDecode() {
        #expect(ConcentrationFigure.decode("s0") == nil)
        #expect(ConcentrationFigure.decode("") == nil)
        #expect(ConcentrationFigure.decode("🍕") == nil)   // 旧版でも盤には出てこない絵文字
    }
}

/// 図案の形。描画そのものは目で見るしかないが、「部品が空」「枠からはみ出す」
/// 「2種類が同じ形になっている」は形の式から機械的に分かる。
@Suite("神経衰弱: 図案の形（#601）")
struct ConcentrationFigureArtTests {

    private static let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    /// 制御点まで含めた外接矩形で見るため、少しだけ外側を許す。
    private static let slack: CGFloat = 12

    @Test("どの図案も部品を持ち、中身が空でない")
    func everyFigureHasNonEmptyParts() {
        for figure in ConcentrationFigure.allCases {
            let parts = ConcentrationFigureArt.parts(of: figure, in: Self.box)
            #expect(!parts.isEmpty, "\(figure) に部品が無い")
            for (i, part) in parts.enumerated() {
                #expect(!part.path.isEmpty, "\(figure) の部品 \(i) が空")
            }
        }
    }

    @Test("どの図案も枠からはみ出さない")
    func everyFigureStaysInsideItsBox() {
        let limit = Self.box.insetBy(dx: -Self.slack, dy: -Self.slack)
        for figure in ConcentrationFigure.allCases {
            for (i, part) in ConcentrationFigureArt.parts(of: figure, in: Self.box).enumerated() {
                let bounds = part.path.boundingRect
                #expect(limit.contains(bounds),
                        "\(figure) の部品 \(i) が枠からはみ出している: \(bounds)")
            }
        }
    }

    /// 小さく描いたときに読めなくならないよう、どの図案も枠の過半を使う。
    @Test("どの図案も枠の過半を使う")
    func everyFigureFillsMostOfItsBox() {
        for figure in ConcentrationFigure.allCases {
            let bounds = ConcentrationFigureArt.parts(of: figure, in: Self.box)
                .map(\.path.boundingRect)
                .reduce(CGRect.null) { $0.union($1) }
            #expect(bounds.width >= Self.box.width * 0.5,
                    "\(figure) の横幅が \(bounds.width) しかない")
            #expect(bounds.height >= Self.box.height * 0.5,
                    "\(figure) の高さが \(bounds.height) しかない")
        }
    }

    /// 同じ形が2種類あると、色でしか見分けられない札の組ができる。
    @Test("同じ形の図案が2つ無い")
    func noTwoFiguresShareTheSameShape() {
        var seen: [String: ConcentrationFigure] = [:]
        for figure in ConcentrationFigure.allCases {
            var shape = ""
            for part in ConcentrationFigureArt.parts(of: figure, in: Self.box) {
                let width: String = part.strokeWidth == nil ? "fill" : "\(part.strokeWidth!)"
                shape += part.path.description + "|" + width + "/"
            }
            if let other = seen[shape] {
                Issue.record("\(figure) と \(other) の形が同じ")
            }
            seen[shape] = figure
        }
    }
}
