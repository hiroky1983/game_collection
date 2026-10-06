import SwiftUI

/// ページの中に置く大きめの広告枠（300×250 のミディアムレクタングル）。
/// 読み込み前・広告が無いときも 300×250 を確保して、レイアウトが跳ねないようにする。
/// `BannerSlot` と同じく、`GADBannerView` の奪い合いを避けるため @State でキャッシュし初回表示時に一度だけ生成する。
/// 画面下の固定バナーとは併用しない（1 画面に広告は 1 枠）。押せる要素とは上下に余白を取って置く（#1749）。
public struct MediumRectangleSlot: View {
    private let ads: AdService
    @State private var ad: AnyView?
    @State private var didMake = false
    public static let size = CGSize(width: 300, height: 250)

    public init(ads: AdService) {
        self.ads = ads
    }

    public var body: some View {
        Group {
            if let ad { ad } else { Color.clear }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .frame(maxWidth: .infinity)
        .task {
            guard !didMake else { return }
            didMake = true
            ad = ads.makeMediumRectangleView()
        }
    }
}
