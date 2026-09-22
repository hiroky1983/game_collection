import SwiftUI
import GoogleMobileAds
import Core

// MARK: - Banner ViewModel

@MainActor
final class AdMobBannerViewModel: NSObject, @preconcurrency GADBannerViewDelegate {
    let bannerView: GADBannerView

    init(width: CGFloat) {
        bannerView = GADBannerView(adSize: GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width))
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
    private let onFailToPresent: () -> Void

    /// `onFailToPresent` を省くと、表示の失敗も閉じられたのと同じ扱いになる。
    init(onDismiss: @escaping () -> Void, onFailToPresent: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        self.onFailToPresent = onFailToPresent ?? onDismiss
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onFailToPresent()
    }
}

// MARK: - AdService 実装

@MainActor
public final class AdMobAdService: AdService {
    private var fullScreenDelegate: FullScreenDelegate?

    /// 先読みしたリワード広告（#658）。タップ時はこれを使い、読み込みを待たせない。
    private var rewardedSlot = PreloadedAdSlot<GADRewardedAd>()
    /// 進行中の先読み。二重に読み込まないためと、タップがその途中に来たときに相乗りするため。
    private var rewardedPreloadTask: Task<Void, Never>?
    /// SDK の初期化（`initializeAds()`）が済むまでは先読みしない。
    private var isRewardedPreloadEnabled = false

    public init() {}

    /// SDK の初期化が済んだら呼ぶ。以後の先読みを許し、最初の 1 本を読み込む。
    public func enableRewardedPreload() {
        isRewardedPreloadEnabled = true
        preloadRewardedAd()
    }

    /// リワード広告を 1 本先読みする。使える広告を預かっている・読み込み中なら何もしない。
    /// 読み込むだけで表示はしない（表示はユーザーのタップを起点にした `showRewardedAd()` だけ）。
    public func preloadRewardedAd() {
        guard isRewardedPreloadEnabled, rewardedPreloadTask == nil,
              !rewardedSlot.hasFreshAd(now: Date()) else { return }
        rewardedPreloadTask = Task { [weak self] in
            // 失敗は握りつぶす。次の先読みの機会（ハブからゲームを開く）か、タップ時の読み込みに任せる。
            let ad = try? await GADRewardedAd.load(
                withAdUnitID: AdConfig.effectiveRewardedID,
                request: GADRequest()
            )
            guard let self else { return }
            if let ad { self.rewardedSlot.store(ad, loadedAt: Date()) }
            self.rewardedPreloadTask = nil
        }
    }

    // 画面ごとに独立した GADBannerView を持たせる。共有すると UIView が奪われ HubView で表示されない。
    @MainActor public func makeBannerView(width: CGFloat) -> AnyView? {
        let vm = AdMobBannerViewModel(width: width)
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
        // 先読みの途中でタップされたら、もう 1 本読み始めずにその完了を待つ。
        if let preload = rewardedPreloadTask {
            await preload.value
        }
        // 先読みした広告があれば読み込みを待たずに出す。失効していた・表示に失敗した回だけ、
        // 従来どおりその場で読み込む。
        if let ad = rewardedSlot.take(now: Date()), let root = rootViewController() {
            switch await present(ad, from: root) {
            case .rewarded:
                preloadRewardedAd()
                return true
            case .notRewarded:
                preloadRewardedAd()
                return false
            case .failedToPresent:
                break
            }
        }

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

        let outcome = await present(ad, from: root)
        // 出し終えたので次の 1 本を読んでおく。読み込みに失敗した回は、回線が戻っていない
        // 見込みが高いので続けて読み直さない。
        preloadRewardedAd()
        return outcome == .rewarded
    }

    private enum RewardedPresentOutcome {
        case rewarded, notRewarded, failedToPresent
    }

    /// リワード広告を出し、閉じられるか表示に失敗するまで待つ。
    private func present(_ ad: GADRewardedAd, from root: UIViewController) async -> RewardedPresentOutcome {
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<RewardedPresentOutcome, Never>) in
            var rewarded = false
            let delegate = FullScreenDelegate(
                onDismiss: { continuation.resume(returning: rewarded ? .rewarded : .notRewarded) },
                onFailToPresent: { continuation.resume(returning: .failedToPresent) }
            )
            self.fullScreenDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(fromRootViewController: root) {
                rewarded = true
            }
        }
        fullScreenDelegate = nil
        return outcome
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
    }
}
