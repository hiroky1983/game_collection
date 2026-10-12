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

    @Test func initialsAreDistinct() {
        let initials = RelayColor.allCases.map(\.initial)
        #expect(Set(initials).count == RelayColor.allCases.count)
    }
}
