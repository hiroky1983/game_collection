import Foundation
import Observation
import Core

@MainActor
@Observable
final class GameSettings {
    private(set) var orderedIDs: [String]
    private(set) var hiddenIDs: Set<String>
    /// 触覚フィードバックのオン / オフ。既定はオン。
    var hapticsEnabled: Bool {
        didSet { Self.haptics.isEnabled = hapticsEnabled }
    }
    /// 効果音のオン / オフ。既定はオン。触覚とは独立に切り替えられる。
    var soundEnabled: Bool {
        didSet { Self.sound.isEnabled = soundEnabled }
    }

    private static let orderKey    = "gameOrder_v1"
    private static let hiddenKey   = "hiddenGames_v1"
    private static let haptics = FeedbackPreference(key: "hapticsEnabled_v1")
    private static let sound   = FeedbackPreference(key: "soundEnabled_v1")

    init(registeredIDs: [String]) {
        let stored = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        var order = stored.filter { registeredIDs.contains($0) }
        for id in registeredIDs where !order.contains(id) { order.append(id) }
        self.orderedIDs = order

        let hiddenArr = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        self.hiddenIDs = Set(hiddenArr.filter { registeredIDs.contains($0) })

        // 未設定（初回起動・キー無し）はオン。既定値の規則は FeedbackPreference が持つ。
        self.hapticsEnabled = Self.haptics.isEnabled
        self.soundEnabled = Self.sound.isEnabled
    }

    func visibleModules(from registry: GameRegistry) -> [GameModule] {
        orderedIDs
            .compactMap { registry.module(id: $0) }
            .filter { !hiddenIDs.contains($0.id) }
    }

    func move(from: IndexSet, to: Int) {
        orderedIDs.move(fromOffsets: from, toOffset: to)
        save()
    }

    func toggleHidden(_ id: String) {
        if hiddenIDs.contains(id) {
            hiddenIDs.remove(id)
        } else {
            hiddenIDs.insert(id)
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(orderedIDs, forKey: Self.orderKey)
        UserDefaults.standard.set(Array(hiddenIDs), forKey: Self.hiddenKey)
    }
}
