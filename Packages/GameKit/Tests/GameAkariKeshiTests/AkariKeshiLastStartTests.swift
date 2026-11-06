import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameAkariKeshi

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
@Suite("最後に選んだ開始条件（#3224）・GameAkariKeshi")
struct AkariKeshiLastStartTests {
    @Test("難易度を変えて始めると、次のモデルの初期値がその難易度になる。記録が無ければ入門")
    func remembersDifficulty() {
        let f = LastStartFixture()
        let first = AkariKeshiModel(services: f.services(), seed: 1)
        #expect(first.difficulty == .easy)
        first.newGame(difficulty: .hard)
        f.store.clear(for: AkariKeshiModel.gameID)
        let next = AkariKeshiModel(services: f.services(), seed: 1)
        #expect(next.difficulty == .hard)
    }

    @Test("保存値が読めないときは入門に倒れる")
    func invalidFallsBackToDefault() {
        let f = LastStartFixture()
        f.services().playLog?.saveLastStart("nightmare", gameID: AkariKeshiModel.gameID)
        let model = AkariKeshiModel(services: f.services(), seed: 1)
        #expect(model.difficulty == .easy)
    }
}
