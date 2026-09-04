import Testing
import CoreGraphics
@testable import Core

/// iPad 対応（#458）の適応レイヤ。判定と数値をこの 1 か所に集約しているので、
/// 各画面のレイアウトが正しいかどうかはここの値がすべての起点になる。
@Suite("画面の広さに応じた適応レイヤ")
struct AdaptiveLayoutTests {
    /// 実機の幅（pt・縦向き）。境目がこの並びのどちら側に来るかがこの型の仕様そのもの。
    private static let iPhoneWidths: [CGFloat] = [320, 375, 390, 393, 428, 430, 440]
    private static let iPadWidths: [CGFloat] = [744, 768, 820, 834, 1024, 1032]

    @Test("iPhone の幅はすべて狭いほうに入る")
    func iPhoneIsNarrow() {
        for width in Self.iPhoneWidths {
            #expect(!AdaptiveLayout(width: width).isWide, "幅 \(width)pt が広いと判定された")
        }
    }

    @Test("iPad の幅はすべて広いほうに入る")
    func iPadIsWide() {
        for width in Self.iPadWidths {
            #expect(AdaptiveLayout(width: width).isWide, "幅 \(width)pt が狭いと判定された")
        }
    }

    @Test("幅が測れていないうちは狭いほうに倒す")
    func unknownWidthFallsBackToNarrow() {
        #expect(!AdaptiveLayout(width: 0).isWide)
    }

    /// #119 の「iPhone は必ず 2 列」は iPad 対応で壊してはならない不変条件。
    @Test("iPhone のハブは従来どおり 2 列のまま")
    func hubStaysTwoColumnsOnPhone() {
        for width in Self.iPhoneWidths {
            let layout = AdaptiveLayout(width: width)
            #expect(layout.hubCardMinWidth == 130)
            #expect(columnCount(containerWidth: width, minimum: layout.hubCardMinWidth) == 2,
                    "幅 \(width)pt で 2 列にならなかった")
        }
    }

    @Test("iPad のハブは 2 列より多く並ぶ")
    func hubGetsMoreColumnsOnPad() {
        for width in Self.iPadWidths {
            let layout = AdaptiveLayout(width: width)
            let columns = columnCount(containerWidth: width, minimum: layout.hubCardMinWidth)
            #expect(columns > 2, "幅 \(width)pt で \(columns) 列だった")
        }
    }

    /// 130pt のままでは iPad でカードが iPhone より小さくなる、というのが最小幅を上げた理由。
    /// その根拠が崩れていないことを固定する。
    @Test("iPad でカードが iPhone より小さくならない")
    func padCardsAreNotSmallerThanPhone() {
        let phone = AdaptiveLayout(width: 393)
        let phoneCard = cardWidth(containerWidth: 393, minimum: phone.hubCardMinWidth)
        for width in Self.iPadWidths {
            let layout = AdaptiveLayout(width: width)
            let padCard = cardWidth(containerWidth: width, minimum: layout.hubCardMinWidth)
            #expect(padCard >= phoneCard, "幅 \(width)pt のカードが \(padCard)pt で iPhone の \(phoneCard)pt を下回った")
        }
    }

    // MARK: - LazyVGrid の列数の再現

    /// `GridItem(.adaptive(minimum:))` の列決定。`padding` と `spacing` は HubView の値。
    private func columnCount(containerWidth: CGFloat, minimum: CGFloat) -> Int {
        let spacing: CGFloat = 12
        let available = containerWidth - Theme.pad * 2
        // n 列が入る条件: n * minimum + (n - 1) * spacing <= available
        var n = 1
        while (CGFloat(n + 1) * minimum + CGFloat(n) * spacing) <= available { n += 1 }
        return n
    }

    private func cardWidth(containerWidth: CGFloat, minimum: CGFloat) -> CGFloat {
        let spacing: CGFloat = 12
        let n = CGFloat(columnCount(containerWidth: containerWidth, minimum: minimum))
        let available = containerWidth - Theme.pad * 2
        return (available - (n - 1) * spacing) / n
    }
}
