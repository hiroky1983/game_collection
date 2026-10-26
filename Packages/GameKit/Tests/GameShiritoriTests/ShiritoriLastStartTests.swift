import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameShiritori


/// 使い捨ての UserDefaults で PlayLog を作る。`reopen` は「アプリ再起動」を表し、同じ保存先から作り直す。
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
@Suite("最後に選んだ開始条件（#2611）・GameShiritori")
struct GameShiritoriLastStartTests {
    @Test("ノルマとモードを覚える。記録が無ければ既定のまま")
    func remembersChoice() {
        let f = LastStartFixture()
        let first = ShiritoriModel(services: f.services(), cpuDelay: .zero, seed: 1)
        first.startGame(quota: .hard, mode: .endless)
        f.store.clear(for: "shiritori")
        let next = ShiritoriModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(next.quota == .hard)
        #expect(next.mode == .endless)
    }
}
