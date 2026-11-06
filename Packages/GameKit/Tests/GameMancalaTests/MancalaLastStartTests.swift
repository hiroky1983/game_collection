import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameMancala

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
@Suite("最後に選んだ開始条件（#3224）・GameMancala")
struct MancalaLastStartTests {
    @Test("後手・強さを変えて始めると、次のモデルの初期値がその条件になる。記録が無ければ先手・標準")
    func remembersTurnAndLevel() {
        let f = LastStartFixture()
        let first = MancalaModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(first.humanFirst)
        #expect(first.aiLevel == CPUStrength.standard.rawValue)
        first.newGame(humanFirst: false, aiLevel: CPUStrength.allCases[0].rawValue)
        f.store.clear(for: "mancala")
        let next = MancalaModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(!next.humanFirst)
        #expect(next.aiLevel == CPUStrength.allCases[0].rawValue)
    }

    @Test("保存値が不正（知らない強さ）なら標準に倒れる")
    func invalidFallsBackToDefault() {
        let f = LastStartFixture()
        f.services().playLog?.saveLastStart(MancalaStartChoice(humanFirst: false, aiLevel: 999), gameID: "mancala")
        let model = MancalaModel(services: f.services(), cpuDelay: .zero, seed: 1)
        #expect(model.aiLevel == CPUStrength.standard.rawValue)
    }
}
