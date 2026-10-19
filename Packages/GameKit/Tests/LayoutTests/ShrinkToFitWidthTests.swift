import Testing
import CoreGraphics
@testable import Core

/// 幅に収まらない固定 pt の札の行を縮める倍率（#2496）。
@Suite("札の行の幅合わせ")
struct ShrinkToFitWidthTests {
    @Test("収まるときは縮めない（SE 以外の見た目を変えない）")
    func fitsKeepsOne() {
        #expect(ShrinkToFitMath.scale(natural: 342, available: 342) == 1)
        #expect(ShrinkToFitMath.scale(natural: 342, available: 600) == 1)
    }

    @Test("SE の手札 5 枚（342pt）は 315pt に収まる倍率になる")
    func seFiveCards() {
        let s = ShrinkToFitMath.scale(natural: 342, available: 315)
        #expect(abs(342 * s - 315) < 0.001)
    }

    @Test("iPhone 17 の 6 枚（412pt）は 342pt に収まる")
    func sixCards() {
        let s = ShrinkToFitMath.scale(natural: 412, available: 342)
        #expect(abs(412 * s - 342) < 0.001)
    }

    @Test("未計測・幅 0 の最初のフレームでは縮めない")
    func zeroGuard() {
        #expect(ShrinkToFitMath.scale(natural: 0, available: 315) == 1)
        #expect(ShrinkToFitMath.scale(natural: 342, available: 0) == 1)
    }

    @Test("札の行の理想幅は 62×枚数 + 間隔×(枚数-1)")
    func rowWidth() {
        #expect(PlayingCardMetrics.standard.rowWidth(count: 5, spacing: 8) == 342)
        #expect(PlayingCardMetrics.standard.rowWidth(count: 6, spacing: 8) == 412)
        #expect(PlayingCardMetrics.standard.rowWidth(count: 0, spacing: 8) == 0)
    }
}
