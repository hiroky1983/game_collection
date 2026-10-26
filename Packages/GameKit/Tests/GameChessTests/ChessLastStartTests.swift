import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameChess


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
@Suite("最後に選んだ開始条件（#2611）・GameChess")
struct GameChessLastStartTests {
    @Test("黒・強さ 3 で始めると、次のモデルの初期値が黒・3 になる。記録が無ければ白・1")
    func remembersSideAndLevel() {
        let f = LastStartFixture()
        let first = ChessGameModel(services: f.services())
        #expect(first.humanSide == .white)
        #expect(first.aiLevel == 1)
        first.newGame(humanSide: .black, aiLevel: 3)
        f.store.clear(for: "chess")
        let next = ChessGameModel(services: f.services())
        #expect(next.humanSide == .black)
        #expect(next.aiLevel == 3)
    }
}
