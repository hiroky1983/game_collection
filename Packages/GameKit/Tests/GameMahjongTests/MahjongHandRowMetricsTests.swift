import Testing
import Foundation
import CoreGraphics
import Core
@testable import GameMahjong

/// 卓の下の手牌の行の寸法（#715）。iPad で自分の手牌が CPU の捨て牌より小さくならないこと、
/// iPhone では 1pt も動かないことを縛る。
@Suite("麻雀の手牌の行の寸法")
struct MahjongHandRowMetricsTests {
    /// iPhone SE（320）〜 16 Pro Max（440）と、境目のすぐ下。
    static let narrowWidths: [CGFloat] = [0, 320, 375, 393, 402, 440, 699.5]
    /// iPad mini（744）〜 13 インチ（1032）と、境目ちょうど・横幅の最大。
    static let wideWidths: [CGFloat] = [700, 744, 768, 810, 820, 834, 1024, 1032, 1366]

    @Test("幅 700pt 未満では変更前の固定値（34×46・間隔 3・隙間 8）と完全に一致する", arguments: narrowWidths)
    func narrowKeepsPhoneValues(width: CGFloat) {
        let m = MahjongHandRowMetrics.make(layout: AdaptiveLayout(width: width))
        #expect(m.tileWidth == 34)
        #expect(m.tileHeight == 46)
        #expect(m.spacing == 3)
        #expect(m.drawnGap == 8)
    }

    @Test("幅 700pt 以上では手牌 1 枚の幅が、卓が取りうる最大の一辺での河の牌の幅以上", arguments: wideWidths)
    func wideHandIsNotSmallerThanDiscard(width: CGFloat) {
        let m = MahjongHandRowMetrics.make(layout: AdaptiveLayout(width: width))
        let tableWidth = width - Theme.pad * 2
        // 卓は高さで頭打ちになると一辺が縮むが、河の牌も一緒に縮むので、最大の一辺で比べれば足りる
        for side in [tableWidth, tableWidth * 0.8, tableWidth * 0.6] {
            let layout = MahjongTableLayout(size: CGSize(width: side, height: side))
            #expect(m.tileWidth >= layout.riverTileWidth, "幅 \(width) 卓 \(side): 手牌 \(m.tileWidth) < 河 \(layout.riverTileWidth)")
            // 実際に河に描かれる牌（縮尺込み）でも確かめる
            for seat in 0..<4 {
                for index in [0, 5, 6, 17] {
                    let slot = layout.riverSlot(seat: seat, index: index)
                    #expect(m.tileWidth >= layout.riverTileWidth * slot.scale)
                }
            }
        }
        // iPhone より大きくなっている（据え置きの退行を拾う）
        #expect(m.tileWidth > MahjongHandRowMetrics.phone.tileWidth)
    }

    @Test("幅 700pt 以上では手牌 14 枚が横 1 行で卓の幅に収まる", arguments: wideWidths)
    func wideRowFitsInTable(width: CGFloat) {
        let m = MahjongHandRowMetrics.make(layout: AdaptiveLayout(width: width))
        let tableWidth = width - Theme.pad * 2
        #expect(m.rowContentWidth + MahjongHandRowMetrics.horizontalInsets <= tableWidth + 0.001)
    }

    @Test("広げても牌の縦横比と間隔の比は変わらない（相似拡大）", arguments: wideWidths)
    func wideIsSimilarScaling(width: CGFloat) {
        let m = MahjongHandRowMetrics.make(layout: AdaptiveLayout(width: width))
        let factor = m.tileWidth / MahjongHandRowMetrics.phone.tileWidth
        #expect(abs(m.tileHeight - 46 * factor) < 0.001)
        #expect(abs(m.spacing - 3 * factor) < 0.001)
        #expect(abs(m.drawnGap - 8 * factor) < 0.001)
    }
}
