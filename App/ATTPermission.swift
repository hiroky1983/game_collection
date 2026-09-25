import AppTrackingTransparency
import GoogleMobileAds

/// AdMob を初期化する。ATT の結果は待たない（拒否でも広告は出る＝非パーソナライズになるだけ）。
/// ATT のシステムダイアログは、初回起動でハブが描画された直後に `HubView` が直接出す
/// （AdMob を収入源とする以上 ATT は避けて通れないため、自前の事前説明は挟まない。会長決裁 2026-08-27）。
@MainActor
func initializeAds() async {
    // AdMob 独自の例外・シグナルハンドラを無効化する。有効のままだと Crashlytics の
    // クラッシュ捕捉を横取りしてレポートが届かない（SDK 自身が起動時に警告を出す）。
    GADMobileAds.sharedInstance().disableSDKCrashReporting()
    // 広告の内容レーティング上限を G（全年齢）に固定する。アプリは 4+ で、v1.1.0 は年齢制限（広告）で
    // リジェクトされた経緯があるため、AdMob コンソールの設定に依存せずコードでも絞る
    // （会長決裁 2026-09-25・#1387）。start() より前に設定しないと最初の広告要求に間に合わない。
    GADMobileAds.sharedInstance().requestConfiguration.maxAdContentRating = .general
    await GADMobileAds.sharedInstance().start()
}

/// ATT 許可ダイアログを表示する。許可・拒否どちらでも広告は表示される（拒否時は非パーソナライズ広告）。
@MainActor
func requestTrackingAuthorization() async {
    _ = await ATTrackingManager.requestTrackingAuthorization()
}
