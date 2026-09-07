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
            #expect(layout.hubColumnCount(containerWidth: width) == 2,
                    "幅 \(width)pt で 2 列にならなかった")
        }
    }

    @Test("iPad のハブは 2 列より多く並ぶ")
    func hubGetsMoreColumnsOnPad() {
        for width in Self.iPadWidths {
            let layout = AdaptiveLayout(width: width)
            let columns = layout.hubColumnCount(containerWidth: width)
            #expect(columns > 2, "幅 \(width)pt で \(columns) 列だった")
        }
    }

    /// 130pt のままでは iPad でカードが iPhone より小さくなる、というのが最小幅を上げた理由。
    /// その根拠が崩れていないことを固定する。
    @Test("iPad でカードが iPhone より小さくならない")
    func padCardsAreNotSmallerThanPhone() {
        let phone = AdaptiveLayout(width: 393)
        let phoneCard = cardWidth(containerWidth: 393, layout: phone)
        for width in Self.iPadWidths {
            let layout = AdaptiveLayout(width: width)
            let padCard = cardWidth(containerWidth: width, layout: layout)
            #expect(padCard >= phoneCard, "幅 \(width)pt のカードが \(padCard)pt で iPhone の \(phoneCard)pt を下回った")
        }
    }

    /// 固定 pt の部品（将棋の持ち駒など）は iPhone では 1pt も動かしてはならない。
    @Test("固定 pt の拡大は狭い画面では恒等")
    func elementScaleIsIdentityOnPhone() {
        for width in Self.iPhoneWidths {
            let layout = AdaptiveLayout(width: width)
            #expect(layout.elementScale == 1)
            #expect(layout.scaled(32) == 32)
            #expect(layout.scaled(48) == 48)
        }
    }

    @Test("固定 pt は広い画面でだけ拡大する")
    func elementScaleGrowsOnPad() {
        for width in Self.iPadWidths {
            let layout = AdaptiveLayout(width: width)
            #expect(layout.elementScale > 1)
            #expect(layout.scaled(32) == 48)
        }
    }

    /// 拡大しても最小タップ標的（44pt）を割らないことが、固定 pt を触ってよい前提。
    @Test("拡大後の持ち駒は最小タップ標的を満たす")
    func scaledHandPieceMeetsTapTarget() {
        #expect(AdaptiveLayout(width: 1024).scaled(32) >= 44)
    }

    // MARK: - 縦方向の使い切り（#485）

    /// iPhone のカードは「中身が決める高さ」のままでなければならない。
    /// ここが nil を返さなくなると、`GameCard` に `minHeight` が入って iPhone の見た目が動く。
    @Test("iPhone のハブカードには高さを与えない")
    func hubCardHeightIsUntouchedOnPhone() {
        for width in Self.iPhoneWidths {
            let layout = AdaptiveLayout(width: width)
            #expect(layout.hubCardMinHeight(viewportHeight: 700, rows: 8) == nil,
                    "幅 \(width)pt で高さが与えられた")
        }
    }

    /// #485 の本体。16 本を並べたときに、行の高さで縦を使い切れること。
    @Test("iPad のハブは行の高さで縦を使い切る")
    func hubFillsHeightOnPad() throws {
        let viewport: CGFloat = 1270  // 13 インチ縦のスクロール領域のおよその高さ
        for width in Self.iPadWidths {
            let layout = AdaptiveLayout(width: width)
            let columns = layout.hubColumnCount(containerWidth: width)
            let rows = (16 + columns - 1) / columns
            let height = try #require(layout.hubCardMinHeight(viewportHeight: viewport, rows: rows))
            let used = height * CGFloat(rows) + 12 * CGFloat(rows - 1) + Theme.pad * 2
            #expect(abs(used - viewport) < 0.5,
                    "幅 \(width)pt: \(rows) 行で \(used)pt しか使えていない（容器は \(viewport)pt）")
        }
    }

    /// 高さが測れる前（0）に割り算の結果を渡すと、カードが潰れる。
    @Test("高さが測れていないうちは高さを与えない")
    func hubCardHeightNeedsMeasuredViewport() {
        let layout = AdaptiveLayout(width: 1032)
        #expect(layout.hubCardMinHeight(viewportHeight: 0, rows: 4) == nil)
        #expect(layout.hubCardMinHeight(viewportHeight: 1270, rows: 0) == nil)
    }

    // MARK: - LazyVGrid の列数の再現

    /// 列数が決まればカード 1 枚の幅も決まる（`.flexible()` は等幅）。
    private func cardWidth(containerWidth: CGFloat, layout: AdaptiveLayout) -> CGFloat {
        let spacing: CGFloat = 12
        let n = CGFloat(layout.hubColumnCount(containerWidth: containerWidth))
        let available = containerWidth - Theme.pad * 2
        return (available - (n - 1) * spacing) / n
    }
}
