import Testing
import Core
import GameKitTestSupport
@testable import GameColorRelay

/// 札の色の読みやすさ（#2007）。窓の数字・四隅の印を載せる文字色 `Theme.onAccent` が、
/// 札の面と白い窓の両方に対して AA（4.5:1）に届くことを固定する。
@Suite struct ColorRelayContrastTests {
    @Test func textOnEveryCardFaceMeetsAA() {
        for color in RelayColor.allCases {
            #expect(WCAG.contrast(Theme.Hex.onAccent, color.faceHex) >= 4.5, "\(color.name) の面")
        }
    }

    @Test func glyphOnWhiteWindowMeetsAA() {
        #expect(WCAG.contrast(Theme.Hex.onAccent, 0xFFFFFF) >= 4.5)
    }

    /// #2369: 窓の大きな数字は地の色の系統で描く。大きな文字（太字 24pt 以上）の基準 3:1 を白い窓に対して満たす。
    @Test func colorGlyphOnWhiteWindowMeetsLargeTextAA() {
        for color in RelayColor.allCases {
            #expect(WCAG.contrast(color.glyphHex, 0xFFFFFF) >= 3, "\(color.name) の窓の数字")
        }
        // 窓の数字は手札で最も小さい札（50pt 幅）でも 31pt あり、大きな文字に当たる。
        #expect(ColorRelayHandLayout.compactHandCardWidth * 0.62 >= 24)
    }

    @Test func initialsAreDistinct() {
        let initials = RelayColor.allCases.map(\.initial)
        #expect(Set(initials).count == RelayColor.allCases.count)
    }
}
