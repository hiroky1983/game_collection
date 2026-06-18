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

// MARK: - Interstitial Delegate

@MainActor
private final class InterstitialDelegate: NSObject, @preconcurrency GADFullScreenContentDelegate {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onDismiss()
    }
}

// MARK: - AdService 実装

@MainActor
public final class AdMobAdService: AdService {
    private var interstitialDelegate: InterstitialDelegate?

    public init() {}

    // 画面ごとに独立した GADBannerView を持たせる。共有すると UIView が奪われ HubView で表示されない。
    @MainActor public func makeBannerView() -> AnyView? {
        let vm = AdMobBannerViewModel()
        return AnyView(AdMobBannerView(viewModel: vm))
    }

    @MainActor public func showInterstitial() async {
        // ロード
        let ad: GADInterstitialAd?
        do {
            ad = try await GADInterstitialAd.load(
                withAdUnitID: AdConfig.effectiveInterstitialID,
                request: GADRequest()
            )
        } catch {
            return // ロード失敗 → 広告なしで続行
        }
        guard let ad else { return }

        // rootViewController を取得
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }

        // 表示 → 閉じるまで await
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = InterstitialDelegate { continuation.resume() }
            self.interstitialDelegate = delegate   // delegate を保持
            ad.fullScreenContentDelegate = delegate
            ad.present(fromRootViewController: root)
        }
        interstitialDelegate = nil
    }
}
