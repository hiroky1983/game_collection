import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameMahjong

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
@Suite("最後に選んだ開始条件（#3151）・GameMahjong")
struct MahjongLastStartTests {
    @Test("半荘戦で始めると、次の起動で LastStart に半荘戦が残る。記録が無ければ nil")
    func remembersLength() {
        let f = LastStartFixture()
        let services = f.services()
        #expect(services.playLog?.lastStart(String.self, gameID: "mahjong4") == nil)
        let model = MahjongModel(services: services)
        model.startGame(length: .hanchan)
        #expect(f.services().playLog?.lastStart(String.self, gameID: "mahjong4") == "hanchan")
        model.startGame(length: .singleHand)
        #expect(f.services().playLog?.lastStart(String.self, gameID: "mahjong4") == "singleHand")
    }
}
