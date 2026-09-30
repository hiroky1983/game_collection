import Testing
import Core
import CoreTestSupport
@testable import GameShogi

/// 一手も指していない局は「続きから」に出さない（#1599。#1572 の取りこぼし）。
@Suite("将棋の「続きから」判定（#1599）")
@MainActor
struct ShogiResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手指すと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(module.hasResumableSnapshot(in: store), "一手指した局（対照）")
    }
}
