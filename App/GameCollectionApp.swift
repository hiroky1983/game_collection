import SwiftUI
import Core
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
            HubView(
                registry: AppEnvironment.registry,
                services: AppEnvironment.services,
                settings: AppEnvironment.settings,
                initialGameID: startGameID
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 起動時は広告の初期化だけ行い、ATT 許可は聞かない（初回起動の1枚目がシステムダイアログに
            // なるのを避ける。実際に聞くのは最初のゲームを遊び終えてハブに戻った時点＝HubView）。
            if newPhase == .active && !adsInitialized {
                adsInitialized = true
                Task {
                    await initializeAds()
                }
            }
        }
    }

    private var startGameID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startGame"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
