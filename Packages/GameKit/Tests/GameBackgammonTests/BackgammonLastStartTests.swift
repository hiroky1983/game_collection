import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameBackgammon

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
@Suite("最後に選んだ開始条件（#3224）・GameBackgammon")
struct BackgammonLastStartTests {
    @Test("強さを変えて始めると、次のモデルの初期値がその強さになる。記録が無ければ標準")
    func remembersLevel() {
        let f = LastStartFixture()
        let first = BackgammonModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(first.aiLevel == CPUStrength.standard.rawValue)
        first.newGame(aiLevel: CPUStrength.allCases[0].rawValue)
        f.store.clear(for: "backgammon")
        let next = BackgammonModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(next.aiLevel == CPUStrength.allCases[0].rawValue)
    }

    @Test("保存値が不正（知らない強さ）なら標準に倒れる")
    func invalidFallsBackToDefault() {
        let f = LastStartFixture()
        f.services().playLog?.saveLastStart(999, gameID: "backgammon")
        let model = BackgammonModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(model.aiLevel == CPUStrength.standard.rawValue)
    }
}
