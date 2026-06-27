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

// MARK: - Full Screen Delegate

@MainActor
private final class FullScreenDelegate: NSObject, @preconcurrency GADFullScreenContentDelegate {
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
    private var fullScreenDelegate: FullScreenDelegate?

    public init() {}

    // 画面ごとに独立した GADBannerView を持たせる。共有すると UIView が奪われ HubView で表示されない。
    @MainActor public func makeBannerView() -> AnyView? {
        let vm = AdMobBannerViewModel()
        return AnyView(AdMobBannerView(viewModel: vm))
    }

    @MainActor public func showInterstitial() async {
        let ad: GADInterstitialAd?
        do {
            ad = try await GADInterstitialAd.load(
                withAdUnitID: AdConfig.effectiveInterstitialID,
                request: GADRequest()
            )
        } catch {
            return
        }
        guard let ad else { return }
        guard let root = rootViewController() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = FullScreenDelegate { continuation.resume() }
            self.fullScreenDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(fromRootViewController: root)
        }
        fullScreenDelegate = nil
    }

    @MainActor public func showRewardedAd() async -> Bool {
        let ad: GADRewardedAd?
        do {
            ad = try await GADRewardedAd.load(
                withAdUnitID: AdConfig.effectiveRewardedID,
                request: GADRequest()
            )
        } catch {
            return false
        }
        guard let ad else { return false }
        guard let root = rootViewController() else { return false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var rewarded = false
            let delegate = FullScreenDelegate { continuation.resume(returning: rewarded) }
            self.fullScreenDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(fromRootViewController: root) {
                rewarded = true
            }
        }
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
    }
}
