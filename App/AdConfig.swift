/// AdMob のユニット ID。本番申請前にテスト ID から差し替える。
enum AdConfig {
    static let appID          = "ca-app-pub-1869410932032409~4823987816"
    static let bannerID       = "ca-app-pub-1869410932032409/5642245468"
    static let interstitialID = "ca-app-pub-1869410932032409/6461337269"
    static let rewardedID     = "ca-app-pub-1869410932032409/8789412276"

    /// 開発中はテスト広告ユニット ID を使う（本番 ID の使用はポリシー違反）。
    /// `DEBUG` フラグが立っているビルドでは自動的にテスト ID に切り替わる。
    static var effectiveBannerID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716" // Google 公式テスト ID
        #else
        return bannerID
        #endif
    }

    static var effectiveInterstitialID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910" // Google 公式テスト ID
        #else
        return interstitialID
        #endif
    }

    static var effectiveRewardedID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313" // Google 公式テスト ID
        #else
        return rewardedID
        #endif
    }
}
