import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameMahjongSolitaire


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
@Suite("最後に選んだ開始条件（#2611）・GameMahjongSolitaire")
struct GameMahjongSolitaireLastStartTests {
    @Test("選んだかたちを覚える。記録が無ければ亀甲。起動引数で明示したかたちが優先")
    func remembersLayout() {
        let f = LastStartFixture()
        #expect(MahjongSolitaireModel(services: f.services(), seed: 1).layout.id == MahjongSolitaireLayout.turtle.id)
        let other = MahjongSolitaireLayout.all.first { $0.id != MahjongSolitaireLayout.turtle.id }!
        MahjongSolitaireModel(services: f.services(), seed: 1).newGame(layout: other)
        f.store.clear(for: MahjongSolitaireModel.snapshotID)
        #expect(MahjongSolitaireModel(services: f.services(), seed: 1).layout.id == other.id)
        #expect(MahjongSolitaireModel(services: f.services(), seed: 1, layout: .turtle).layout.id == MahjongSolitaireLayout.turtle.id)
    }
}
