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
        GeometryReader { geo in
            Group {
                if let b = banner { b } else { Color.clear }
            }
            .frame(width: geo.size.width, height: Self.height)
            // 呼び出し元の `.padding()` 等を差し引いた**実際にバナーが置かれる幅**を渡す。
            // 画面全体の幅で広告を要求すると、実表示幅より広いサイズの広告が来て
            // 左右に黒い余白が出ていた（会長指摘）。幅が確定してから一度だけ生成する。
            .task(id: geo.size.width) {
                guard banner == nil, geo.size.width > 0 else { return }
                banner = ads.makeBannerView(width: geo.size.width)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}
