import SwiftUI
import Core

@main
struct GameCollectionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var attRequested = false

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
            if newPhase == .active && !attRequested {
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
}
