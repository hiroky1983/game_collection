import SwiftUI
import GoogleMobileAds
import Core

// MARK: - Banner ViewModel

@MainActor
final class AdMobBannerViewModel: NSObject, @preconcurrency BannerViewDelegate {
    let bannerView: BannerView

    init(width: CGFloat) {
        bannerView = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        bannerView.adUnitID = AdConfig.effectiveBannerID
        super.init()
        bannerView.delegate = self
    }

    func load() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        bannerView.rootViewController = root
        bannerView.load(Request())
    }
}

// MARK: - UIViewRepresentable

struct AdMobBannerView: UIViewRepresentable {
    let viewModel: AdMobBannerViewModel

    func makeUIView(context: Context) -> BannerView {
        viewModel.load()
        return viewModel.bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

// MARK: - Medium Rectangle（300×250）

/// ページの中に置く 300×250 の広告。読み込み・表示の作法はバナーと同じ（サイズとユニットだけ違う）。
@MainActor
final class AdMobMediumRectangleViewModel: NSObject, @preconcurrency BannerViewDelegate {
    let bannerView: BannerView

    override init() {
        bannerView = BannerView(adSize: AdSizeMediumRectangle)
        bannerView.adUnitID = AdConfig.effectiveMediumRectangleID
        super.init()
        bannerView.delegate = self
    }

    func load() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        bannerView.rootViewController = root
        bannerView.load(Request())
    }
}

struct AdMobMediumRectangleView: UIViewRepresentable {
    let viewModel: AdMobMediumRectangleViewModel

    func makeUIView(context: Context) -> BannerView {
        viewModel.load()
        return viewModel.bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

// MARK: - Full Screen Delegate

@MainActor
private final class FullScreenDelegate: NSObject, @preconcurrency FullScreenContentDelegate {
    private let onDismiss: () -> Void
    private let onFailToPresent: () -> Void

    /// `onFailToPresent` を省くと、表示の失敗も閉じられたのと同じ扱いになる。
    init(onDismiss: @escaping () -> Void, onFailToPresent: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        self.onFailToPresent = onFailToPresent ?? onDismiss
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onFailToPresent()
    }
}

// MARK: - AdService 実装

@MainActor
public final class AdMobAdService: AdService {
    private var fullScreenDelegate: FullScreenDelegate?

    /// 先読みしたリワード広告（#658）。タップ時はこれを使い、読み込みを待たせない。
    private var rewardedSlot = PreloadedAdSlot<RewardedAd>()
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
            let ad = try? await RewardedAd.load(
                with: AdConfig.effectiveRewardedID,
                request: Request()
            )
            guard let self else { return }
            if let ad { self.rewardedSlot.store(ad, loadedAt: Date()) }
            self.rewardedPreloadTask = nil
        }
    }

    /// 先読みした広告を失効前のまま預かっているか（`reward_offer` の `not_ready` の判定・#780）。
    /// 先読みの途中はまだ出せないので false。
    public var isRewardedAdReady: Bool {
        rewardedSlot.hasFreshAd(now: Date())
    }

    // 画面ごとに独立した BannerView を持たせる。共有すると UIView が奪われ HubView で表示されない。
    @MainActor public func makeBannerView(width: CGFloat) -> AnyView? {
        let vm = AdMobBannerViewModel(width: width)
        return AnyView(AdMobBannerView(viewModel: vm))
    }

    @MainActor public func makeMediumRectangleView() -> AnyView? {
        AnyView(AdMobMediumRectangleView(viewModel: AdMobMediumRectangleViewModel()))
    }

    @MainActor public func showInterstitial() async {
        let ad: InterstitialAd?
        do {
            ad = try await InterstitialAd.load(
                with: AdConfig.effectiveInterstitialID,
                request: Request()
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
            ad.present(from: root)
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

        let ad: RewardedAd?
        do {
            ad = try await RewardedAd.load(
                with: AdConfig.effectiveRewardedID,
                request: Request()
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
    private func present(_ ad: RewardedAd, from root: UIViewController) async -> RewardedPresentOutcome {
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<RewardedPresentOutcome, Never>) in
            var rewarded = false
            let delegate = FullScreenDelegate(
                onDismiss: { continuation.resume(returning: rewarded ? .rewarded : .notRewarded) },
                onFailToPresent: { continuation.resume(returning: .failedToPresent) }
            )
            self.fullScreenDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(from: root) {
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
