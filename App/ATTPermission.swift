import AppTrackingTransparency
import GoogleMobileAds

/// AdMob を初期化する。ATT の結果は待たない（拒否でも広告は出る＝非パーソナライズになるだけ）。
/// ATT ダイアログは初回起動では出さず、最初のゲームを遊び終えた時点で事前説明を挟んでから出す
/// （`TrackingConsentGate` / `TrackingConsentPrompt`）。
@MainActor
func initializeAds() async {
    // AdMob 独自の例外・シグナルハンドラを無効化する。有効のままだと Crashlytics の
    // クラッシュ捕捉を横取りしてレポートが届かない（SDK 自身が起動時に警告を出す）。
    GADMobileAds.sharedInstance().disableSDKCrashReporting()
    await GADMobileAds.sharedInstance().start()
}

/// ATT の許可状態がまだ未決定か（＝これから許可を聞ける状態か）。
@MainActor
var isTrackingAuthorizationUndetermined: Bool {
    ATTrackingManager.trackingAuthorizationStatus == .notDetermined
}

/// ATT 許可ダイアログを表示する。許可・拒否どちらでも広告は表示される（拒否時は非パーソナライズ広告）。
@MainActor
func requestTrackingAuthorization() async {
    _ = await ATTrackingManager.requestTrackingAuthorization()
}
