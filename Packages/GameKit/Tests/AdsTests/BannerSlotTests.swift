import Testing
import CoreGraphics
@testable import Core

/// `GADBannerView` のサイズは生成時の幅で固定されるため、枠の幅が変わったら作り直さないと
/// コンテナ幅と広告サイズがずれる（画面回転・Split View。PR #264 の CodeRabbit 指摘）。
/// 一方で毎回作り直すと同じ `GADBannerView` を奪い合うので、幅が変わったときだけ作り直す。
@Suite("バナー枠の生成判断")
struct BannerSlotTests {
    @Test("最初の1回は生成する")
    func createsOnFirstLayout() {
        #expect(BannerSlot.shouldMakeBanner(width: 320, currentWidth: nil))
    }

    @Test("幅が確定していないうちは生成しない")
    func skipsBeforeWidthIsKnown() {
        #expect(!BannerSlot.shouldMakeBanner(width: 0, currentWidth: nil))
        #expect(!BannerSlot.shouldMakeBanner(width: -1, currentWidth: nil))
        // 幅が 0 に戻っても、既に生成済みのバナーを捨てて作り直したりはしない。
        #expect(!BannerSlot.shouldMakeBanner(width: 0, currentWidth: 320))
    }

    @Test("同じ幅で再レイアウトされても作り直さない")
    func keepsBannerWhenWidthIsUnchanged() {
        #expect(!BannerSlot.shouldMakeBanner(width: 320, currentWidth: 320))
    }

    @Test("幅が変わったら作り直す（画面回転・Split View）")
    func recreatesWhenWidthChanges() {
        #expect(BannerSlot.shouldMakeBanner(width: 640, currentWidth: 320))
        #expect(BannerSlot.shouldMakeBanner(width: 320, currentWidth: 640))
    }
}
