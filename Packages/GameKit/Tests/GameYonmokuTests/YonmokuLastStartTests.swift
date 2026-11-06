import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameYonmoku

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
@Suite("最後に選んだ開始条件（#3224）・GameYonmoku")
struct YonmokuLastStartTests {
    @Test("後手・強さを変えて始めると、次のモデルの初期値がその条件になる。記録が無ければ先手・標準")
    func remembersSideAndLevel() {
        let f = LastStartFixture()
        let first = YonmokuModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(first.humanSide == .black)
        #expect(first.aiLevel == CPUStrength.standard.rawValue)
        first.newGame(humanSide: .white, aiLevel: CPUStrength.allCases[0].rawValue)
        f.store.clear(for: "yonmoku")
        let next = YonmokuModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(next.humanSide == .white)
        #expect(next.aiLevel == CPUStrength.allCases[0].rawValue)
    }

    @Test("保存値が不正（知らない強さ・先後）なら既定値に倒れる")
    func invalidFallsBackToDefault() {
        let f = LastStartFixture()
        f.services().playLog?.saveLastStart(YonmokuStartChoice(humanSide: 99, aiLevel: 999), gameID: "yonmoku")
        let model = YonmokuModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(model.humanSide == .black)
        #expect(model.aiLevel == CPUStrength.standard.rawValue)
    }
}
