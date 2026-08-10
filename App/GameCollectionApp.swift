import SwiftUI
import Core
import FirebaseCore

@main
struct GameCollectionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var attRequested = false

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
                initialGameID: startGameID,
                showsSettingsInitially: showSettingsOnLaunch
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 撮影モードでは ATT ダイアログがスクショに被るため聞かない（DEBUG のみ有効）
            if newPhase == .active && !attRequested && !AppEnvironment.isScreenshotMode {
                attRequested = true
                Task {
                    await requestATTAndInitializeAds()
                }
            }
        }
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
