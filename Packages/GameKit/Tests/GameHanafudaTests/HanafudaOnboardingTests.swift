import Testing
import SwiftUI
import Core
import GameKitTestSupport
@testable import GameHanafuda

/// 図で見る「はじめての遊び方」（#2827）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("花札: はじめての遊び方")
struct HanafudaOnboardingTests {
    private let options = HanafudaOptions()

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(HanafudaOnboarding.guide.isWellFormed)
        #expect(HanafudaOnboarding.guide.gameID == HanafudaModel.gameID)
    }

    @Test("図に並べた役の札は、本当にその役になり、文数が表示と一致する")
    func yakuFigureMatchesScoring() {
        for sample in HanafudaOnboarding.sampleYaku {
            let cards = sample.cardIDs.map(HanafudaCard.init(id:))
            let hits = HanafudaScoring.yaku(for: cards, options: options)
            #expect(hits.map(\.yaku) == [sample.yaku], "\(sample.yaku): 札の並びが役の成立条件と合わない")
            #expect(hits.first?.points == sample.yaku.basePoints)
            // 文言は 3 つの役を同じ文数として書いている。
            #expect(sample.yaku.basePoints == HanafudaYaku.inoshikacho.basePoints)
        }
    }

    @Test("図に並べた札の種類が、札の表のとおり")
    func kindsFigureMatchesCards() {
        for sample in HanafudaOnboarding.sampleKinds {
            #expect(HanafudaCard(id: sample.cardID).kind == sample.kind)
        }
        #expect(Set(HanafudaOnboarding.sampleKinds.map(\.kind)) == Set(HanafudaKind.allCases))
    }

    @Test("文言の数字（48 枚・7 文で 2 倍・こいこい返しで 2 倍）が実装の値と同じ")
    func textsMatchRules() {
        let all = HanafudaOnboarding.guide.pages.flatMap(\.lines).joined(separator: "\n")
        #expect(HanafudaCard.deckSize == 48)
        #expect(all.contains("全部で 48 枚"))
        #expect(HanafudaScoring.sevenMonThreshold == 7)
        #expect(all.contains("\(HanafudaScoring.sevenMonThreshold) 文以上"))
        // 7 文以上は 2 倍・相手がこいこいを宣言したあとにあがると 2 倍（重なると 4 倍）。
        #expect(HanafudaScoring.finalScore(base: 7, opponentDeclaredKoiKoi: false) == 14)
        #expect(HanafudaScoring.finalScore(base: 5, opponentDeclaredKoiKoi: true) == 10)
        #expect(HanafudaScoring.finalScore(base: 5, opponentDeclaredKoiKoi: false) == 5)
    }

    /// ページ送りで画面が固まってクラッシュした不具合（#2905）の再発防止。原因は札の図
    /// （`HanafudaCardFace`）が幅の分かっている所でも内部で `GeometryReader` を使っていたこと
    /// （`TabView` の「はじめての遊び方」でページをめくるたびに札を何枚も再計測するのが重かった）。
    /// `ImageRenderer` は固まりそのものは検知できないが、全ページの図を実際に描いて、取り落としや
    /// クラッシュが無いことと、札に明示した幅がそのまま絵の幅に出ることを確かめる。
    @Test("全ページの図が描ける")
    func allPagesRender() throws {
        for (index, page) in HanafudaOnboarding.guide.pages.enumerated() {
            let renderer = ImageRenderer(content: page.figure().fixedSize())
            renderer.scale = 1
            _ = try #require(renderer.cgImage, "\(index + 1) 枚目（\(page.heading)）の図が描けない")
        }
    }

    /// `fixedWidth` を渡すと `GeometryReader` を経由せず、指定した幅どおりに描く（#2905）。
    @Test("fixedWidth を渡した札は、その幅そのままで描ける")
    func fixedWidthCardRendersAtGivenWidth() throws {
        let width: CGFloat = 60
        let face = HanafudaCardFace(card: HanafudaCard(id: 0), fixedWidth: width)
        let renderer = ImageRenderer(content: face)
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "fixedWidth 指定の札が描けない")
        #expect(CGFloat(image.width) == width)
        #expect(abs(CGFloat(image.height) - width * HanafudaCardArt.aspectRatio) < 0.5)
    }

    /// build 54・iOS 27 の実機で、ページ送りの途中に主スレッドが `Canvas` の `draw(Text)`（和文の代替フォント探し）で
    /// 10 秒埋まり、監視（0x8BADF00D）に落とされた（#2905）。札の帯の文字は `Canvas` で組まず `Text` で置く。
    @Test("札の帯の文字は Canvas で描かない（ページ送りで固まらない）")
    func cardBandDoesNotDrawTextInCanvas() throws {
        let code = try SourceScan.packageSource("Sources/GameHanafuda/HanafudaCardFace.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!code.contains("Canvas"), "札 1 枚の中で Canvas を使っている")
        #expect(!code.contains(".draw(text"), "札の帯の文字を GraphicsContext に描いている")
        #expect(code.contains("Text(verbatim: card.kind.badgeLabel)"))
    }

    @Test("帯の文字は帯の高さに収まり、月と種別が札の幅に並ぶ")
    func bandLabelFitsTheBand() {
        for width: CGFloat in [26, 40, 44, 60, 130] {
            let bandHeight = width * HanafudaCardArt.aspectRatio * HanafudaCardFace.bandRatio
            let size = HanafudaCardFace.bandFontSize(width: width, bandHeight: bandHeight)
            #expect(size <= bandHeight)
            // 一番長い組み合わせ（2 桁の月＋2 文字の種別）でも、左右の余白込みで幅に収まる
            // （数字は字幅 0.6 em、かなは 1 em で見積もる）。
            let longest = size * 0.6 * 2 + size * 2 + width * 0.1
            #expect(longest <= width, "幅 \(width) の札で帯の文字があふれる")
        }
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        // 数を埋め込む行は、表のキー（書式）の形で確かめる。
        let key = "猪鹿蝶・赤短・三光は、どれも %lld 文です。"
        #expect(tr.hasTranslation(key, language: .english))
        for text in HanafudaOnboarding.guide.texts where text != tr(key, HanafudaYaku.inoshikacho.basePoints) {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
