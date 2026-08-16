import SwiftUI
import Core
import MahjongTiles
import FirebaseCore

@main
struct GameCollectionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var adsInitialized = false

    init() {
        // Firebase Analytics / Crashlytics の初期化（デフォルトの自動収集イベントのみ）
        FirebaseApp.configure()
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
                }
            }
        }
    }

    private var hub: some View {
        HubView(
            registry: AppEnvironment.registry,
            services: AppEnvironment.services,
            settings: AppEnvironment.settings,
            initialGameID: startGameID,
            showsSettingsInitially: showSettingsOnLaunch
        )
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
}
