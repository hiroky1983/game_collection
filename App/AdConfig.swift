/// AdMob のユニット ID。本番申請前にテスト ID から差し替える。
enum AdConfig {
    static let appID          = "ca-app-pub-1869410932032409~4823987816"
    static let bannerID       = "ca-app-pub-1869410932032409/5642245468"
    static let interstitialID = "ca-app-pub-1869410932032409/6461337269"
    static let rewardedID     = "ca-app-pub-1869410932032409/8789412276"

    /// 本番ユニット ID を使ってよいのは App Store 配布ビルドだけ（#347）。
    /// 開発ビルドに加えて TestFlight（リリース前実機確認）もテスト ID に倒す。
    /// 従来は `#if DEBUG` 判定だったため、Release ビルドである TestFlight の実機確認が
    /// 本番ユニットへ広告リクエストを飛ばしており、レポートの汚染と無効トラフィックの
    /// リスク（自分の本番広告の表示はポリシー違反）になっていた。
    private static var isProductionAdsAllowed: Bool {
        BuildChannel.current == .appstore
    }

    static var effectiveBannerID: String {
        isProductionAdsAllowed
            ? bannerID
            : "ca-app-pub-3940256099942544/2934735716" // Google 公式テスト ID
    }

    static var effectiveInterstitialID: String {
        isProductionAdsAllowed
            ? interstitialID
            : "ca-app-pub-3940256099942544/4411468910" // Google 公式テスト ID
    }

    static var effectiveRewardedID: String {
        isProductionAdsAllowed
            ? rewardedID
            : "ca-app-pub-3940256099942544/1712485313" // Google 公式テスト ID
    }
}
