import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGo


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
@Suite("最後に選んだ開始条件（#2611）・GameGo")
struct GameGoLastStartTests {
    @Test("白・強さ・置き石を覚える。黒の置き石は次回の初期値になる。記録が無ければ黒・ふつう・置き石なし")
    func remembersChoice() {
        let f = LastStartFixture()
        let first = GoModel(services: f.services())
        #expect(first.humanSide == .black)
        #expect(first.aiLevel == .normal)
        #expect(first.ruleset.handicap == 0)
        first.newGame(humanSide: .black, level: .hard, handicap: 2)
        f.store.clear(for: "go")
        let next = GoModel(services: f.services())
        #expect(next.humanSide == .black)
        #expect(next.aiLevel == .hard)
        #expect(next.ruleset.handicap == 2)
    }
}
