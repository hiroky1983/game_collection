import AppTrackingTransparency
import GoogleMobileAds

/// アプリ起動後、ATT 許可ダイアログを表示してから AdMob を初期化する。
/// 許可・拒否どちらでも広告は表示される（拒否時は非パーソナライズ広告）。
@MainActor
func requestATTAndInitializeAds() async {
    if #available(iOS 14, *) {
        // iOS 14+ は ATT 許可を取ってから初期化
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
    // AdMob 独自の例外・シグナルハンドラを無効化する。有効のままだと Crashlytics の
    // クラッシュ捕捉を横取りしてレポートが届かない（SDK 自身が起動時に警告を出す）。
    GADMobileAds.sharedInstance().disableSDKCrashReporting()
    await GADMobileAds.sharedInstance().start()
}
