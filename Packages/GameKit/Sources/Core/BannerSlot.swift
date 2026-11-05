import SwiftUI

/// 画面下部のバナー広告枠。広告が無いときも高さを確保してレイアウトを安定させる。
/// body 内で makeBannerView() を毎回呼ぶと同じ GADBannerView が奪われる問題を避けるため、
/// @State でキャッシュし初回表示時に一度だけ生成する。
public struct BannerSlot: View {
    private let ads: AdService
    @State private var banner: AnyView?
    /// `banner` を生成したときの幅。幅が変わったら作り直す判断に使う。
    @State private var bannerWidth: CGFloat?
    public static let height: CGFloat = 50

    /// バナーに要求する幅の上限（pt）。
    ///
    /// アダプティブバナーの**高さは要求した幅で決まる**。枠の高さは上の `height`（50pt）で
    /// 固定してあるため、iPad の 1024pt をそのまま渡すと SDK が 50pt より背の高い広告を返し、
    /// 枠から溢れて切れる（#458）。440pt は現行 iPhone の最大幅（16 Pro Max）で、
    /// **いま実際に 50pt で表示できている実績のある値**なのでここを上限に取る。
    /// iPad では iPhone と同じ大きさのバナーが中央に置かれるだけになり、
    /// 広告フォーマットは変わらない（引き伸ばさない = #458 の受け入れ条件）。
    public static let maxWidth: CGFloat = 440

    public init(ads: AdService) {
        self.ads = ads
    }

    /// 枠の幅から、バナーに要求する幅を決める。
    static func bannerWidth(containerWidth: CGFloat) -> CGFloat {
        min(containerWidth, maxWidth)
    }

    /// バナーを（作り直しも含めて）生成すべきか。
    ///
    /// `GADBannerView` のサイズは生成時の幅で固定されるため、画面回転や Split View で枠の幅が
    /// 変わっても作り直さないと、コンテナ幅と広告サイズがずれる（CodeRabbit 指摘・PR #264）。
    /// 一方で body のたびに作り直すと同じ `GADBannerView` を奪い合うので、
    /// **幅が変わったときだけ**作り直す。
    static func shouldMakeBanner(width: CGFloat, currentWidth: CGFloat?) -> Bool {
        guard width > 0 else { return false }
        return currentWidth != width
    }

    public var body: some View {
        GeometryReader { geo in
            Group {
                if let b = banner { b } else { Color.clear }
            }
            .frame(width: Self.bannerWidth(containerWidth: geo.size.width), height: Self.height)
            // 枠より狭いバナー（iPad）は中央に置く。
            .frame(width: geo.size.width, height: Self.height)
            // 呼び出し元の `.padding()` 等を差し引いた**実際にバナーが置かれる幅**を渡す。
            // 画面全体の幅で広告を要求すると、実表示幅より広いサイズの広告が来て
            // 左右に黒い余白が出ていた（会長指摘）。
            .task(id: geo.size.width) {
                let width = Self.bannerWidth(containerWidth: geo.size.width)
                guard Self.shouldMakeBanner(width: width, currentWidth: bannerWidth) else { return }
                bannerWidth = width
                banner = ads.makeBannerView(width: width)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .anchorPreference(key: BannerFrameKey.self, value: .bounds) { $0 }
    }
}

/// 画面の中の `BannerSlot` の枠。幕を重ねる側（`overlayAboveBanner`）がバナーを避けるために読む（#3247）。
struct BannerFrameKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// 幕を置いてよい縦の範囲の決め方（View から切り離してテストできるようにする）。
public enum BannerAvoidance {
    /// 幕を置く縦の範囲（上端と高さ）。バナーが上半分にあれば（打席の上端）その下から、下半分にあれば
    /// （ほぼ全ゲーム）その上端まで。バナーが無ければ全体。
    public static func region(containerHeight: CGFloat, banner: CGRect?) -> (top: CGFloat, height: CGFloat) {
        guard let banner else { return (0, containerHeight) }
        if banner.midY < containerHeight / 2 {
            let top = min(max(0, banner.maxY), containerHeight)
            return (top, containerHeight - top)
        }
        return (0, min(max(0, banner.minY), containerHeight))
    }
}

public extension View {
    /// 暗幕・結果カードなど画面いっぱいの重ねを、中の `BannerSlot` を**覆わない範囲**にだけ重ねる（#3247）。
    ///
    /// バナーが幕の裏に回ると、表示されているのに見えていない扱い（ビューアブルでない）になり、広告の単価が下がる
    /// うえ、AdMob のポリシー（Content obscuring）にも当たる。バナーは常に見えて押せる状態のまま残す。
    /// 幕が出ているあいだ、バナーが画面に無ければ（`BannerSlot` が無い）全体に重ねる。
    ///
    /// この修飾子は `BannerSlot` を含む View の**外側**に付ける（プリファレンスは子から親へ流れる）。
    /// 全画面の枠（`gameChrome(fullScreen:ads:)`）のバナーは枠の中にあるので、枠より後ろに付けてもよい。
    func overlayAboveBanner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let overlay = content()
        return overlayPreferenceValue(BannerFrameKey.self) { anchor in
            GeometryReader { proxy in
                let region = BannerAvoidance.region(containerHeight: proxy.size.height,
                                                    banner: anchor.map { proxy[$0] })
                overlay
                    .frame(width: proxy.size.width, height: region.height)
                    .offset(y: region.top)
            }
        }
    }
}
