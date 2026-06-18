import SwiftUI

/// 画面下部のバナー広告枠。広告が無いときも高さを確保してレイアウトを安定させる。
/// body 内で makeBannerView() を毎回呼ぶと同じ GADBannerView が奪われる問題を避けるため、
/// @State でキャッシュし初回表示時に一度だけ生成する。
public struct BannerSlot: View {
    private let ads: AdService
    @State private var banner: AnyView?
    public static let height: CGFloat = 50

    public init(ads: AdService) {
        self.ads = ads
    }

    public var body: some View {
        Group {
            if let b = banner { b } else { Color.clear }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .task {
            if banner == nil { banner = ads.makeBannerView() }
        }
    }
}
