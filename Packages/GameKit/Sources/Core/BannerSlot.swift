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

    public init(ads: AdService) {
        self.ads = ads
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
            .frame(width: geo.size.width, height: Self.height)
            // 呼び出し元の `.padding()` 等を差し引いた**実際にバナーが置かれる幅**を渡す。
            // 画面全体の幅で広告を要求すると、実表示幅より広いサイズの広告が来て
            // 左右に黒い余白が出ていた（会長指摘）。
            .task(id: geo.size.width) {
                let width = geo.size.width
                guard Self.shouldMakeBanner(width: width, currentWidth: bannerWidth) else { return }
                bannerWidth = width
                banner = ads.makeBannerView(width: width)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}
