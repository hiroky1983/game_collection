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
    await GADMobileAds.sharedInstance().start()
}
