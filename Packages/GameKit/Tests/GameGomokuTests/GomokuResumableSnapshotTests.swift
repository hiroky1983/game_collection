import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGomoku

/// 一手も打っていない盤は「続きから」に出さない（#1572）。
@Suite("五目並べの「続きから」判定（#1572）")
@MainActor
struct GomokuResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手打つと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = GomokuModule()
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tap(row: 7, col: 7)
        #expect(module.hasResumableSnapshot(in: store), "一手打った盤（対照）")
    }

    @Test("手順を持たない旧形式は盤上の石で判定する")
    func legacySnapshotWithoutHistory() throws {
        let store = MemorySnapshotStore()
        var cells = [Int?](repeating: nil, count: gomokuBoardSize * gomokuBoardSize)
        func snapshot(_ cells: [Int?]) -> GomokuSnapshot {
            GomokuSnapshot(
                cells: cells, currentStone: GomokuStone.black.rawValue, humanSide: GomokuStone.black.rawValue,
                aiLevel: 1, startedAt: Date(), moveHistory: nil, undoUsed: nil, resigned: nil, winner: nil,
                forbiddenMoves: nil, hintsUsed: nil)
        }
        try store.save(snapshot(cells), for: "gomoku")
        #expect(!GomokuModule().hasResumableSnapshot(in: store))
        cells[0] = GomokuStone.black.rawValue
        try store.save(snapshot(cells), for: "gomoku")
        #expect(GomokuModule().hasResumableSnapshot(in: store))
    }

    @Test("人間が白のとき、CPU の初手だけでは続きではなく手つかず。自分が打つと続きになる（#2508）")
    func whiteAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = GomokuModule()
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        #expect(!model.isAITurn, "CPU が初手を打った（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        model.tap(row: 0, col: 0)
        #expect(module.hasResumableSnapshot(in: store), "自分が打った盤（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("CPU の初手だけで離れても途中離脱に数えない（#3042）")
    func cpuOpeningIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["gomoku"]),
            isResumable: { _, snapshots in GomokuModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "gomoku")
        let model = GomokuModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        services.gameDidLeave(gameID: "gomoku")
        #expect(spy.quits.isEmpty, "CPU が指しただけでは離脱に数えない")
    }

    @Test("自分が指した後に離れると途中離脱に数える（対照・上のテストが空振りでない証拠・#3042）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["gomoku"]),
            isResumable: { _, snapshots in GomokuModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "gomoku")
        let model = GomokuModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        model.tap(row: 0, col: 0)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "gomoku", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["gomoku"], "自分が指した後は従来どおり数える（対照）")
    }
}
