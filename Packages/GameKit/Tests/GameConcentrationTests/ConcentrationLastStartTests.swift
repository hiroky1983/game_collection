import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameConcentration


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
@Suite("最後に選んだ開始条件（#2611）・GameConcentration")
struct GameConcentrationLastStartTests {
    @Test("組数と強さを覚える。記録が無ければ 12 ペア・ふつう")
    func remembersChoice() {
        let f = LastStartFixture()
        let first = ConcentrationModel(services: f.services())
        #expect(first.pairCount == .medium)
        #expect(first.cpuLevel == .normal)
        first.newGame(pairCount: .large, cpuLevel: .strong)
        f.store.clear(for: "concentration")
        let next = ConcentrationModel(services: f.services())
        #expect(next.pairCount == .large)
        #expect(next.cpuLevel == .strong)
    }
}
