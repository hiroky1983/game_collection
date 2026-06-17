import SwiftUI
import GoogleMobileAds
import Core

// MARK: - Banner ViewModel

@MainActor
final class AdMobBannerViewModel: NSObject, @preconcurrency GADBannerViewDelegate {
    let bannerView: GADBannerView

    override init() {
        bannerView = GADBannerView(adSize: GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(
            UIScreen.main.bounds.width
        ))
        bannerView.adUnitID = AdConfig.effectiveBannerID
        super.init()
        bannerView.delegate = self
    }

    func load() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        bannerView.rootViewController = root
        bannerView.load(GADRequest())
    }
}

// MARK: - UIViewRepresentable

struct AdMobBannerView: UIViewRepresentable {
    let viewModel: AdMobBannerViewModel

    func makeUIView(context: Context) -> GADBannerView {
        viewModel.load()
        return viewModel.bannerView
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}

// MARK: - AdService 実装

@MainActor
public final class AdMobAdService: AdService {
    private let viewModel = AdMobBannerViewModel()

    public init() {}

    @MainActor public func makeBannerView() -> AnyView? {
        AnyView(AdMobBannerView(viewModel: viewModel))
    }
}
