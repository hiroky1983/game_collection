import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameHearts

/// 使い捨ての UserDefaults で PlayLog を作る。
@MainActor
private struct LastStartFixture {
    let name = "asobiba.laststart.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let store = MemorySnapshotStore()
    init() {
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }
    func services() -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService(), playLog: PlayLog(defaults: defaults))
    }
}

@MainActor
@Suite("最後に選んだ開始条件（#3151）・GameHearts")
struct HeartsLastStartTests {
    @Test("強さ 2 で始めると、次のモデルの初期値が 2 になる。記録が無ければ標準")
    func remembersLevel() {
        let f = LastStartFixture()
        let first = HeartsModel(services: f.services())
        #expect(first.aiLevel == CPUStrength.standard.rawValue)
        first.startMatch(aiLevel: 2)
        f.store.clear(for: "hearts")
        let next = HeartsModel(services: f.services())
        #expect(next.aiLevel == 2)
    }
}
