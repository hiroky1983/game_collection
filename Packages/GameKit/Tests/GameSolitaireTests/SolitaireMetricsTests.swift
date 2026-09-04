import Testing
import CoreGraphics
@testable import GameSolitaire

/// iPad 対応（#458）。上段（山札・捨て札・組札）は `Spacer` で左右いっぱいに広がるのに対し、
/// 下段の 7 列は札の幅の上限で頭打ちになる。広い画面では両方を同じ幅に揃えないと
/// 組札と 7 列目が縦に揃わない。
@Suite("ソリティアの盤面幅（iPad 対応）")
struct SolitaireBoardWidthTests {

    typealias Metrics = SolitaireMetrics

    /// 画面幅から `Theme.pad`（16pt）を左右に引いた、盤に使える幅。
    private static func contentWidth(screenWidth: CGFloat) -> CGFloat { screenWidth - 16 * 2 }

    @Test("上限に掛からない画面では盤面幅は使える幅と一致する（＝見た目が変わらない）")
    func matchesAvailableWidthOnPhone() {
        for screen: CGFloat in [320, 375, 393, 402, 430, 440] {
            let available = Self.contentWidth(screenWidth: screen)
            let card = Metrics.cardWidth(availableWidth: available)
            #expect(abs(Metrics.boardWidth(cardWidth: card) - available) < 0.001,
                    "画面幅 \(screen)pt で盤面幅が使える幅とずれた")
        }
    }

    @Test("iPad では盤面幅が使える幅より狭くなる（＝中央に寄せる必要がある）")
    func boardIsNarrowerThanScreenOnPad() {
        for screen: CGFloat in [744, 834, 1024, 1032] {
            let available = Self.contentWidth(screenWidth: screen)
            let card = Metrics.cardWidth(availableWidth: available)
            #expect(Metrics.boardWidth(cardWidth: card) < available)
        }
    }

    @Test("上限を引き上げると札も盤面も大きくなる")
    func raisingTheCapGrowsTheBoard() {
        let available = Self.contentWidth(screenWidth: 1024)
        let base = Metrics.cardWidth(availableWidth: available)
        let scaled = Metrics.cardWidth(availableWidth: available, maxWidth: Metrics.maxCardWidth * 1.5)
        #expect(base == Metrics.maxCardWidth)
        #expect(scaled == Metrics.maxCardWidth * 1.5)
        #expect(Metrics.boardWidth(cardWidth: scaled) > Metrics.boardWidth(cardWidth: base))
        // 引き上げても画面には収まる（はみ出したら 7 列目が切れる）。
        #expect(Metrics.boardWidth(cardWidth: scaled) <= available)
    }

    @Test("上限の引き上げは狭い画面には効かない")
    func raisingTheCapDoesNotAffectPhones() {
        for screen: CGFloat in [320, 375, 393, 430, 440] {
            let available = Self.contentWidth(screenWidth: screen)
            #expect(Metrics.cardWidth(availableWidth: available)
                    == Metrics.cardWidth(availableWidth: available, maxWidth: Metrics.maxCardWidth * 1.5))
        }
    }
}
