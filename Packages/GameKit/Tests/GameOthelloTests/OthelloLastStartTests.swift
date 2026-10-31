import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameOthello

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
@Suite("最後に選んだ開始条件（#3151）・GameOthello")
struct OthelloLastStartTests {
    @Test("後手・強さ 3 で始めると、次のモデルの初期値が後手・3 になる。記録が無ければ先手・1")
    func remembersSideAndLevel() {
        let f = LastStartFixture()
        let first = OthelloModel(services: f.services())
        #expect(first.humanSide == .black)
        #expect(first.aiLevel == 1)
        first.newGame(humanSide: .white, aiLevel: 3)
        f.store.clear(for: "othello")
        let next = OthelloModel(services: f.services())
        #expect(next.humanSide == .white)
        #expect(next.aiLevel == 3)
    }
}
