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

    @Test("「待った」で開始局面まで戻したら中断データを消し、離脱に数えない（#3200）")
    func undoToStartClearsSnapshot() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["gomoku"]),
            isResumable: { _, snapshots in GomokuModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "gomoku")
        let model = GomokuModel(services: services)
        model.newGame()
        model.tap(row: 7, col: 7)
        await model.performAIMoveIfNeeded()
        #expect(store.exists(for: "gomoku"), "前提: 1 往復指すと保存される")
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(model.moveCount == 0, "前提: 開始局面まで戻った")
        #expect(!store.exists(for: "gomoku"))
        #expect(GomokuModule().hasUntouchedSnapshot(in: store) == false)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "gomoku", isResumable: false)
        #expect(spy.quits.isEmpty, "手つかずの局は離脱に数えない")
    }

    @Test("「待った」で戻しても開始局面でなければ従来どおり保存し、続きとして残す（#3200）")
    func undoToMidGameKeepsSnapshot() async {
        let store = MemorySnapshotStore()
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame()
        model.tap(row: 7, col: 7)
        await model.performAIMoveIfNeeded()
        model.tap(row: 0, col: 0)
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(GomokuModule().hasResumableSnapshot(in: store))
    }
}

/// CPU 先手の局で、CPU の初手だけでは「新規」に確認を出さない（#3490）。
@Suite("五目並べ CPU 先手の局の新規対局確認（#3490）")
@MainActor
struct GomokuCPUOpeningProgressTests {
    @Test("人間が白のとき、CPU の初手だけでは失う進行は無く、自分が打つと進行になる")
    func whiteAfterCPUOpening() async throws {
        let model = GomokuModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame(humanSide: .white, aiLevel: -1) // 入門（最弱）にして、CPU の初手の読みを軽くする。
        await model.performAIMoveIfNeeded()
        try #require(model.moveCount >= 1, "前提: CPU が初手を打った")
        #expect(!model.hasProgressToLose)
        let point = try #require(
            (0..<gomokuBoardSize).lazy.flatMap { r in (0..<gomokuBoardSize).map { (r, $0) } }
                .first { model.board.cells[$0.0 * gomokuBoardSize + $0.1] == nil })
        model.tap(row: point.0, col: point.1)
        #expect(model.hasProgressToLose)
    }

    @Test("人間が黒のとき、新規直後は無く、1 手打つと進行になる（対照）")
    func blackFirst() {
        let model = GomokuModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame()
        #expect(!model.hasProgressToLose)
        model.tap(row: 7, col: 7)
        #expect(model.hasProgressToLose)
    }
}
