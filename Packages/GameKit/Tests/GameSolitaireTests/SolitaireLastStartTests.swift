import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameSolitaire


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
@Suite("最後に選んだ開始条件（#2611）・GameSolitaire")
struct GameSolitaireLastStartTests {
    @Test("3 枚めくりで始めると、次のモデルの初期ルールが 3 枚めくりになる。記録が無ければ 1 枚めくり")
    func remembersDrawMode() {
        let f = LastStartFixture()
        #expect(SolitaireModel(services: f.services()).rules.drawMode == .one)
        SolitaireModel(services: f.services()).newGame(rules: SolitaireRuleSet(drawMode: .three))
        f.store.clear(for: "solitaire")
        #expect(SolitaireModel(services: f.services()).rules.drawMode == .three)
    }
}
