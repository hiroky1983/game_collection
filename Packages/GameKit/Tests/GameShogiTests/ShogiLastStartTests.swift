import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameShogi

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
@Suite("最後に選んだ開始条件（#3151）・GameShogi")
struct ShogiLastStartTests {
    @Test("後手・強さ 3・飛車落ちで始めると、次のモデルの開始シートの初期値に残り、始め直すと進行中の局に戻る")
    func remembersSideLevelAndHandicap() {
        let f = LastStartFixture()
        let first = ShogiGameModel(services: f.services())
        #expect(first.humanSide == .black)
        #expect(first.aiLevel == 1)
        #expect(first.startSheetSetting.handicap == .even)
        first.newGame(humanSide: .white, aiLevel: 3, handicap: .even, dropper: .player)
        first.newGame(humanSide: .black, aiLevel: 3, handicap: .rook, dropper: .cpu)
        f.store.clear(for: "shogi")
        let next = ShogiGameModel(services: f.services())
        #expect(next.humanSide == .black)
        #expect(next.aiLevel == 3)
        #expect(next.startSheetSetting.handicap == .rook)
        #expect(next.startSheetSetting.dropper == .cpu)
        next.newGame(humanSide: .black, aiLevel: 3)
        #expect(next.startSheetSetting.handicap == .even)
    }
}
