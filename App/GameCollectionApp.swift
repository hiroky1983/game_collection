import SwiftUI
import Core

@main
struct GameCollectionApp: App {
    var body: some Scene {
        WindowGroup {
            // 起動引数 -startGame <id> で特定ゲームを push 状態で開く（開発時の確認用）。
            // ハブを土台に push するので、ゲーム側「戻る」でハブに戻れる（実フローと同じ）。
            HubView(
                registry: AppEnvironment.registry,
                services: AppEnvironment.services,
                initialGameID: startGameID
            )
        }
    }

    private var startGameID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startGame"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
