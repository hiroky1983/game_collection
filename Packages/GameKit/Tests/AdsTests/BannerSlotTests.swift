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

    /// アダプティブバナーの高さは要求した幅で決まる。枠は 50pt 固定なので、iPad の幅を
    /// そのまま渡すと背の高い広告が返って枠から切れる（#458）。
    @Test("iPhone の幅までは枠いっぱいに広げる")
    func usesFullWidthOnPhone() {
        for width: CGFloat in [320, 375, 393, 430, 440] {
            #expect(BannerSlot.bannerWidth(containerWidth: width) == width)
        }
    }

    @Test("iPad の幅では要求幅を頭打ちにする")
    func capsWidthOnPad() {
        for width: CGFloat in [744, 820, 1024, 1366] {
            #expect(BannerSlot.bannerWidth(containerWidth: width) == BannerSlot.maxWidth)
        }
    }

    /// 上限は「50pt の枠に収まる実績のある幅」であることが根拠なので、現行 iPhone の
    /// 最大幅を超えて広げてはならない。
    @Test("上限は現行 iPhone の最大幅を超えない")
    func capMatchesLargestPhoneWidth() {
        #expect(BannerSlot.maxWidth == 440)
    }

    @Test("頭打ちになった幅では枠が広がっても作り直さない")
    func keepsBannerWhenOnlyContainerGrows() {
        let first = BannerSlot.bannerWidth(containerWidth: 1024)
        let second = BannerSlot.bannerWidth(containerWidth: 1366)
        #expect(!BannerSlot.shouldMakeBanner(width: second, currentWidth: first))
    }
}
