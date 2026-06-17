import SwiftUI

/// 画面下部のバナー広告枠。広告が無いときも高さを確保してレイアウトを安定させる。
/// MVP は `NoopAdService` なので何も出ないが枠は確保される（M5 で AdMob 実装に差し替え）。
public struct BannerSlot: View {
    private let ads: AdService
    public static let height: CGFloat = 50

    public init(ads: AdService) {
        self.ads = ads
    }

    public var body: some View {
        Group {
            if let banner = ads.makeBannerView() {
                banner
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}
