import SwiftUI
import Core
import MahjongTiles
import FirebaseCore

@main
struct GameCollectionApp: App {
    /// 中断のお知らせ（#663）のタップを、アプリが終了していた状態からでも受け取るため。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var adsInitialized = false

    init() {
        // Firebase Analytics / Crashlytics の初期化
        FirebaseApp.configure()
        // 設定の「利用状況の送信」を SDK 全体の収集状態へ反映する（#158）。
        // 収集は Info.plist で既定オフにしてあり（#382）、許可された経路でだけここが ON を立てる。
        AppEnvironment.applyAnalyticsCollectionState()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // 動作確認用: 麻雀牌の全 42 種を複数サイズで並べて出す（`-showMahjongTiles`）。
            // 盤面では牌が重なって減光もかかるため、絵柄そのものの見分けはここで確認する。
            if ProcessInfo.processInfo.arguments.contains("-showMahjongTiles") {
                MahjongTileGallery()
            } else {
                hub
            }
            #else
            hub
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 起動時は広告の初期化だけ行い、ATT 許可は聞かない（初回起動の1枚目がシステムダイアログに
            // なるのを避ける。実際に聞くのは最初のゲームを遊び終えてハブに戻った時点＝HubView）。
            // 撮影モードは広告そのものを出さない（NoopAdService）ので SDK の初期化も走らせない。
            if newPhase == .active && !adsInitialized && !AppEnvironment.isScreenshotMode {
                adsInitialized = true
                Task {
                    await initializeAds()
                    // リワード広告を 1 本先読みしておく（#658）。表示はタップ時だけ。
                    (AppEnvironment.services.ads as? AdMobAdService)?.enableRewardedPreload()
                }
                // Game Center 認証（#289 段階①）。iOS 26「ゲーム」アプリの推薦面に載る資格を
                // 得るためのもので、失敗してもゲームには一切影響しない。撮影モードでは
                // ウェルカムバナーがスクリーンショットに写り込むため開始しない。
                GameCenterAuth.start()
            }
            // 再エンゲージメント通知（#1193）の対象は、バックグラウンドに入るたびに判定し直す
            // （アプリを開いている間の経過日数は判定材料として発生しないため）。
            if newPhase == .background {
                AppEnvironment.reengagement.applicationDidEnterBackground(
                    games: AppEnvironment.reengagementCandidateInputs(),
                    availableIDs: AppEnvironment.settings.visibleModules(from: AppEnvironment.registry).map(\.id)
                )
            }
        }
    }

    private var hub: some View {
        HubView(
            registry: AppEnvironment.registry,
            services: AppEnvironment.services,
            settings: AppEnvironment.settings,
            initialGameID: startGameID,
            showsSettingsInitially: showSettingsOnLaunch,
            showsRecordsInitially: showRecordsOnLaunch
        )
        // iPad の広い画面へ追従するための適応レイヤ（#458）。ウインドウの幅をここで一度だけ測り、
        // `\.adaptiveLayout` として全画面へ配る。各画面はこの値を読むだけで、
        // `horizontalSizeClass` の分岐を自前で持たない。
        .providesAdaptiveLayout()
    }

    private var startGameID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startGame"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 撮影モードで設定画面を撮るための起動引数（`-screenshotMode -showSettings`）。
    private var showSettingsOnLaunch: Bool {
        AppEnvironment.isScreenshotMode
            && ProcessInfo.processInfo.arguments.contains("-showSettings")
    }

    /// 撮影モードで「きろく」画面（#669）を撮るための起動引数（`-screenshotMode -showRecords`）。
    private var showRecordsOnLaunch: Bool {
        AppEnvironment.isScreenshotMode
            && ProcessInfo.processInfo.arguments.contains("-showRecords")
    }
}
