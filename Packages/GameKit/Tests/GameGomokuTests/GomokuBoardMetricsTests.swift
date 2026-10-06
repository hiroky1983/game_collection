import CoreGraphics
import Testing
@testable import GameGomoku

@Suite("五目並べの盤の余白（#1706）")
struct GomokuBoardMetricsTests {
    /// SE 〜 Pro Max（盤の幅 およそ 300〜460pt）で、端の交点の印が描画範囲に収まる。
    @Test func edgeMarksFitInsideBoard() {
        var width: CGFloat = 300
        while width <= 460 {
            let inset = GomokuBoardMetrics.inset(forWidth: width)
            let spacing = (width - inset * 2) / CGFloat(gomokuBoardSize - 1)
            let outer = spacing * GomokuBoardMetrics.stoneRadiusRatio + GomokuBoardMetrics.markOverhang
            #expect(inset - outer >= GomokuBoardMetrics.margin - 0.0001, "width \(width)")
            width += 10
        }
    }

    /// 余白を広げすぎない（#1663 で盤を最大化した成果を削らない）。
    @Test func insetStaysCompact() {
        #expect(GomokuBoardMetrics.inset(forWidth: 375) < 18)
        #expect(GomokuBoardMetrics.inset(forWidth: 460) < 20)
    }
}
