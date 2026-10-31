import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGomoku

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
@Suite("最後に選んだ開始条件（#3151）・GameGomoku")
struct GomokuLastStartTests {
    @Test("後手・強さ 3・禁じ手ありで始めると、次のモデルの初期値に残る。記録が無ければ先手・1・なし")
    func remembersSideLevelAndRenju() {
        let f = LastStartFixture()
        let first = GomokuModel(services: f.services())
        #expect(first.humanSide == .black)
        #expect(first.aiLevel == 1)
        #expect(!first.forbiddenMovesEnabled)
        first.newGame(humanSide: .white, aiLevel: 3, forbiddenMoves: true)
        f.store.clear(for: "gomoku")
        let next = GomokuModel(services: f.services())
        #expect(next.humanSide == .white)
        #expect(next.aiLevel == 3)
        #expect(next.forbiddenMovesEnabled)
    }
}
