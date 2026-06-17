import SwiftUI
import Core

@main
struct GameCollectionApp: App {
    var body: some Scene {
        WindowGroup {
            HubView(
                registry: AppEnvironment.registry,
                services: AppEnvironment.services,
                initialGameID: startGameID
            )
            .task {
                await requestATTAndInitializeAds()
            }
        }
    }

    private var startGameID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startGame"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
